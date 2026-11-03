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

# The license key is never in Terraform state: RunsOn accepts LicenseKey as the ARN of an SSM
# SecureString parameter that MUST be named /<stack name>/license-key, and only the stack's
# service role decrypts it. The parameter is created by hand (see README.rst); this lookup
# without decryption only proves it exists before the stack is planned, storing the ciphertext.
data "aws_ssm_parameter" "license_key" {
  name            = "/${var.stack_name}/license-key"
  with_decryption = false
}

data "aws_caller_identity" "current" {}

# The stack was removed from this configuration on purpose: every job of apache/airflow runs on
# terraform/runs-on-flex since 2026-11-01, and applying this change is what deletes the stack
# (the Terraform (RunsOn) workflow, after the runs-on-prod approval). The template retains the
# cache and access-log buckets (DeletionPolicy RetainExceptOnCreate); delete them by hand.
