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

# Credentials come from the environment (AWS_PROFILE locally, the OIDC role in the
# Terraform (RunsOn Flex) workflow) — do not hardcode a profile here.
provider "aws" {
  # Also hard-coded in the backend (state.tf), the zone IDs (network.tf) and the README commands;
  # change all together.
  region = "us-east-2"

  default_tags {
    tags = {
      Project   = "airflow-ci"
      ManagedBy = "terraform"
      Repo      = "apache/airflow-ci-infra"
    }
  }
}
