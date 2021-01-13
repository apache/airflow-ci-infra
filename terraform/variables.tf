variable vpc_cidr {
    type = string
    description = "The cidr of the vpc holding ASG of github action self hosted runners."
}

variable vpc_azs {
    type = list(string)
    description = "List of vpc azs that subnets should be created."
}

variable tags {
    type = map(string)
    description = "Tags of the resources"
}

variable ami_owner {
    type = string
    description = "The owner of the ami in AWS."
}

variable ami_name {
    type = string
    description = "The ami name."
}

variable runner_instance_type {
    type = string
    description = "The instance type of the github actions runners."
}

variable asg_max_size {
    type = number 
    description = "Max size the ASG can scale runners."
}

variable asg_min_size {
    type = number
    description = "Min size the ASG can scale runners."
}