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

variable "vpc_cidr" {
    type = string
    description = "The cidr of the vpc holding ASG of github action self hosted runners."
}

variable "vpc_azs" {
    type = list(string)
    description = "List of vpc azs that subnets should be created."
}

variable "tags" {
    type = map(string)
    description = "Tags of the resources"
}

variable "ami_owner" {
    type = string
    description = "The owner of the ami in AWS."
}

variable "ami_name" {
    type = string
    description = "The ami name."
}

variable "runner_instance_type" {
    type = string
    description = "The instance type of the github actions runners."
}

variable "asg_max_size" {
    type = number
    description = "Max size the ASG can scale runners."
}

variable "asg_min_size" {
    type = number
    description = "Min size the ASG can scale runners."
}
