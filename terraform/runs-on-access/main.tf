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

locals {
  account_id = data.aws_caller_identity.current.account_id
  stack_arn  = "arn:aws:cloudformation:us-east-2:${local.account_id}:stack/runs-on/*"
  state      = "arn:aws:s3:::airflow-ci-tfstate/tf-state/runs-on.tfstate"

  # Any release template RunsOn publishes (vX.Y.Z, one-digit major, one- or two-digit minor and
  # patch), so an upgrade (or a rollback) is a reviewed change of runs_on_version in
  # terraform/runs-on alone. "?" matches exactly one character, unlike "*", so pre-release or other
  # objects in the bucket (template-v3.6.0-rc1.yaml, sub-paths) and other buckets stay out of reach.
  runs_on_template_urls = [
    for p in setproduct(["?", "??"], ["?", "??"]) :
    "https://runs-on.s3.eu-west-1.amazonaws.com/cloudformation/template-v?.${p[0]}.${p[1]}.yaml"
  ]

  # The repository is pinned by its immutable IDs (repository_owner_id and repository_id claims),
  # so a renamed or re-created repository cannot match. Fork pull requests get no OIDC token at all,
  # and the runs-on-prod environment deploys only from main after a required reviewer approves
  # (.asf.yaml).
  github_owner_id      = "47359"
  github_repository_id = "321691041"
  # Both subject forms are accepted: the default one the repository emits today and the immutable
  # one it emits once INFRA-28572 opts it in. Dropping the default form afterwards is optional
  # cleanup (README, "Switching to the immutable subject").
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

  # IAM names the RunsOn template generates for the runs-on stack: <stack>-<logical id>-<suffix>.
  # Matching the logical-ID prefixes rather than "runs-on-*" keeps every other role in the account,
  # including the ones defined here, out of reach of the CloudFormation service role.
  stack_role_prefixes = [
    "RunsOn", "EC2Instance", "ManagedLaunchTemplate", "SchedulerInvoke", "StackConfigMaterializer",
    "NetworkFirewallEndpointResolver", "AlertTopicSlackWebhook",
  ]
  stack_iam_resources = concat(
    [for prefix in local.stack_role_prefixes : "arn:aws:iam::${local.account_id}:role/runs-on-${prefix}*"],
    [
      "arn:aws:iam::${local.account_id}:instance-profile/runs-on-EC2InstanceProfile*",
      "arn:aws:iam::${local.account_id}:role/aws-service-role/*",
    ],
  )
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

resource "aws_iam_role" "terraform" {
  for_each = local.github_subjects

  name               = "runs-on-terraform-${each.key}"
  description        = "terraform ${each.key} of terraform/runs-on from apache/airflow-ci-infra GitHub Actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust[each.key].json
}

# What terraform plan needs: refresh the stack, prove the license-key parameter exists and read
# the state. Plans run with -lock=false, so this policy grants no writes.
data "aws_iam_policy_document" "read" {
  statement {
    actions   = ["cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents", "cloudformation:GetTemplate"]
    resources = [local.stack_arn]
  }
  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:us-east-2:${local.account_id}:parameter/runs-on/license-key"]
  }
  # The aws/ssm key policy lets any principal in the account decrypt through SSM, so
  # GetParameter alone would also return the plain license key. Terraform never asks for it. The
  # deny is limited to SSM so an SSE-KMS state bucket would stay readable.
  statement {
    effect    = "Deny"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.us-east-2.amazonaws.com"]
    }
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::airflow-ci-tfstate"]
    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values   = ["tf-state/runs-on.tfstate"]
    }
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = [local.state]
  }
}

resource "aws_iam_role_policy" "read" {
  for_each = aws_iam_role.terraform

  name   = "terraform-read"
  role   = each.value.name
  policy = data.aws_iam_policy_document.read.json
}

# The apply role can only resubmit the stack from RunsOn's published templates. CloudFormation
# then acts as the stack's service role below, so this role holds no infrastructure permissions.
data "aws_iam_policy_document" "apply" {
  statement {
    actions   = ["cloudformation:UpdateStack"]
    resources = [local.stack_arn]
    condition {
      test     = "StringLike"
      variable = "cloudformation:TemplateUrl"
      values   = local.runs_on_template_urls
    }
  }
  # The provider sends the default tags on every UpdateStack.
  statement {
    actions   = ["cloudformation:TagResource", "cloudformation:UntagResource"]
    resources = [local.stack_arn]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.cloudformation.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["cloudformation.amazonaws.com"]
    }
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = [local.state]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state}.tflock"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.terraform["apply"].name
  policy = data.aws_iam_policy_document.apply.json
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

data "aws_iam_policy_document" "cloudformation_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudformation.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudformation" {
  name               = "runs-on-cloudformation"
  description        = "Service role CloudFormation uses to update the runs-on stack"
  assume_role_policy = data.aws_iam_policy_document.cloudformation_trust.json
}

# RunsOn documents only "admin rights" for deploying its stack: the template creates IAM, VPC,
# ECS, Lambda, API Gateway, SQS, DynamoDB, S3, SNS and Budgets resources, and the set changes
# between releases. AdministratorAccess follows that; the denies below keep the role away from
# everything in the account that is not the stack's own.
resource "aws_iam_role_policy_attachment" "cloudformation" {
  role       = aws_iam_role.cloudformation.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "cloudformation_guardrails" {
  statement {
    sid    = "OnlyTheStackIam"
    effect = "Deny"
    actions = [
      "iam:Add*", "iam:Attach*", "iam:Change*", "iam:Create*", "iam:Deactivate*", "iam:Delete*",
      "iam:Detach*", "iam:Enable*", "iam:PassRole", "iam:Put*", "iam:Remove*", "iam:Reset*",
      "iam:Set*", "iam:Tag*", "iam:Untag*", "iam:Update*", "iam:Upload*",
    ]
    not_resources = local.stack_iam_resources
  }
  # Stack parameters (AppCustomPolicy, RunnerCustomPolicy) can attach any managed policy to the
  # stack's own roles, which the IAM deny above exempts. The template itself attaches only these
  # two.
  statement {
    sid       = "OnlyTheTemplateManagedPolicies"
    effect    = "Deny"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["*"]
    condition {
      test     = "ArnNotEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy",
        "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
      ]
    }
  }
  statement {
    sid       = "NoRoleHopping"
    effect    = "Deny"
    actions   = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
    resources = ["*"]
  }
  statement {
    sid       = "NoTerraformState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::airflow-ci-tfstate", "arn:aws:s3:::airflow-ci-tfstate/*"]
  }
}

resource "aws_iam_role_policy" "cloudformation_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.cloudformation.name
  policy = data.aws_iam_policy_document.cloudformation_guardrails.json
}
