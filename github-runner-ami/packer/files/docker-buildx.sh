#!/usr/bin/env bash
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
set -exu -o pipefail

architecture=$(uname -m)
if [[ ${architecture} == "x86_64" ]] ; then
    # Well. Docker compose got it right, but docker buildx didn't ¯\_(ツ)_/¯
    architecture="amd64"
fi
# Hard-code docker buildx version
buildx_version="v0.8.2"
buildx_binary="buildx-${buildx_version}.$(uname -s)-${architecture}"
plugins_dir="/home/runner/.docker/cli-plugins"
sudo -u runner mkdir -pv "${plugins_dir}"
sudo -u runner curl -L "https://github.com/docker/buildx/releases/download/${buildx_version}/${buildx_binary}" -o "${plugins_dir}/docker-buildx"
sudo -u runner chmod a+x "${plugins_dir}/docker-buildx"


## Support for multi-platform builds
## See; https://docs.docker.com/buildx/working-with-buildx/#build-multi-platform-images
## We do not need installing qemu support for public runners as we are currently starting ARM instances to
## build the images for ARM
# apt install -y qemu qemu-user-static
# sudo docker run --privileged --rm tonistiigi/binfmt --install all


## Alternatively support builds with ARM instance launched on demand
# Needed Launch arm instances and make the docker engine available via forwarded SSH connection
apt-get install -y autossh
# The runner role has to have the following policies enabled:
# RunInstancesPolicy:
#{
#    "Version": "2012-10-17",
#     "Statement": [
#        {
#            "Sid": "VisualEditor0",
#            "Effect": "Allow",
#            "Action": [
#                "ec2:AuthorizeSecurityGroupIngress",
#                "ec2:TerminateInstances",
#                "ec2:CreateTags",
#                "ec2:RunInstances",
#                "ec2:RevokeSecurityGroupIngress"
#            ],
#            "Resource": [
#                "arn:aws:ec2:us-east-2:827901512104:subnet/*",
#                "arn:aws:ec2:us-east-2:827901512104:instance/*",
#                "arn:aws:ec2:us-east-2:827901512104:security-group/*",
#                "arn:aws:ec2:us-east-2:827901512104:network-interface/*",
#                "arn:aws:ec2:us-east-2:827901512104:volume/*",
#                "arn:aws:ec2:us-east-2::image/*"
#            ]
#        },
#        {
#            "Sid": "VisualEditor1",
#            "Effect": "Allow",
#            "Action": [
#                "ec2:DescribeInstances",
#                "ec2:DescribeInstanceStatus"
#            ],
#            "Resource": "*"
#        }
#    ]
#}
#
# InstanceConnectPolicy:
# {
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2-instance-connect:SendSSHPublicKey"
#            ],
#            "Resource": [
#                "arn:aws:ec2:us-east-2:827901512104:instance/*"
#            ],
#            "Condition": {
#                "StringEquals": {
#                    "ec2:osuser": "ec2-user"
#                }
#            }
#        }
#    ]
# }
