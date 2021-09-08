#!/bin/bash -e

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

set -uo pipefail

# https://github.com/actions/virtual-environments/blob/f2fdcef0e020770b1b6cc58bda3b4a01f0286f5e/images/linux/scripts/installers/github-cli.sh
url=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r '.assets[].browser_download_url|select(contains("linux") and contains("amd64") and contains(".deb"))')

cd /tmp
curl -fsL --remote-name "$url"
apt install /tmp/gh_*_linux_amd64.deb
rm /tmp/gh_*_linux_amd64.deb
