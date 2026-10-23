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
    a template from RunsOn's published bucket (``template-v*.yaml``), pass the service role
    below, and write the state and its lock file. It holds no infrastructure permissions.
``runs-on-cloudformation``
    The stack's CloudFormation service role, which performs every create, update and delete.
    RunsOn documents only "admin rights" for deploying its stack, and its template touches IAM,
    VPC, ECS, Lambda, API Gateway, SQS, DynamoDB, S3, SNS and Budgets, with a set that changes
    between releases, so the role has ``AdministratorAccess`` with explicit denies on top: IAM
    writes only to the roles and instance profile the template names
    (``runs-on-<logical id>-*``) and to service-linked roles, no ``sts:AssumeRole*``, and no
    access to the ``airflow-ci-tfstate`` bucket. A template release that adds an IAM resource
    with a new logical-ID prefix fails its update with ``AccessDenied`` until the list in
    ``main.tf`` is extended.

All trust policies use GitHub's immutable OIDC subject,
``repo:apache@47359/airflow-ci-infra@321691041:...``, so a renamed or re-created repository
cannot match them. The GitHub OIDC provider already exists in the account (it is shared with
``apache/airflow``) and is only read here.

Bootstrap order
---------------

1. A repository admin opts ``apache/airflow-ci-infra`` into immutable OIDC subjects (until then
   both roles refuse the workflow):

   .. code-block:: bash

       gh api -X PUT repos/apache/airflow-ci-infra/actions/oidc/customization/sub \
           -F use_default=true -F use_immutable_subject=true

2. Merge, so that ``.asf.yaml`` creates the ``runs-on-prod`` environment. This happens before the
   roles exist, so the first workflow run on ``main`` cannot assume them, and a job never sees
   the environment without its protection rules.
3. An account admin applies this module::

       cd terraform/runs-on-access
       terraform init
       terraform plan -out=runs-on-access.tfplan   # 3 roles and their policies, nothing else
       terraform apply runs-on-access.tfplan

4. The same admin applies ``terraform/runs-on`` once by hand, which sets ``iam_role_arn`` on the
   stack (the workflow would only do it on the next push that touches ``terraform/runs-on``).
   From then on the workflow plans and applies.
