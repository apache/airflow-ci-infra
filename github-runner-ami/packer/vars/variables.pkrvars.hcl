# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

vpc_id = "vpc-d73487bd"
ami_name = "airflow-runner-ami"
aws_regions = ["eu-central-1", "us-east-2"]
packer_role_arn = "arn:aws:iam::827901512104:role/packer-role"
runner_version = "2.299.1-airflow1"
session_manager_instance_profile_name = "packer_ssm_instance_profile"
