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


debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_done boolean true
iptables-persistent iptables-persistent/autosave_v4 boolean false
iptables-persistent iptables-persistent/autosave_v6 boolean false
EOF

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -yq --no-install-recommends -o Dpkg::Options::="--force-confold" \
            awscli \
            build-essential \
            docker.io \
            git \
            haveged \
            iptables-persistent \
            jq \
            parallel \
            python3-dev \
            python3-venv \
            python3-wheel \
            yarn \
            vector='0.15.*'


# Re-enabled in clout-init once AWS_DEFAULT_REGION env var is set
systemctl disable vector

# validate the vector config file we have already installed
sudo -u vector vector validate --no-environment
