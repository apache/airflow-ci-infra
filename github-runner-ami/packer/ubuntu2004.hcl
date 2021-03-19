source "amazon-ebs" "runner_builder" {
  type = "amazon-ebs"
  assume_role {
    role_arn     = "arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME"
    session_name = "SESSION_NAME"
    external_id  = "EXTERNAL_ID"
  }
  region = "us-east-1"
  ami_name = "airflow-ci-runner"
  ami_regions = "us-west"
  tags {
    tag = "example"
  }
  encrypt_boot = true
  kms_key_id = "key id"
  instance_type = "t2.micro"
  communicator = "ssh"
  ssh_username = "ubuntu"
  ssh_interface = "session_manager"
  iam_instance_profile = "{{user `iam_instance_profile`}}"
  subnet_filter {
    filters = {
          "tag:Class": "build"
    }
    most_free = true
    random = false
  }
  source_ami_filter {
    filters = {
       image-id = "ami-0885b1f6bd170450c"
    }
    owners = ["self"]
    most_recent = true
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
  provisioner "file" {
    destination = "/etc/systemd/system/actions.runner.service"
    source      = "./files/actions.runner.service"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/runner-cleanup-workdir.sh"
    source      = "./files/runner-cleanup-workdir.sh"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/stop-runner-if-no-job.sh"
    source      = "./files/stop-runner-if-no-job.sh"
  }
  provisioner "file" {
    destination = "/etc/sudoers.d/runner"
    source      = "./files/runner"
  }
  provisioner "file" {
    destination = "/etc/iptables/rules.v4"
    source      = "./files/rules.v4"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/actions-runner-ec2-reporting"
    source      = "./files/actions-runner-ec2-reporting"
  }
  provisioner "file" {
    destination = "/etc/cron.d/cloudwatch-metrics-github-runners"
    source      = "./files/cloudwatch-metrics-github-runners"
  }
  provisioner "file" {
    destination = "/etc/systemd/system/actions.runner-supervisor.service"
    source      = "./files/actions.runner-supervisor.service"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/set-file-permissions.sh"
    source      = "./files/set-file-permissions.sh"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/timber.key"
    source      = "./files/timber.key"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/source-list-additions.sh"
    source      = "./files/source-list-additions.sh"
  }
  provisioner "file" {
    destination = "/usr/local/sbin/install-dependencies.sh"
    source      = "./files/install-dependencies.sh"
  }
}