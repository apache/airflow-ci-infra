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

variable "stack_name" {
  description = <<-EOT
    RunsOn stack name. Every resource the module creates is named after it, the license-key SSM
    parameter is /<stack_name>/license-key, and terraform/runs-on-access scopes the apply role's
    IAM rights to it, so changing it re-creates the stack and needs an access change.
  EOT
  type        = string
  default     = "runs-on-flex"
}

variable "runs_on_environment" {
  description = <<-EOT
    RunsOn environment: the stack only takes jobs whose label carries env=<this value>. It differs
    from the CloudFormation stack's "production" so both stacks can serve apache/airflow at once and
    jobs move by label.
  EOT
  type        = string
  default     = "flex"
}

variable "github_organization" {
  description = "GitHub organization the runners serve (case-sensitive)."
  type        = string
  default     = "apache"
}

variable "alert_email" {
  description = "Recipient of RunsOn cost reports and alerts; AWS sends an SNS confirmation email on creation."
  type        = string
  default     = "private@airflow.apache.org"
}

variable "enable_admin_routes" {
  description = <<-EOT
    Expose the /setup admin routes on the public entry point. Set to true only while registering
    (or re-registering) the GitHub App, then back to false.
  EOT
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR of the runners' VPC; must not overlap existing VPCs in the account (10.0.0.0/16,
    10.1.0.0/16 and the CloudFormation stack's 10.2.0.0/16 are taken).
  EOT
  type        = string
  default     = "10.3.0.0/16"
}
