data "aws_iam_policy_document" "autoscaler_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "autoscaler_policy" {
  name        = "eks-autoscaler-policy"
  description = "EKS Autoscaler Policy"
  policy      = data.aws_iam_policy_document.autoscaler_policy_document.json
}

data "aws_iam_policy_document" "autoscaler_role_assume_policy_document" {
  statement {
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        module.eks.oidc_provider_arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values = [
        "system:serviceaccount:infra:cluster-autoscaler"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values = [
        "sts.amazonaws.com"
      ]
    }

  }
}

resource "aws_iam_role" "autoscaler_role" {
  name               = "eks-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.autoscaler_role_assume_policy_document.json
}

resource "aws_iam_role_policy_attachment" "autoscaler_policy_attachment" {
  role       = aws_iam_role.autoscaler_role.name
  policy_arn = aws_iam_policy.autoscaler_policy.arn
}