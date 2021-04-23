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
aws_region = "eu-central-1"
subnet_id = "subnet-72ed3c0e"
packer_role_arn = "arn:aws:iam::827901512104:role/packer-role"
<<<<<<< HEAD
runner_version = "0.0.1"
kms_key_arn = "arn:aws:kms:eu-central-1:827901512104:key/48a58710-7ac6-4f88-995f-758a6a450faa"
=======
runner_version = "2.278.0-airflow2"
>>>>>>> e036ae904379e7364c93a7f23456c3507fb749c9
session_manager_instance_profile_name = "packer_ssm_instance_profile"
