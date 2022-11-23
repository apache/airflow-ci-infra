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
variable "runner_version" {
  type = string
}
variable "session_manager_instance_profile_name" {
  type = string
}

source "amazon-ebs" "runner_builder" {
  #access_key = ""
  #secret_key = ""
  region = var.aws_regions[0]
  ami_name = "${var.ami_name}-${var.runner_version}-v15"
  ami_regions = var.aws_regions
  tag {
    key   = "Name"
    value = "github-runner-ami"
  }
  snapshot_tag {
    key   = "Name"
    value = "github-runner-ami-root"
  }
  encrypt_boot = false
  instance_type = "t3.micro"
  communicator = "ssh"
  ssh_username = "ubuntu"
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
       name = "ubuntu/images/*buntu-focal-20.04-amd64-server-*"
       root-device-type = "ebs"
    }
    owners = ["099720109477"]
    most_recent = true
  }
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 16
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = [
    "source.amazon-ebs.runner_builder"
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
      "mkdir -p /tmp/etc-systemd-system /tmp/usr-local-sbin /tmp/usr-local-bin /tmp/etc-sudoers.d /tmp/etc-iptables /tmp/etc-cron.d /tmp/etc-vector /tmp/etc-systemd-system-vector.service.d"
    ]
  }
  provisioner "file" {
    destination = "/tmp/etc-systemd-system/actions.runner.service"
    source      = "./files/actions.runner.service"
  }
  provisioner "file" {
    destination = "/tmp/etc-systemd-system/actions.runner-supervisor.service"
    source      = "./files/actions.runner-supervisor.service"
  }
  provisioner "file" {
    destination = "/tmp/usr-local-sbin/runner-cleanup-workdir.sh"
    source      = "./files/runner-cleanup-workdir.sh"
  }
  provisioner "file" {
    destination = "/tmp/usr-local-bin/stop-runner-if-no-job.sh"
    source      = "./files/stop-runner-if-no-job.sh"
  }
  provisioner "file" {
    destination = "/tmp/etc-sudoers.d/runner"
    source      = "./files/runner"
  }
  provisioner "file" {
    destination = "/tmp/etc-iptables/rules.v4"
    source      = "./files/rules.v4"
  }
  provisioner "file" {
    destination = "/tmp/usr-local-sbin/actions-runner-ec2-reporting.sh"
    source      = "./files/actions-runner-ec2-reporting.sh"
  }
  provisioner "file" {
    destination = "/tmp/etc-cron.d/cloudwatch-metrics-github-runners"
    source      = "./files/cloudwatch-metrics-github-runners"
  }
  provisioner "file" {
    destination = "/tmp/timber.key"
    source      = "./files/timber.key"
  }
  provisioner "file" {
    destination = "/tmp/runner-supervisor"
    source      = "./files/runner-supervisor.py"
  }
  provisioner "file" {
    destination = "/tmp/etc-vector/vector.toml"
    source      = "./files/vector.toml"
  }
  provisioner "shell" {
    scripts = [
      "./files/install-files.sh",
      "./files/source-list-additions.sh",
      "./files/install-dependencies.sh",
      "./files/install-nodejs.sh",
      "./files/install-github-cli.sh",
      "./files/install-subversion.sh",
      "./files/docker-compose.sh",
      "./files/configure_kernel.sh",
      "./files/git.sh",
      "./files/runner_bootstrap.sh",
      "./files/create-hostedtools-cache.sh",
      "./files/docker-buildx.sh",
      "./files/regctl.sh",
      "./files/cleanup.sh",
    ]
    execute_command = "chmod +x '{{ .Path }}'; sudo sh -c '{{ .Vars }} {{ .Path }}'"
    environment_vars = [
      "RUNNER_VERSION=${var.runner_version}",
    ]
  }
}
