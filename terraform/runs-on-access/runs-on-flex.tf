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

# Roles of the Terraform (RunsOn Flex) workflow, which applies terraform/runs-on-flex: RunsOn's
# Terraform module instead of its CloudFormation template. No CloudFormation service role sits in
# between, so the apply role itself creates the infrastructure. It gets what the CloudFormation
# service role in main.tf has (AdministratorAccess with denies) and three limits more: it acts
# only in us-east-2 (IAM and Budgets are global), it reaches no S3 bucket but the stack's cache
# buckets and its own state, and every role it creates carries the runs-on-flex-boundary
# permissions boundary, so no role of the stack can be given more than the boundary allows.
locals {
  flex_stack = "runs-on-flex"
  flex_state = "arn:aws:s3:::airflow-ci-tfstate/tf-state/runs-on-flex.tfstate"

  # Every IAM role and instance profile of the module (v3.5.1) is named <stack>-<purpose>. AWS
  # creates the service-linked roles on first use of ECS and Spot.
  flex_iam_resources = [
    "arn:aws:iam::${local.account_id}:role/${local.flex_stack}-*",
    "arn:aws:iam::${local.account_id}:instance-profile/${local.flex_stack}-*",
    "arn:aws:iam::${local.account_id}:role/aws-service-role/*",
  ]
  # The only AWS-managed policies the module attaches (runner SSM access, ECS task execution).
  flex_managed_policies = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy",
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
  ]
  iam_write_actions = [
    "iam:Add*", "iam:Attach*", "iam:Change*", "iam:Create*", "iam:Deactivate*", "iam:Delete*",
    "iam:Detach*", "iam:Enable*", "iam:PassRole", "iam:Put*", "iam:Remove*", "iam:Reset*",
    "iam:Set*", "iam:Tag*", "iam:Untag*", "iam:Update*", "iam:Upload*",
  ]
  tfstate_bucket = ["arn:aws:s3:::airflow-ci-tfstate", "arn:aws:s3:::airflow-ci-tfstate/*"]
}

# Named outside the stack's runs-on-flex-* prefix: the apply role may write IAM only under that
# prefix, and must not be able to remove its own guardrails.
resource "aws_iam_role" "flex_terraform" {
  for_each = local.github_subjects

  name               = "runs-on-terraform-flex-${each.key}"
  description        = "terraform ${each.key} of terraform/runs-on-flex from apache/airflow-ci-infra GitHub Actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust[each.key].json
}

# Refreshing the module's ~150 resources reads across a dozen services, so plans get
# ReadOnlyAccess. Plans also run on pull requests, so the denies keep secrets out of reach:
# ReadOnlyAccess can read every S3 object (the other Terraform states included) and SSM
# parameters, which the aws/ssm key would decrypt.
resource "aws_iam_role_policy_attachment" "flex_plan_read_only" {
  role       = aws_iam_role.flex_terraform["plan"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "flex_plan_guardrails" {
  statement {
    sid           = "OnlyThisStateObject"
    effect        = "Deny"
    actions       = ["s3:GetObject*"]
    not_resources = [local.flex_state]
  }
  statement {
    sid       = "NoSsmDecrypt"
    effect    = "Deny"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["ssm.*.amazonaws.com"]
    }
  }
  statement {
    sid       = "NoSecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:BatchGetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flex_plan_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.flex_terraform["plan"].name
  policy = data.aws_iam_policy_document.flex_plan_guardrails.json
}

# RunsOn documents only "admin rights" for deploying the stack, and the module's resource set
# changes between releases, so AdministratorAccess as for the CloudFormation service role.
resource "aws_iam_role_policy_attachment" "flex_apply" {
  role       = aws_iam_role.flex_terraform["apply"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "flex_apply_guardrails" {
  statement {
    sid           = "OnlyTheStackIam"
    effect        = "Deny"
    actions       = local.iam_write_actions
    not_resources = local.flex_iam_resources
  }
  # A stack role without the boundary could be given any permission and then be passed to a Lambda
  # function or an ECS task, which would lift every deny of this policy.
  statement {
    sid       = "StackRolesKeepTheBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.flex_stack}-*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.flex_boundary.arn]
    }
  }
  statement {
    sid       = "NoBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
  statement {
    sid       = "OnlyTheModuleManagedPolicies"
    effect    = "Deny"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["*"]
    condition {
      test     = "ArnNotEquals"
      variable = "iam:PolicyARN"
      values   = local.flex_managed_policies
    }
  }
  statement {
    sid       = "NoRoleHopping"
    effect    = "Deny"
    actions   = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
    resources = ["*"]
  }
  # Only the stack's cache bucket (bucket_prefix "<stack>-cache-") and this state and its lock file.
  statement {
    sid     = "OnlyTheStackBuckets"
    effect  = "Deny"
    actions = ["s3:*"]
    not_resources = [
      "arn:aws:s3:::${local.flex_stack}-cache-*",
      local.flex_state,
      "${local.flex_state}.tflock",
      "arn:aws:s3:::airflow-ci-tfstate",
    ]
  }
  statement {
    sid       = "NoStateBucketChanges"
    effect    = "Deny"
    actions   = ["s3:Put*", "s3:Delete*"]
    resources = ["arn:aws:s3:::airflow-ci-tfstate"]
  }
  statement {
    sid         = "OnlyTheRunnersRegion"
    effect      = "Deny"
    not_actions = ["iam:*", "budgets:*", "sts:*"]
    resources   = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-2"]
    }
  }
}

resource "aws_iam_role_policy" "flex_apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.flex_terraform["apply"].name
  policy = data.aws_iam_policy_document.flex_apply_guardrails.json
}

# The most any role of the stack may do, whatever its own policies say. The control plane passes
# the runner role to the instances it launches and creates the Spot service-linked role; nothing
# of the stack writes other IAM, assumes roles outside the stack or touches the Terraform states.
data "aws_iam_policy_document" "flex_boundary" {
  statement {
    sid       = "Everything"
    actions   = ["*"]
    resources = ["*"]
  }
  statement {
    sid    = "NoIamWrites"
    effect = "Deny"
    # PassRole and CreateServiceLinkedRole are limited below.
    actions = [
      "iam:Add*", "iam:Attach*", "iam:Change*", "iam:CreateA*", "iam:CreateG*", "iam:CreateI*",
      "iam:CreateL*", "iam:CreateO*", "iam:CreateP*", "iam:CreateR*", "iam:CreateSA*",
      "iam:CreateServiceS*", "iam:CreateU*", "iam:CreateV*", "iam:Deactivate*", "iam:Delete*",
      "iam:Detach*", "iam:Enable*", "iam:Put*", "iam:Remove*", "iam:Reset*", "iam:Set*", "iam:Tag*",
      "iam:Untag*", "iam:Update*", "iam:Upload*",
    ]
    resources = ["*"]
  }
  statement {
    sid           = "PassOnlyStackRoles"
    effect        = "Deny"
    actions       = ["iam:PassRole"]
    not_resources = ["arn:aws:iam::${local.account_id}:role/${local.flex_stack}-*"]
  }
  statement {
    sid           = "OnlyServiceLinkedRoles"
    effect        = "Deny"
    actions       = ["iam:CreateServiceLinkedRole"]
    not_resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]
  }
  statement {
    sid           = "AssumeOnlyStackRoles"
    effect        = "Deny"
    actions       = ["sts:AssumeRole"]
    not_resources = ["arn:aws:iam::${local.account_id}:role/${local.flex_stack}-*"]
  }
  statement {
    sid       = "NoTerraformState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = local.tfstate_bucket
  }
}

resource "aws_iam_policy" "flex_boundary" {
  name        = "${local.flex_stack}-boundary"
  description = "Permissions boundary of every IAM role the runs-on-flex stack creates"
  policy      = data.aws_iam_policy_document.flex_boundary.json
}
