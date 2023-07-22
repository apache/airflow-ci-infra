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

- `tfenv <https://github.com/tfutils/tfenv>`_ to manage Terraform versions
- Configure your AWS and EKS credentials :ref:`doc <aws_configuration>`


Configure Terraform
~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   cd eks
   tfenv install 1.5.3

Plan and deploy the infrastructure
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   # Initialize the Terraform modules and install the required providers,
   # just the first time or when you add a new module
   AWS_PROFILE=airflow terraform init

   # Plan the infrastructure
   AWS_PROFILE=airflow terraform plan -out=terraform.tfplan

   # Deploy the infrastructure after reviewing the plan
   AWS_PROFILE=airflow terraform apply terraform.tfplan
