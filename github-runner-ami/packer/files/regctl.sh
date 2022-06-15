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
    # Well. Docker compose got it right, but regctl didn't ¯\_(ツ)_/¯
    architecture="amd64"
fi
# Hard-code regctl version
regctl_version="v0.4.3"
regctl_binary="regctl-$(uname -s)-${architecture}"
curl -L "https://github.com/regclient/regclient/releases/download/${regctl_version}/${regctl_binary}" -o "/usr/local/bin/regctl"
chmod a+x "/usr/local/bin/regctl"
