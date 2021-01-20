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
}