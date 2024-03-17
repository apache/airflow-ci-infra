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

cp /tmp/yarn.key /etc/apt/keyrings/yarn.gpg
sudo chmod a+r /etc/apt/keyrings/yarn.gpg

cp /tmp/timber.key /etc/apt/keyrings/timber.gpg
sudo chmod a+r /etc/apt/keyrings/timber.gpg

echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list
echo "deb [signed-by=/etc/apt/keyrings/timber.gpg] https://repositories.timber.io/public/vector/deb/ubuntu jammy main" > /etc/apt/sources.list.d/timber.list
