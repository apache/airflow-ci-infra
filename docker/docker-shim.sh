#!/usr/bin/env bash

#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

set -Eeuo pipefail

DOCKER=/usr/bin/docker
if [ ! -e $DOCKER ]; then
  DOCKER=/home/runner/bin/docker
fi

if [[ ${ARC_DOCKER_MTU_PROPAGATION:-false} == true ]] &&
  (($# >= 2)) && [[ $1 == network && $2 == create ]] &&
  mtu=$($DOCKER network inspect bridge --format '{{index .Options "com.docker.network.driver.mtu"}}' 2>/dev/null); then
  shift 2
  set -- network create --opt com.docker.network.driver.mtu="$mtu" "$@"
fi

exec $DOCKER "$@"
