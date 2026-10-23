.. Licensed to the Apache Software Foundation (ASF) under one
   or more contributor license agreements.  See the NOTICE file
   distributed with this work for additional information
   regarding copyright ownership.  The ASF licenses this file
   to you under the Apache License, Version 2.0 (the
   "License"); you may not use this file except in compliance
   with the License.  You may obtain a copy of the License at

..   http://www.apache.org/licenses/LICENSE-2.0

.. Unless required by applicable law or agreed to in writing,
   software distributed under the License is distributed on an
   "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
   KIND, either express or implied.  See the License for the
   specific language governing permissions and limitations
   under the License.

RunsOn — self-hosted CI runners on AWS
======================================

`RunsOn <https://runs-on.com/>`_ is the approach selected by
`AIP-118 <https://cwiki.apache.org/confluence/spaces/AIRFLOW/pages/451974652>`_ for Airflow's
self-hosted GitHub Actions runners. It packages runner provisioning into a CloudFormation stack in
Airflow's AWS account: a small control plane (ECS Fargate + API Gateway) receives GitHub's
``workflow_job`` webhooks and launches one ephemeral EC2 instance per job, Spot first, sized from
the job's ``runs-on:`` label. RunsOn's `free open-source license <https://runs-on.com/billing/free/>`_
covers the product; EC2/EBS/S3 usage is billed to the account.

This module creates the stack for the **apache** organization from RunsOn's published,
version-pinned template, with the configuration validated on 2026-09-25 (full ``Tests (AMD)``
graph green apart from two non-hermetic tests — see the AIP-118 appendix).

Files
-----

``main.tf``
    The ``aws_cloudformation_stack`` resource, its parameters and the license-key lookup.
``variables.tf``
    All variables have defaults: ``stack_name`` (``runs-on``), ``github_organization``
    (``apache``), ``alert_email`` (``private@airflow.apache.org``), ``runs_on_version``
    (``v3.3.2``), ``enable_admin_routes`` (``false``) and ``vpc_cidr`` (``10.2.0.0/16``). The
    region (``us-east-2``) is not a variable: it is hard-coded in ``provider.tf``, the backend in
    ``state.tf`` and the commands below, so a move changes all of them.
``state.tf``
    S3 backend ``airflow-ci-tfstate`` / ``tf-state/runs-on.tfstate`` (its own key next to the
    EKS states).
``runs-on.yml.example``
    Runner presets for Airflow's three size classes, to be committed as ``.github/runs-on.yml``
    in the organization's ``.github-private`` repository (or a repository's default branch).

Step 1 — create the license-key parameter (manual, once)
--------------------------------------------------------

RunsOn accepts ``LicenseKey`` either as plain text or as the ARN of an SSM Parameter Store
parameter that must be named ``/<stack name>/license-key`` (`reference
<https://runs-on.com/docs/maintenance/configuration/flex/cloudformation/>`_). The ARN form keeps
the key out of Terraform variables, plan output and state: ``main.tf`` reads the parameter
**without decryption** (only to prove it exists) and passes its ARN; the stack's service role is
the only principal that decrypts it. Secrets Manager is not supported by the template.

.. code-block:: bash

    aws ssm put-parameter --region us-east-2 \
        --name /runs-on/license-key \
        --type SecureString \
        --description "RunsOn license key for the runs-on stack (GitHub organization apache)" \
        --value 'RUNS-ON-LICENSE-KEY'

Use the default SSM KMS key (``alias/aws/ssm``): the template grants the stack's role access to
that key; a customer key would need an extra key policy. Never put the key in ``terraform.tfvars``.
Rotating the key does not go through Terraform: ``LicenseKey`` stays the same ARN, so an apply
does not make the stack read the new value. The control-plane service reads the parameter itself,
so overwrite it and restart the service:

.. code-block:: bash

    aws ssm put-parameter --region us-east-2 --name /runs-on/license-key \
        --type SecureString --overwrite --value 'NEW-RUNS-ON-LICENSE-KEY'
    service="$(aws cloudformation describe-stack-resource --region us-east-2 \
        --stack-name runs-on --logical-resource-id RunsOnWorkerService \
        --query StackResourceDetail.PhysicalResourceId --output text)"
    aws ecs update-service --region us-east-2 --force-new-deployment \
        --cluster "$(cut -d / -f 2 <<< "${service}")" --service "${service}"

The free open-source license is issued per GitHub organization; the key must be the one issued
for ``apache``.

Step 2 — plan and apply
-----------------------

Changes go through pull requests. The ``Terraform (RunsOn)`` workflow
(``.github/workflows/terraform-runs-on.yml``) plans every pull request that touches this
directory, plans again on ``main`` after the merge, and applies that plan once a required reviewer
approves the ``runs-on-prod`` environment. The plan artifact is kept 7 days; if approval comes
later, use "Re-run all jobs" on the run, which plans again. It authenticates with GitHub OIDC; the AWS roles it
assumes, and the CloudFormation service role the stack runs as, are in
`terraform/runs-on-access <../runs-on-access/README.rst>`_, which is applied by hand first.

The state is in the S3 backend of ``state.tf``, locked with ``use_lockfile``. An account admin can
still run the same steps locally::

    cd terraform/runs-on
    terraform init
    terraform plan -out=runs-on.tfplan
    terraform apply runs-on.tfplan          # ~10 minutes on creation
    terraform output

The ``apache`` stack already exists: it was created on 2026-09-25 with local state, which was then
moved to S3 with ``terraform init -migrate-state``. A plan against it must therefore never propose
to create the stack; if it does, Terraform is not reading the S3 state, and an apply would fail
with ``AlreadyExistsException``. On a fresh account the plan shows exactly one resource to create
(``aws_cloudformation_stack.runs_on``) and reads two data sources (the SSM parameter and the
caller identity).

Step 3 — register the GitHub App and the presets
------------------------------------------------

1. Apply with ``-var enable_admin_routes=true``, open the ``entry_point`` output → **Register
   app**, then apply again without the variable to remove the ``/setup`` routes from the public
   entry point. This creates a private GitHub App in the organization and installs it; for
   ``apache`` this is done together with ASF Infra, who also grant the app access to
   ``apache/airflow`` and to ``.github-private`` if the presets live there. Re-registering the
   app needs the same temporary apply.
2. Commit ``runs-on.yml.example`` as ``.github/runs-on.yml`` in ``apache/.github-private``
   (stack parameter ``RunnerConfigAutoExtendsFrom``, default ``.github-private``). RunsOn reads
   ``.github/runs-on.yml`` in a public repository **only from its default branch**, so presets
   cannot be trialled from a feature branch; the validation therefore spelled the same values
   out in the labels.
3. Point jobs at the runners:

   .. code-block:: yaml

       runs-on: runs-on=${{ github.run_id }}/runner=airflow-amd-medium

   ``runs-on=<run id>`` is mandatory (it routes the job and namespaces the runner). Labels can
   also carry everything inline, which is what the validation did:
   ``runs-on=<id>/family=m7a+m7i+m6a+m6i/image=ubuntu22-full-x64/volume=150gb/cpu=8/ram=32``.
   ``runs-on/action`` (per-job cost line in the job summary) is already on the ASF GitHub Actions
   allowlist.

Upgrades and changes
--------------------

Bump ``runs_on_version`` (or any parameter) and ``terraform plan`` / ``apply``: the resource
always resubmits the template URL, which is what RunsOn's `upgrade guide
<https://runs-on.com/docs/maintenance/upgrades/>`_ requires (a reused processed template can
silently skip parameter changes). Minor and patch releases have no downtime; major releases may.
Rollback is the previous ``runs_on_version``. The apply role may only deploy the templates listed
in ``runs_on_versions`` in `terraform/runs-on-access <../runs-on-access/README.rst>`_, so a
``runs_on_version`` bump first needs the new version added there and applied by an admin. Template ``v3.3.2`` has SHA-256
``3017805d77c1d717fdd229a1e1242db12c985944699d3d8dca01f6f28b35c16d``.

Every plan shows ``"LicenseKey" = "****" -> "arn:...:parameter/runs-on/license-key"``:
CloudFormation masks ``NoEcho`` parameters when Terraform reads the stack, and the AWS provider
stores the mask. The value sent on apply is the same ARN, so that line alone changes nothing. Do
not add it to ``ignore_changes``: the provider would then send the literal ``****`` as the license
key.

``prevent_destroy`` is set on the stack: a ``terraform destroy`` fails until the lifecycle block is
removed on purpose. Deleting the stack also needs its cache bucket emptied first if CloudFormation
stops on it.

What the stack contains
-----------------------

VPC ``10.2.0.0/16`` with public and private subnets (``Private=false`` → runners get public IPs and
no NAT, so each runner pulls from Docker Hub from its own address), an ECS Fargate service for the
control plane, an API Gateway entry point (``/github/webhooks``, plus ``/``, ``/setup`` and
``/readyz`` only while ``enable_admin_routes`` is true), an S3 cache bucket (``cache_bucket``
output; the runners' instance role can read and write the ``cache/`` prefix, lifecycle
``S3CacheExpirationInDays``), the EC2 instance role and launch templates, DynamoDB tables for
locks and job tracking, an SNS alert topic, an AWS Budget (``AppBudgetDailyUsd``,
alert only — not a spending cap), the CloudWatch dashboard ``RunsOnDashboard-*`` (queue health,
scheduling trend, queue-duration P50/P90, Spot circuit breaker), log groups
``/aws/ecs/<stack>/runs-on-worker`` and ``<stack>-EC2InstanceLogGroup-*``, and a daily cost report
by email.

Observability
-------------

- CloudWatch dashboard and log groups above; ``roc`` CLI (`docs
  <https://runs-on.com/docs/observability/cli/>`_): ``roc stack doctor``, ``roc stack logs``,
  ``roc logs <job url> --watch``, ``roc connect <job url>`` over SSM (``SSMAllowed=true``).
- Optional OTLP export (``OtelExporterEndpoint`` / ``OtelExporterHeaders`` + ``extras=otel`` on the
  label) to SigNoz or any OTLP backend; RunsOn publishes a SigNoz dashboard. Not deployed by
  the stack.

Things learned in the validation
--------------------------------

- Runner instances use IMDSv2 with a hop limit of 2, so Docker containers started by a job can
  obtain the instance role's credentials. Tests that assume "no AWS credentials" must set
  ``AWS_EC2_METADATA_DISABLED=true`` (fixed in ``apache/airflow#73707``). The same credentials
  can read and write the whole ``cache/`` prefix, so any job on these runners can overwrite
  objects that later runs download.
- Untrusted code is meant to stay off these runners. Airflow's CI (``apache/airflow#74889``)
  routes only pushes, schedules and dispatches on ``apache/airflow``, branches of
  ``apache/airflow`` itself, and pull requests labelled ``use self-hosted runners`` that a
  committer approved at their head commit to RunsOn; everything else runs on GitHub-hosted
  runners. That routing is cooperative, not a boundary: a ``pull_request`` run uses the workflow
  file of the pull request, so a fork can ask for a RunsOn label itself. The boundary is GitHub's
  fork-workflow approval, which must be set to "Require approval for all external contributors"
  for ``apache/airflow`` (ASF Infra).
- Airflow's stash actions (image tars, mount caches, prek cache) store payloads in the stack's
  cache bucket under ``cache/airflow-stash/``, so multi-gigabyte payloads never leave the region.
  Payloads are content-addressed (``cache/airflow-stash/sha256/<digest>.tar``); the digest itself
  is kept as a GitHub-scoped ASF stash, and a restore whose download does not match it is a cache
  miss. Overwriting an object in the bucket therefore cannot change what a later run restores.
- Job pickup (job queued → runner started) was 29 s at the median, 51 s at p90; a full
  ``Tests (AMD)`` graph finished in 53 minutes.
- Magic cache (``extras=s3-cache``) was not enabled: it only speeds up ``actions/cache`` and
  ``setup-*`` caches and requires ``runs-on/action`` before every ``upload-artifact``.
- EC2 quotas in us-east-2 (``All Standard Spot Instance Requests`` 3000 vCPU, on-demand 2000)
  were enough for ~130 concurrent jobs.
