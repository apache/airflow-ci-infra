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
buildx_version="v0.7.1"
buildx_binary="buildx-${buildx_version}.$(uname -s)-${architecture}"
plugins_dir="/home/runner/.docker/cli-plugins"
sudo -u runner mkdir -pv "${plugins_dir}"
sudo -u runner curl -L "https://github.com/docker/buildx/releases/download/${buildx_version}/${buildx_binary}" -o "${plugins_dir}/docker-buildx"
sudo -u runner chmod a+x "${plugins_dir}/docker-buildx"

# make sure multi-platform support is added for self-hosted runners
# See; https://docs.docker.com/buildx/working-with-buildx/#build-multi-platform-images
sudo docker run --privileged --rm tonistiigi/binfmt --install all
