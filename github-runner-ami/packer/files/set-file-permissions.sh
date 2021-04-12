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

chmod 0755 /usr/local/sbin/runner-cleanup-workdir.sh root:root
chmod 0755 /usr/local/bin/stop-runner-if-no-job.sh root:root
chmod 0440 /etc/sudoers.d/runner root:root
chmod 0775 /usr/local/sbin/actions-runner-ec2-reporting
