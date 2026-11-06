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

# What every role here shares: the GitHub OIDC trust of apache/airflow-ci-infra. The roles of the
# Terraform (RunsOn Flex) workflow are in runs-on-flex.tf.
locals {
  account_id = data.aws_caller_identity.current.account_id

  # The repository is pinned by its immutable IDs (repository_owner_id and repository_id claims),
  # so a renamed or re-created repository cannot match. Fork pull requests get no OIDC token at all,
  # and the runs-on-prod environment deploys only from main after a required reviewer approves
  # (.asf.yaml).
  github_owner_id      = "47359"
  github_repository_id = "321691041"
  # Both subject forms are accepted: the default one and the immutable one, which the repository
  # emits once github.oidc_subject in .asf.yaml opts it in. Dropping the default form afterwards is
  # optional cleanup (README, "Switching to the immutable subject").
  github_subject_prefixes = [
    "repo:apache/airflow-ci-infra",
    "repo:apache@${local.github_owner_id}/airflow-ci-infra@${local.github_repository_id}",
  ]
  github_subjects = {
    plan = flatten([
      for s in local.github_subject_prefixes : ["${s}:pull_request", "${s}:ref:refs/heads/main"]
    ])
    apply = [for s in local.github_subject_prefixes : "${s}:environment:runs-on-prod"]
  }
  # The weekly report runs on a schedule, so only main.
  usage_report_subjects = [for s in local.github_subject_prefixes : "${s}:ref:refs/heads/main"]
}

data "aws_caller_identity" "current" {}

# Shared with apache/airflow's GithubActionApacheAirflow role, so it is read here, never managed.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
  for_each = merge(local.github_subjects, { usage-report = local.usage_report_subjects })

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_owner_id"
      values   = [local.github_owner_id]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_id"
      values   = [local.github_repository_id]
    }
  }
}

# Read-only role for .github/workflows/runs-on-usage-report.yml, which compares the account's
# on-demand and Spot vCPU usage. GetMetricData has no resource-level permissions.
resource "aws_iam_role" "usage_report" {
  name               = "runs-on-usage-report"
  description        = "Weekly on-demand share report of apache/airflow-ci-infra GitHub Actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust["usage-report"].json
}

data "aws_iam_policy_document" "usage_report" {
  statement {
    actions   = ["cloudwatch:GetMetricData"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "usage_report" {
  name   = "usage-report"
  role   = aws_iam_role.usage_report.name
  policy = data.aws_iam_policy_document.usage_report.json
}
