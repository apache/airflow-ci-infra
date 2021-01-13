module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = ""
  cidr = var.vpc_cidr
  azs             = var.vpc_azs
  public_subnets  = module.subnet_addrs.networks[*].cidr_block
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
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
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

resource "aws_launch_template" "runners" {
  name_prefix   = "ci-runner"
  image_id      = data.aws_ami.runner.id
  instance_type = "t2.micro"
  vpc_security_group_ids = ["sg-12345678"]
  user_data = filebase64("${path.module}/example.sh")
  
  network_interfaces {
    associate_public_ip_address = true
  }

  iam_instance_profile {
    name = "test"
  }

  monitoring {
    enabled = true
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





