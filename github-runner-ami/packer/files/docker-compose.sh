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

# https://github.com/actions/virtual-environments/blob/525f79f479cca77aef4e0a680548b65534c64a18/images/linux/scripts/installers/docker-compose.sh

# disabled installing latest released version until https://github.com/docker/compose/issues/8742
# is solved (docker v2 breaks network management required to get kerberos integration working
# Switching temporary to latest released docker v2

#URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.assets[].browser_download_url | select(endswith("docker-compose-linux-x86_64"))')
#curl --fail -L "$URL" -o /usr/local/bin/docker-compose
#chmod +x /usr/local/bin/docker-compose

# Hard-code docker-compose 1.29.2
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
