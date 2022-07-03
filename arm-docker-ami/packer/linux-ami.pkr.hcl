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

variable "vpc_id" {
  type = string
}
variable "ami_name" {
  type = string
}
variable "aws_regions" {
  type = list(string)
}
variable "packer_role_arn" {
  type = string
}
variable "session_manager_instance_profile_name" {
  type = string
}

source "amazon-ebs" "docker-runner" {
  region = var.aws_regions[0]
  ami_name = "${var.ami_name}-v2"
  ami_regions = var.aws_regions
  tag {
    key   = "Name"
    value = "arm-docker-ami"
  }
  snapshot_tag {
    key   = "Name"
    value = "arm-docker-ami-root"
  }
  encrypt_boot = false
  instance_type = "m6g.large"
  communicator = "ssh"
  ssh_username = "ec2-user"
  ssh_interface = "session_manager"
  iam_instance_profile = var.session_manager_instance_profile_name
  subnet_filter {
    #  Just pick a random subnet in the VPC -- we only have the three defaults so this is fine!
    random = true
  }
  vpc_id = var.vpc_id
  source_ami_filter {
    filters = {
       virtualization-type = "hvm"
       architecture=  "arm64",
       name = "amzn2-ami-kernel-5.10-hvm-*"
       root-device-type = "ebs"
    }
    owners = ["amazon"]
    most_recent = true
  }
}

build {
  sources = [
    "source.amazon-ebs.docker-runner"
  ]

  provisioner "shell" {
      inline = [
        "echo Connected via SSM at '${build.User}@${build.Host}:${build.Port}'"
      ]
  }

  # Since we connect as a non-root user, we have to "stage" the files to a writable folder, which we then move
  # in to place with the approriate permissions via install-files.sh provisioner step
  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/etc-systemd-system /tmp/usr-local-sbin /tmp/usr-local-bin /tmp/etc-sudoers.d /tmp/etc-iptables /tmp/etc-cron.d"
    ]
  }
  provisioner "shell" {
    scripts = [
      "./files/install-dependencies.sh",
      "./files/docker-permissions.sh",
    ]
    execute_command = "chmod +x '{{ .Path }}'; sudo sh -c '{{ .Vars }} {{ .Path }}'"
    environment_vars = [
    ]
  }
}
