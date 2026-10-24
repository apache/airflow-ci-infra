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

CI Infrastructure for Apache Airflow
====================================

RunsOn deployment
-----------------

`AIP-118 <https://cwiki.apache.org/confluence/spaces/AIRFLOW/pages/451974652>`_ selected
`RunsOn <https://runs-on.com/>`_ for Airflow's self-hosted GitHub Actions runners. The Terraform
module that creates its CloudFormation stack, and the runner presets, live in
`terraform/runs-on <terraform/runs-on/README.rst>`_; the ``Terraform (RunsOn)`` workflow plans
and applies it, with the AWS roles from
`terraform/runs-on-access <terraform/runs-on-access/README.rst>`_.
