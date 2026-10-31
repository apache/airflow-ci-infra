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

# The license key is never in Terraform state: the Flex module accepts license_key as the ARN of
# an SSM SecureString parameter named /<stack name>/license-key, created by hand (README.rst). This
# lookup without decryption only proves it exists before the stack is planned.
data "aws_ssm_parameter" "license_key" {
  name            = "/${var.stack_name}/license-key"
  with_decryption = false
}

data "aws_caller_identity" "current" {}

module "runs_on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.5.1"

  stack_name          = var.stack_name
  environment         = var.runs_on_environment
  github_organization = var.github_organization
  license_key         = data.aws_ssm_parameter.license_key.arn
  email               = var.alert_email

  vpc_id            = aws_vpc.runners.id
  public_subnet_ids = [for zone_id in local.zone_ids : aws_subnet.public[zone_id].id]
  private_mode      = "false"

  # Created in terraform/runs-on-access; the apply role cannot create a stack role without it.
  permission_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.stack_name}-boundary"

  # The values of the CloudFormation stack (terraform/runs-on/main.tf); everything else keeps the
  # module default.
  ssh_allowed           = false
  ssm_allowed           = true
  enable_admin_routes   = var.enable_admin_routes
  enable_ecr            = false
  runner_max_runtime    = 720
  cache_expiration_days = 10
  app_size              = "small"
  # With hundreds of runners two interruptions in 15 minutes are routine, so the default 2/15/30
  # keeps Spot off (terraform/runs-on/main.tf).
  spot_circuit_breaker = "30/15/10"
  enable_cost_reports  = "daily"
  app_budget_daily_usd = 10 # alert only, not a spending cap
}
