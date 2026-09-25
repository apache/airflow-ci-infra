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
    (``apache``), ``alert_email`` (``shahar@apache.org``), ``runs_on_version`` (``v3.3.2``),
    ``vpc_cidr`` (``10.2.0.0/16``) and ``region`` (``us-east-2``).
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
Rotating the key is ``aws ssm put-parameter --overwrite`` followed by a stack update.

The free open-source license is issued per GitHub organization; the key must be the one issued
for ``apache``.

Step 2 — plan and apply
-----------------------

For the first, local run, keep the shared S3 state out of the way with a gitignored override::

    cd terraform/runs-on
    printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
    terraform init
    terraform plan -out=runs-on.tfplan
    terraform apply runs-on.tfplan          # ~10 minutes
    terraform output

The plan must show exactly one resource to create (``aws_cloudformation_stack.runs_on``) and read
one data source (the SSM parameter). Delete ``backend_override.tf`` and run ``terraform init
-migrate-state`` to move the state to S3 once the future GitHub Actions workflow takes over;
the workflow only needs an OIDC role, nothing secret.

Step 3 — register the GitHub App and the presets
------------------------------------------------

1. Open the ``entry_point`` output → **Register app**. This creates a private GitHub App in the
   organization and installs it; for ``apache`` this is done together with ASF Infra, who also
   grant the app access to ``apache/airflow`` and to ``.github-private`` if the presets live there.
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
Rollback is the previous ``runs_on_version``. Template ``v3.3.2`` has SHA-256
``3017805d77c1d717fdd229a1e1242db12c985944699d3d8dca01f6f28b35c16d``.

``prevent_destroy`` is set on the stack: a ``terraform destroy`` fails until the lifecycle block is
removed on purpose. Deleting the stack also needs its cache bucket emptied first if CloudFormation
stops on it.

What the stack contains
-----------------------

VPC ``10.2.0.0/16`` with public and private subnets (``Private=false`` → runners get public IPs and
no NAT, so each runner pulls from Docker Hub from its own address), an ECS Fargate service for the
control plane, an API Gateway entry point (``/``, ``/setup``, ``/readyz`` only), an S3 cache bucket
(``cache_bucket`` output; the runners' instance role can read and write the ``cache/`` prefix,
lifecycle ``S3CacheExpirationInDays``), the EC2 instance role and launch templates, DynamoDB
tables for locks and job tracking, an SNS alert topic, an AWS Budget (``AppBudgetDailyUsd``,
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
  ``AWS_EC2_METADATA_DISABLED=true`` (fixed in ``apache/airflow#73707``).
- Airflow's stash actions (image tars, mount caches, prek cache) were pointed at the stack's cache
  bucket under ``cache/airflow-stash/``, so multi-gigabyte payloads never leave the region.
- Job pickup (job queued → runner started) was 29 s at the median, 51 s at p90; a full
  ``Tests (AMD)`` graph finished in 53 minutes.
- Magic cache (``extras=s3-cache``) was not enabled: it only speeds up ``actions/cache`` and
  ``setup-*`` caches and requires ``runs-on/action`` before every ``upload-artifact``.
- EC2 quotas in us-east-2 (``All Standard Spot Instance Requests`` 3000 vCPU, on-demand 2000)
  were enough for ~130 concurrent jobs.
