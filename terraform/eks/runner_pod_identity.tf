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

# The airflow CI workflows pass artifacts between jobs via the S3-backed stash
# actions (.github/actions/stash-s3-*). Runner pods get scoped S3 access
# through EKS Pod Identity — node IAM credentials are deliberately
# unreachable from pods (IMDS hop limit 1 on the EC2NodeClass).
locals {
  # Same-region successor of the us-east-1 `airflow-ci-runner-cache` bucket
  # (bucket names are global, so the regional suffix disambiguates). Contents
  # are disposable inter-job artifacts — nothing was migrated.
  stash_bucket = "airflow-ci-runner-cache-us-east-2"

  # One service account per runner scale set, created by the gha-runner-scale-set
  # chart as "<scale-set-name>-gha-rs-no-permission" in the arc-runners namespace.
  runner_scale_set_names = [
    "airflow-runner-amd-small",
    "airflow-runner-amd-medium",
    "airflow-runner-amd-xl",
    "airflow-runner-arm-small",
    "airflow-runner-arm-medium",
    "airflow-runner-arm-xl",
  ]
}

resource "aws_s3_bucket" "stash" {
  bucket = local.stash_bucket
}

resource "aws_s3_bucket_public_access_block" "stash" {
  bucket = aws_s3_bucket.stash.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Stashes are short-lived hand-offs between jobs of a run; the actions ask for
# ~2-day retention, the lifecycle rule is the backstop that actually deletes.
resource "aws_s3_bucket_lifecycle_configuration" "stash" {
  bucket = aws_s3_bucket.stash.id

  rule {
    id     = "expire-stashes"
    status = "Enabled"

    filter {}

    expiration {
      days = 3
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "runner_pods_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "runner_pods_stash" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${local.stash_bucket}/*"]
  }
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.stash_bucket}"]
  }
}

resource "aws_iam_role" "runner_pods" {
  name               = "airflow-ci-runner-pods"
  assume_role_policy = data.aws_iam_policy_document.runner_pods_assume.json
}

resource "aws_iam_role_policy" "runner_pods_stash" {
  name   = "stash-bucket-access"
  role   = aws_iam_role.runner_pods.id
  policy = data.aws_iam_policy_document.runner_pods_stash.json
}

resource "aws_eks_pod_identity_association" "runner_pods" {
  for_each = toset(local.runner_scale_set_names)

  cluster_name    = module.eks.cluster_name
  namespace       = "arc-runners"
  service_account = "${each.value}-gha-rs-no-permission"
  role_arn        = aws_iam_role.runner_pods.arn
}
