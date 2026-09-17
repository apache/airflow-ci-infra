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

terraform {

  backend "s3" {
    region = "us-east-2"
    bucket = "airflow-ci-tfstate"
    # Fresh key for the 2026 airflow-ci cluster. tf-state/eks.tfstate is the
    # 2024 deployment's state and is deliberately left untouched (its cluster
    # is gone but the VPC/IAM leftovers still exist and must not be disturbed).
    key     = "tf-state/eks-airflow-ci.tfstate"
    encrypt = true
    # S3-native locking (.tflock object next to the state). Replaces the
    # deprecated dynamodb_table locking; the TerraformLocks DynamoDB table is
    # still referenced by the 2024 state and must not be deleted.
    use_lockfile = true
  }
}
