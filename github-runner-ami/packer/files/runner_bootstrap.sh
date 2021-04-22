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

# Validate params
: "${RUNNER_VERSION?}"

# Set an env var (that is visible in runners) that will let us know we are on a self-hosted runner
echo 'AIRFLOW_SELF_HOSTED_RUNNER="[\"self-hosted\"]"' >> /etc/environment

useradd  --create-home runner -G docker

install --owner runner --directory ~runner/actions-runner

cd ~runner/actions-runner
curl -L "https://github.com/ashb/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | tar -zx

python3 -mvenv /opt/runner-supervisor
/opt/runner-supervisor/bin/pip install -U pip python-dynamodb-lock-whatnick==0.9.3 click==7.1.2 psutil 'tenacity~=6.0'

install --owner root --mode 0755 /tmp/runner-supervisor /opt/runner-supervisor/bin/runner-supervisor

systemctl enable iptables.service
systemctl enable vector.service

# We don't enable actions.runner.service here, but instead in the user-data
# script, as otherwise it would happen to early, before we have had a chance to
# drop the AWS_DEFAULT_REGION in to /etc/environment
