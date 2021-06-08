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

set -u

MAINPID="${MAINPID:-${1:-}}"

if [[ -z "$MAINPID" ]]; then
    echo "No MAINPID, assuming it already crashed!"
    exit 0
fi

if pgrep --ns $MAINPID -a Runner.Worker > /dev/null; then
  echo "Waiting for current job to finish"
  while pgrep --ns $MAINPID -a Runner.Worker; do
    # Job running -- just wait for it to exit
    sleep 10
  done

else
  # If there were _no_ Workers running, ask the main process to stop. If there
  # were Workers running, then Runner.Listener would stop automatically because
  # of the `--once`
  pkill --ns $MAINPID Runner.Listener || true
fi

  # Wait for it to shut down
echo "Waiting for main Runner.Listener $MAINPID process to stop"
while pgrep --ns $MAINPID -a Runner.Listener; do
  sleep 5
done
