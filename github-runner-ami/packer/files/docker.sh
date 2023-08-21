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

for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg --assume-yes; done

sudo apt-get update
sudo apt-get install ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

# Same version as MIN_VERSIONS in Breeze
DOCKER_VERSION_STRING="5:23.0.0-1~ubuntu.20.04~focal"
DOCKER_COMPOSE_VERSION_STRING="2.14.1~ubuntu-focal"
DOCKER_BUILDX_VERSION_STRING="0.11.2-1~ubuntu.20.04~focal"
sudo apt-get install \
  "docker-ce=${DOCKER_VERSION_STRING}" \
  "docker-ce-cli=${DOCKER_VERSION_STRING}" \
  containerd.io \
  "docker-buildx-plugin=${DOCKER_BUILDX_VERSION_STRING}" \
  "docker-compose-plugin=${DOCKER_COMPOSE_VERSION_STRING}" --asume-yes --allow-downgrades
