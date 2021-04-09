terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = "github-runners-vpc"
  cidr = var.vpc_cidr
  azs             = var.vpc_azs
  public_subnets  = module.subnet_addrs.networks[*].cidr_block
  enable_dynamodb_endpoint = true
  tags = var.tags
}

module "subnet_addrs" {
  source = "hashicorp/subnets/cidr"
  base_cidr_block = var.vpc_cidr
  networks = [
    {
      name     = "one"
      new_bits = 4
    },
    {
      name     = "two"
      new_bits = 4
    },
    {
      name     = "three"
      new_bits = 4
    }
  ]
}

resource "aws_autoscaling_group" "runners" {
  name                      = "ci-runners-asg"
  max_size                  = 15
  min_size                  = 0
  desired_capacity          = 20
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  placement_group           = aws_placement_group.test.id
  launch_configuration      = aws_launch_configuration.foobar.name
  vpc_zone_identifier       = module.vpc.public_subnets
  tags = var.tags 
  launch_template {
    id      = aws_launch_template.runners.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "scale_runner_policy" {
  name                   = "aws_autoscaling_policy"
  autoscaling_group_name = aws_autoscaling_group.runners.name
  policy_type = "StepScaling"
  adjustment_type = "ChangeInCapacity"

  step_adjustment {
    scaling_adjustment          = -1
    metric_interval_lower_bound = 1
    metric_interval_upper_bound = 2
  }
  step_adjustment {
    scaling_adjustment          = -2
    metric_interval_lower_bound = 3
    metric_interval_upper_bound = 4
  }
  step_adjustment {
    scaling_adjustment          = -3
    metric_interval_lower_bound = 5
    metric_interval_upper_bound = 9
  }
  step_adjustment {
    scaling_adjustment          = -7
    metric_interval_lower_bound = 10
    metric_interval_upper_bound = 19
  }
  step_adjustment {
    scaling_adjustment          = -15
    metric_interval_lower_bound = 20
    metric_interval_upper_bound = 29
  }
  step_adjustment {
    scaling_adjustment          = -24
    metric_interval_lower_bound = 30
  }
}

resource "aws_cloudwatch_metric_alarm" "scale-gh-runners-asg" {
  alarm_name          = "scale-gh-runners-asg"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  period              = "60"
  threshold           = "0"
  datapoints_to_alarm = "3"

  metric_query {
    id          = "e1"
    expression  = "m2-m1"
    label       = "Idle instances"
    return_data = "true"
  }

  metric_query {
    id = "m2"

    metric {
      metric_name = "GroupInServiceInstances"
      namespace   = "AWS/AutoScaling"
      period      = "60"
      stat        = "Sum"
        
      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.runners.name
      }
    }
  }

  metric_query {
    id = "m1"

    metric {
      metric_name = "jobs-running"
      namespace   = "github.actions"
      stat        = "Sum"
      period      = "60"
    }
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_runner_policy.arn]
}

resource "aws_launch_template" "runners" {
  name_prefix   = "ci-runner"
  image_id      = data.aws_ami.runner.id
  instance_type = "r5a.2xlarge"
  vpc_security_group_ids = [aws_security_group.github_runners.id]
  user_data = filebase64("${path.module}/user_data.sh")

  network_interfaces {
    associate_public_ip_address = true
    security_groups = []
  }

  iam_instance_profile {
    name = "test"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "test"
    }
  }
}

data "aws_ami" "runner" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_dynamodb_table" "github-runner-locks" {
  name           = "GithubRunnerLocks"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "lock_key"
  range_key      = "sort_key"
  tags = var.tags
}

resource "aws_dynamodb_table" "github-runner-queue" {
  name           = "GithubRunnerQueue"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"
  tags = var.tags
}

resource "aws_security_group" "github_runners" {
  name = "Github Runner"
  vpc_id = module.vpc.vpc_id	
  description = "Security group to enable github runners "
  tags = var.tags
}

resource "aws_iam_role" "runner_role" {
  name = "runner-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    tag-key = "tag-value"
  }
}

resource "aws_iam_role_policy" "runner_policy" {
  name = "runners-policy"
  role = aws_iam_role.runner_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "cloudwatch:PutMetricData",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "cloudwatch:namespace": "github.actions"
                }
            }
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "ssm:DescribeParameters",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor2",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "s3:GetObject",
                "dynamodb:PutItem",
                "autoscaling:CompleteLifecycleAction",
                "dynamodb:DeleteItem",
                "autoscaling:SetInstanceProtection",
                "sqs:ReceiveMessage",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "autoscaling:RecordLifecycleActionHeartbeat"
            ],
            "Resource": [
                "${aws_dynamodb_table.github-runner-locks.arn}",
                "arn:aws:sqs:*:827901512104:actions-runner-requests",
                "${aws_autoscaling_group.runners.arn}",
                "arn:aws:s3:::airflow-ci-assets//*",
                "arn:aws:s3:::airflow-ci-assets"
            ]
        },
        {
            "Sid": "VisualEditor3",
            "Effect": "Allow",
            "Action": [
                "ssm:GetParametersByPath",
                "dynamodb:UpdateItem",
                "ssm:GetParameters",
                "ssm:GetParameter"
            ],
            "Resource": [
                "arn:aws:ssm:*:827901512104:parameter/runners//*",
                "${aws_dynamodb_table.github-runner-queue.arn}"
            ]
        }
    ]
  }
  EOF
}

resource "aws_iam_role_policy" "github_cloud_watch_logs" {
  name = "gh-cloudwatch-logs-policy"
  role = aws_iam_role.runner_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "ssm:GetParameter"
            ],
            "Resource": [
                "arn:aws:logs:*:827901512104:log-group:GitHubRunners:log-stream:*",
                "arn:aws:logs:*:827901512104:log-group:*",
                "arn:aws:ssm:*:*:parameter/runners/apache/airflow/AmazonCloudWatch-*"
            ]
        }
    ]
  }
  EOF
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "github_cloud_watch_logs" {
  name = "GithubCloudWatchLogs"
  role = aws_iam_role.runner_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "kms:Decrypt",
                "autoscaling:SetDesiredCapacity",
                "ssm:GetParameter",
                "logs:CreateLogGroup",
                "logs:PutLogEvents",
                "dynamodb:UpdateItem"
            ],
            "Resource": [
                "arn:aws:ssm:*:827901512104:parameter/runners/*/configOverlay",
                "${aws_autoscaling_group.runners.arn}",
                "arn:aws:kms:*:827901512104:key/48a58710-7ac6-4f88-995f-758a6a450faa",
                "${aws_dynamodb_table.github-runner-queue.arn}",
                "arn:*:logs:*:*:*"
            ]
      },
      {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups"
            ],
            "Resource": "*"
      }
    ]
  }
  EOF
}


resource "aws_lambda_function" "lambda_scale_out_runners" {
  filename      = "lambda_function_payload.zip"
  function_name = "lambda_scale_out_runners"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "exports.test"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  runtime = "python3.7"

  environment {
    variables = {
      foo = "bar"
    }
  }
}