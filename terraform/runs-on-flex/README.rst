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

RunsOn Flex — the runners from RunsOn's Terraform module
========================================================

This module deploys the same RunsOn runners as `terraform/runs-on <../runs-on/README.rst>`_, from
RunsOn's `Terraform module <https://github.com/runs-on/terraform-aws-runs-on>`_ (Flex, v3.5.1)
instead of its CloudFormation template, into a VPC this module creates with a public subnet in
each of the three us-east-2 zones. Both stacks run side by side until the jobs of
``apache/airflow`` have moved here; the CloudFormation stack is then removed in a separate change.

Why this module
---------------

The CloudFormation template places runners in the first two zones of the region, use2-az1 and
use2-az2 for this account, and has no parameter to change that. On 2026-10-30 those two zones
had the worst Spot capacity in the region for the runners' instance families:

=================================  ==========  ==========  ==========
Spot placement score (1-10)        use2-az1    use2-az2    use2-az3
=================================  ==========  ==========  ==========
x64, 8-16 vCPU (m5-m8 a/i)         1           1           9
x64, 4-8 vCPU                      2           1           8
arm64, 8-64 vCPU (m6g-m8g)         1           1           3
=================================  ==========  ==========  ==========

From 2026-10-25 to 2026-10-30 AWS reclaimed 911 of 16,145 Spot runners (5.6%), at the median
7 minutes after launch, and 30% of all runners ran on-demand. A third zone gives the Spot
allocator the pools where capacity is.

Files
-----

``network.tf``
    VPC (``vpc_cidr``, default ``10.3.0.0/16``), internet gateway, one public subnet per zone ID
    and an S3 gateway endpoint. No NAT: runners get public IPs, as on the CloudFormation stack.
``main.tf``
    The ``runs-on/runs-on/aws//modules/flex`` module with the CloudFormation stack's settings, the
    license-key lookup and the permissions boundary of the stack's roles.
``variables.tf``
    All variables have defaults: ``stack_name`` (``runs-on-flex``), ``runs_on_environment``
    (``flex``), ``github_organization``, ``alert_email``, ``enable_admin_routes`` (``false``) and
    ``vpc_cidr``.
``state.tf``
    S3 backend ``airflow-ci-tfstate`` / ``tf-state/runs-on-flex.tfstate``.

How it differs from the CloudFormation stack
--------------------------------------------

- **Environment.** The stack takes only jobs whose label carries ``env=flex``; the CloudFormation
  stack keeps the default ``production`` and ignores them. That is what lets both run at once.
- **Who creates the resources.** The CloudFormation stack is applied by a role that can only
  resubmit RunsOn's published template; CloudFormation's service role does the work. Here the
  ``runs-on-terraform-flex-apply`` role creates everything itself, with AdministratorAccess and
  the denies in `terraform/runs-on-access/runs-on-flex.tf <../runs-on-access/runs-on-flex.tf>`_:
  IAM writes only on ``runs-on-flex-*`` roles and only with the ``runs-on-flex-boundary``
  permissions boundary, only the two AWS-managed policies the module attaches, no S3 but the
  stack's cache bucket and this state, no role assumption, and us-east-2 only. Anything merged to
  ``main`` here and approved in the ``runs-on-prod`` environment can therefore change any non-IAM
  resource in us-east-2, not just this stack: review pull requests to this module as such.
- **Upgrades** bump the module ``version`` in ``main.tf`` (with the lock file), not a template
  URL. Before a bump, check the new release's IAM role names and managed-policy attachments
  against ``flex_iam_resources`` and ``flex_managed_policies`` in ``runs-on-access``.

Setup
-----

1. **Access (account admin, once).** Apply `terraform/runs-on-access <../runs-on-access/README.rst>`_:
   it adds the ``runs-on-terraform-flex-plan`` and ``-apply`` roles and the
   ``runs-on-flex-boundary`` policy.
2. **License key (manual, once).** The same RunsOn license as the CloudFormation stack, under
   this stack's name. The module receives only the parameter's ARN, so the key never reaches
   Terraform state:

   .. code-block:: bash

       aws ssm put-parameter --region us-east-2 \
           --name /runs-on-flex/license-key \
           --type SecureString \
           --description "RunsOn license key for the runs-on-flex stack (GitHub organization apache)" \
           --value 'RUNS-ON-LICENSE-KEY'

3. **Create the stack.** Merge the pull request that adds this module; the
   ``Terraform (RunsOn Flex)`` workflow plans on ``main`` and applies once a reviewer approves
   ``runs-on-prod``. Set ``enable_admin_routes = true`` in that first change.
4. **GitHub App (with ASF Infra).** Open the ``entry_point`` output → **Register app**. This
   creates a second private GitHub App for this stack; ASF Infra installs it on
   ``apache/airflow`` (and ``.github-private``, for the presets). Then set
   ``enable_admin_routes`` back to ``false`` in a follow-up change.
5. **Move the jobs.** In ``apache/airflow``, add ``/env=flex`` to the RunsOn label templates in
   ``dev/breeze/src/airflow_breeze/global_constants.py``. All jobs of a run must move together:
   the stash actions keep image tars in the cache bucket of the stack that ran the job, so a
   job on the other stack would not find them. Rolling back is removing ``/env=flex``.
6. **Retire the CloudFormation stack** once the runs have been green on this stack for a while:
   a separate change in ``terraform/runs-on`` (remove ``prevent_destroy``, destroy), the old
   GitHub App uninstalled by ASF Infra, and the ``runs-on-terraform-plan``, ``-apply`` and
   ``runs-on-cloudformation`` roles removed from ``runs-on-access``.

Locally, an account admin runs the same steps as the workflow::

    cd terraform/runs-on-flex
    terraform init
    terraform plan -out=runs-on-flex.tfplan
    terraform apply runs-on-flex.tfplan
    terraform output -raw getting_started

Not carried over yet
--------------------

- ``RUNS_ON_SPOT_FORCE_ZONE_SPREAD`` (RunsOn v3.5.0, beta) would spread Spot runners across the
  zones instead of letting the allocator pick; it can be set through ``extra_env_vars`` once the
  three zones have run for a while.
- ``prevent_destroy`` cannot be set on a module; a ``terraform destroy`` of this module is
  stopped only by review.
