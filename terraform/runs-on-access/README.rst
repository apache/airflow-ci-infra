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

The IAM roles that let ``.github/workflows/terraform-runs-on.yml`` plan and apply
`terraform/runs-on <../runs-on/README.rst>`_ without any stored AWS credential. This module is
applied **by hand by an account admin** (own state key ``tf-state/runs-on-access.tfstate``) and
never by the workflow, so the workflow cannot widen its own permissions.

Roles
-----

``runs-on-terraform-plan``
    Assumed through GitHub OIDC by pull requests of ``apache/airflow-ci-infra`` and by pushes to
    ``main``. Reads the stack, the state and the license-key parameter **without** decryption
    (``kms:Decrypt`` is denied explicitly: the ``aws/ssm`` key policy would otherwise let
    ``ssm:GetParameter`` return the plain key). Plans run with ``-lock=false``; the role writes
    nothing. Fork pull requests get no OIDC token and cannot use it.
``runs-on-terraform-apply``
    Assumed only by jobs in the ``runs-on-prod`` environment, which ``.asf.yaml`` limits to
    ``main`` and to deployments approved by a required reviewer other than the person who
    triggered them. It can call ``cloudformation:UpdateStack`` on the ``runs-on`` stack only with
    a template from RunsOn's published bucket, only for the versions listed in
    ``runs_on_versions`` (exact template URLs), so a RunsOn upgrade means adding the version there
    and applying this module before bumping ``runs_on_version`` in ``terraform/runs-on``. It can
    also pass the service role below and write the state and its lock file. It holds no
    infrastructure permissions.
``runs-on-cloudformation``
    The stack's CloudFormation service role, which performs every create, update and delete.
    RunsOn documents only "admin rights" for deploying its stack, and its template touches IAM,
    VPC, ECS, Lambda, API Gateway, SQS, DynamoDB, S3, SNS and Budgets, with a set that changes
    between releases, so the role has ``AdministratorAccess`` with explicit denies on top: IAM
    writes only to the roles and instance profile the template names
    (``runs-on-<logical id>-*``) and to service-linked roles, no ``sts:AssumeRole*``, and no
    access to the ``airflow-ci-tfstate`` bucket. The role may attach only the two managed
    policies the template uses, so the ``AppCustomPolicy`` / ``RunnerCustomPolicy`` stack
    parameters cannot give the stack's roles (or the CI runners) more permissions; a custom policy
    needs that list extended here first. A template release that adds an IAM resource
    with a new logical-ID prefix fails its update with ``AccessDenied`` until the list in
    ``main.tf`` is extended.

All trust policies pin the repository by its immutable GitHub IDs (``repository_owner_id``
``47359`` and ``repository_id`` ``321691041``), so a renamed or re-created repository cannot match
them. They accept two forms of the ``sub`` claim: the default ``repo:apache/airflow-ci-infra:...``,
which the repository emits today, and the immutable
``repo:apache@47359/airflow-ci-infra@321691041:...``, which it emits once
`INFRA-28572 <https://issues.apache.org/jira/browse/INFRA-28572>`_ opts it in; see
`Switching to the immutable subject`_. The GitHub OIDC provider already exists in the account (it
is shared with ``apache/airflow``) and is only read here.

Bootstrap order
---------------

1. (Optional, pending INFRA-28572_.) A repository admin opts ``apache/airflow-ci-infra`` into
   immutable OIDC subjects. The roles accept both subject forms and pin the repository by ID
   either way, see `Switching to the immutable subject`_:

   .. code-block:: bash

       gh api -X PUT repos/apache/airflow-ci-infra/actions/oidc/customization/sub \
           -F use_default=true -F use_immutable_subject=true

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
       terraform plan -out=runs-on-access.tfplan   # 3 roles and their policies, nothing else
       terraform apply runs-on-access.tfplan

5. The same admin applies ``terraform/runs-on`` once by hand, which sets ``iam_role_arn`` on the
   stack (the workflow would only do it on the next push that changes ``terraform/runs-on``'s
   ``.tf`` files).
   From then on the workflow plans and applies.

Switching to the immutable subject
----------------------------------

The ID conditions already protect against a renamed or re-created repository, so this is cleanup,
not a security fix. Once INFRA has enabled ``use_immutable_subject``
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
