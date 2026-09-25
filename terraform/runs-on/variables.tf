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

variable "region" {
  description = "AWS region for the RunsOn stack and its runners."
  type        = string
  default     = "us-east-2"
}

variable "stack_name" {
  description = <<-EOT
    CloudFormation stack name. RunsOn derives the license-key SSM parameter name from it
    (/<stack_name>/license-key), so changing it means re-creating the parameter.
  EOT
  type        = string
  default     = "runs-on"
}

variable "runs_on_version" {
  description = "RunsOn release to deploy; selects the version-pinned CloudFormation template."
  type        = string
  default     = "v3.3.2"
}

variable "github_organization" {
  description = "GitHub organization the runners serve (case-sensitive)."
  type        = string
  default     = "apache"
}

variable "alert_email" {
  description = "Recipient of RunsOn cost reports and alerts; AWS sends an SNS confirmation email on creation."
  type        = string
  default     = "shahar@apache.org"
}

variable "vpc_cidr" {
  description = "CIDR of the VPC the stack creates; must not overlap existing VPCs in the account (10.1.0.0/16 is taken)."
  type        = string
  default     = "10.2.0.0/16"
}
