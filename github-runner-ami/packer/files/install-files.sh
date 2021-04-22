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

set -eu -o pipefail

mkdir /etc/iptables/ /etc/vector

install --owner root --mode=0644 --target-directory "/etc/systemd/system/" "/tmp/etc-systemd-system/"*
install --owner root --mode=0755 --target-directory "/usr/local/sbin" "/tmp/usr-local-sbin/"*
install --owner root --mode=0755 --target-directory "/usr/local/bin" "/tmp/usr-local-bin/"*
install --owner root --mode=0644 --target-directory "/etc/iptables" "/tmp/etc-iptables/"*
install --owner root --mode=0644 --target-directory "/etc/cron.d" "/tmp/etc-cron.d/"*
install --owner root --mode=0644 --target-directory "/etc/sudoers.d" "/tmp/etc-sudoers.d/"*
install --owner root --mode=0644 --target-directory "/etc/vector/" "/tmp/etc-vector/"*
