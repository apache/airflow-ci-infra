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

AWS access for the RunsOn Terraform workflow
============================================

The IAM roles that let ``.github/workflows/terraform-runs-on-flex.yml`` plan and apply
`terraform/runs-on-flex <../runs-on-flex/README.rst>`_ without any stored AWS credential, and the
role of the weekly usage report. This module is applied **by hand by an account admin** (own state
key ``tf-state/runs-on-access.tfstate``) and never by the workflow, so the workflow cannot widen
its own permissions.

Roles
-----

``runs-on-terraform-flex-plan``
    Assumed through GitHub OIDC by pull requests of ``apache/airflow-ci-infra`` and by pushes to
    ``main``. ``ReadOnlyAccess``, which refreshing the module's resources needs, with denies that
    keep secrets out of a pull request's reach: no S3 object but this module's state, no
    ``kms:Decrypt`` through SSM (the ``aws/ssm`` key policy would otherwise let
    ``ssm:GetParameter`` return the plain license key) and no Secrets Manager values. Plans run
    with ``-lock=false``; the role writes nothing. Fork pull requests get no OIDC token and cannot
    use it.
``runs-on-terraform-flex-apply``
    Assumed only by jobs in the ``runs-on-prod`` environment, which ``.asf.yaml`` limits to
    ``main`` and to deployments approved by a required reviewer other than the person who
    triggered them. It creates the stack's resources itself. RunsOn documents only "admin rights"
    for deploying its stack, and the module's resource set changes between releases, so the role
    has ``AdministratorAccess`` with explicit denies on top (``runs-on-flex.tf``): IAM writes only
    to ``runs-on-flex-*`` roles and instance profiles and to service-linked roles, every role it
    creates must carry the ``runs-on-flex-boundary`` permissions boundary, only the two managed
    policies the module attaches, no ``sts:AssumeRole*``, no S3 but the stack's cache bucket
    (``runs-on-flex-cache-*``) and this module's state and lock file, and us-east-2 only (IAM,
    STS and Budgets are global). A module release that names an IAM role outside that prefix or
    attaches another managed policy fails its apply with ``AccessDenied`` until the lists in
    ``runs-on-flex.tf`` are extended.
``runs-on-flex-boundary``
    The permissions boundary of every role the stack creates, so the ceiling of what a Lambda
    function, an ECS task or a runner instance of the stack can do whatever its own policies say:
    no IAM writes, ``iam:PassRole`` and ``sts:AssumeRole`` only on the stack's own roles,
    us-east-2 only (plus the global endpoints the module's roles call) and no access to the
    ``airflow-ci-tfstate`` bucket.
``runs-on-usage-report``
    Assumed through GitHub OIDC by workflows running on ``main`` of ``apache/airflow-ci-infra``,
    for the weekly ``.github/workflows/runs-on-usage-report.yml``. It can only call
    ``cloudwatch:GetMetricData``, to compare the account's on-demand and Spot vCPU usage.

All trust policies pin the repository by its immutable GitHub IDs (``repository_owner_id``
``47359`` and ``repository_id`` ``321691041``), so a renamed or re-created repository cannot match
them. They accept two forms of the ``sub`` claim: the default ``repo:apache/airflow-ci-infra:...``
and the immutable ``repo:apache@47359/airflow-ci-infra@321691041:...``, which the repository emits
once ``github.oidc_subject`` in ``.asf.yaml`` opts it in; see `Switching to the immutable subject`_. The GitHub OIDC provider already exists in the account (it
is shared with ``apache/airflow``) and is only read here.

Bootstrap order
---------------

1. ``github.oidc_subject`` in ``.asf.yaml`` opts ``apache/airflow-ci-infra`` into immutable OIDC
   subjects. The roles accept both subject forms and pin the repository by ID either way, see
   `Switching to the immutable subject`_.
2. Merge, so that ``.asf.yaml`` creates the ``runs-on-prod`` environment. This happens before the
   roles exist, so the first workflow run on ``main`` cannot assume them, and a job never sees
   the environment without its protection rules.
3. Check that ``runs-on-prod`` exists with its protection rules before creating the roles. A
   missing or partly applied ``.asf.yaml`` block would let GitHub create the environment
   unprotected on first use, and the apply role trusts that environment alone:

   .. code-block:: bash

       gh api repos/apache/airflow-ci-infra/environments/runs-on-prod \
           --jq '{rules: .protection_rules, policy: .deployment_branch_policy}'
       gh api repos/apache/airflow-ci-infra/environments/runs-on-prod/deployment-branch-policies \
           --jq '[.branch_policies[].name]'

   Expect a ``required_reviewers`` rule with ``prevent_self_review`` and only ``main``; stop
   otherwise.
4. An account admin applies this module::

       cd terraform/runs-on-access
       terraform init
       terraform plan -out=runs-on-access.tfplan   # 3 roles, their policies and the boundary
       terraform apply runs-on-access.tfplan

   From then on the ``Terraform (RunsOn Flex)`` workflow plans and applies
   ``terraform/runs-on-flex``.

Switching to the immutable subject
----------------------------------

The ID conditions already protect against a renamed or re-created repository, so this is cleanup,
not a security fix. Once ``.asf.yaml`` has enabled ``use_immutable_subject``
(``gh api repos/apache/airflow-ci-infra/actions/oidc/customization/sub`` shows
``sub_claim_prefix`` as ``repo:apache@47359/airflow-ci-infra@321691041``), the tokens change form at
once and the roles keep working because they trust both. After one green pull-request plan and one
green apply on ``main`` with the new form:

1. Remove ``"repo:apache/airflow-ci-infra"`` from ``github_subject_prefixes`` in ``main.tf`` and
   shorten the comment above it.
2. Drop this section and the two-forms sentence above; make step 1 of the bootstrap order a plain
   prerequisite again.
3. An account admin applies this module by hand (``terraform plan`` shows only the two trust
   policies changing in place). The pull-request plan check is green before that apply, because
   both forms are still trusted; re-run it afterwards.
