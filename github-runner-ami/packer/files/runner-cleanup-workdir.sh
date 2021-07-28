#!/bin/bash
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

set -eu -o pipefail
echo "Left-over containers:"
docker ps -a
docker ps -qa | xargs --verbose --no-run-if-empty docker rm -fv

echo "Log in to a paid docker user to get unlimited docker pulls"
aws ssm get-parameter --with-decryption --name /runners/apache/airflow/dockerPassword | \
    jq .Parameter.Value -r | \
    sudo -u runner docker login --username airflowcirunners --password-stdin

if [[ -d ~runner/actions-runner/_work/airflow/airflow ]]; then
    cd ~runner/actions-runner/_work/airflow/airflow

    chown --changes -R runner: .
    if [[ -e .git ]]; then
        sudo -u runner bash -c "
        git reset --hard && \
        git submodule deinit --all -f && \
        git submodule foreach git clean -fxd && \
        git clean -fxd \
        "
    fi
fi

# Remove left over mssql data dirs
find . -maxdepth 1 -name 'tmp-mssql-volume-*' -type d -printf 'Deleting %f\n' -exec sudo rm -r {} +
