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

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# The license key is never in Terraform state: RunsOn accepts LicenseKey as the ARN of an SSM
# SecureString parameter that MUST be named /<stack name>/license-key, and only the stack's
# service role decrypts it. The parameter is created by hand (see README.rst); this lookup
# without decryption only proves it exists before the stack is planned, storing the ciphertext.
data "aws_ssm_parameter" "license_key" {
  name            = "/${var.stack_name}/license-key"
  with_decryption = false
}

resource "aws_cloudformation_stack" "runs_on" {
  name         = var.stack_name
  template_url = "https://runs-on.s3.eu-west-1.amazonaws.com/cloudformation/template-${var.runs_on_version}.yaml"
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]

  # Everything not listed keeps the template default; the values match the stack validated on
  # 2026-09-25 (see the AIP-118 appendix) apart from the organization and the CIDR.
  parameters = {
    GithubOrganization      = var.github_organization
    LicenseKey              = data.aws_ssm_parameter.license_key.arn
    EmailAddress            = var.alert_email
    Environment             = "production"
    VpcCidrBlock            = var.vpc_cidr
    Private                 = "false" # runners get public IPs: no NAT cost, Docker Hub pulls per runner IP
    SSHAllowed              = "false"
    SSMAllowed              = "true"
    EnableAdminRoutes       = "true" # /setup for the GitHub App registration
    EnableEphemeralRegistry = "false"
    RunnerMaxRuntime        = "720"
    S3CacheExpirationInDays = "10"
    AppSize                 = "small"
    SpotCircuitBreaker      = "2/15/30"
    CostReportsEnabled      = "daily"
    AppBudgetDailyUsd       = "10" # alert only, not a spending cap
  }

  timeout_in_minutes = 30

  lifecycle {
    # The stack owns the runners for apache/airflow; a destroy is a deliberate, separate change.
    prevent_destroy = true
  }
}
