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


Terraform: Airflow infrastructure as code
========================================

In this folder, you will find the Terraform code to deploy the Airflow infrastructure on AWS.

The `eks` folder contains the code to deploy the Airflow EKS cluster and all the required resources.

Requirements
------------

In order to deploy the infrastructure, you need to have the following tools installed:

- Terraform >= 1.9 (e.g. via `tfenv <https://github.com/tfutils/tfenv>`_: ``tfenv install 1.9.5``)
- Configure your AWS and EKS credentials :ref:`doc <aws_configuration>`

State
~~~~~

The remote state lives in the ``airflow-ci-tfstate`` S3 bucket (``us-east-2``) with the
``TerraformLocks`` DynamoDB table. Credentials/profile are taken from the environment
(``AWS_PROFILE=...``), which also works for a future GitHub Actions plan/apply workflow
assuming a role via OIDC — nothing is hardcoded in the provider.

.. note::

   The bucket also contains ``tf-state/eks.tfstate`` — the **2024 deployment's** state.
   Its cluster is gone but leftovers (the ``airflow-vpc`` VPC, old node-group IAM roles,
   the ``/aws/eks/airflow/cluster`` log group, the ``alias/eks/airflow`` KMS alias)
   still exist in the account and are **deliberately left untouched**. The current
   deployment therefore uses its own state key (``tf-state/eks-airflow-ci.tfstate``)
   and the cluster name ``airflow-ci``, so every derived resource name avoids the 2024
   ones. Do not import, modify, or delete the 2024 resources from this configuration.
   For local iteration without touching the shared state, drop a
   ``backend_override.tf`` (gitignored) with ``terraform { backend "local" {} }``
   next to the sources.

Plan and deploy the infrastructure
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   cd eks

   # Initialize the Terraform modules and install the required providers,
   # just the first time or when you add a new module
   AWS_PROFILE=airflow terraform init

   # Plan the infrastructure
   AWS_PROFILE=airflow terraform plan -out=terraform.tfplan

   # Deploy the infrastructure after reviewing the plan
   AWS_PROFILE=airflow terraform apply terraform.tfplan
