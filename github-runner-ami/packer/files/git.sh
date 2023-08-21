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

GIT_REPO="ppa:git-core/ppa"
GIT_LFS_REPO="https://packagecloud.io/install/repositories/github/git-lfs"

function download_with_retries() {
# Due to restrictions of bash functions, positional arguments are used here.
# In case if you using latest argument NAME, you should also set value to all previous parameters.
# Example: download_with_retries $ANDROID_SDK_URL "." "android_sdk.zip"
    local URL="$1"
    local DEST="${2:-.}"
    local NAME="${3:-${URL##*/}}"
    local COMPRESSED="$4"

    if [[ $COMPRESSED == "compressed" ]]; then
        local COMMAND="curl $URL -4 -sL --compressed -o '$DEST/$NAME' -w '%{http_code}'"
    else
        local COMMAND="curl $URL -4 -sL -o '$DEST/$NAME' -w '%{http_code}'"
    fi

    echo "Downloading '$URL' to '${DEST}/${NAME}'..."
    retries=20
    interval=30
    while [ $retries -gt 0 ]; do
        ((retries--))
        # Temporary disable exit on error to retry on non-zero exit code
        set +e
        http_code=$(eval $COMMAND)
        exit_code=$?
        if [ $http_code -eq 200 ] && [ $exit_code -eq 0 ]; then
            echo "Download completed"
            return 0
        else
            echo "Error — Either HTTP response code for '$URL' is wrong - '$http_code' or exit code is not 0 - '$exit_code'. Waiting $interval seconds before the next attempt, $retries attempts left"
            sleep $interval
        fi
        # Enable exit on error back
        set -e
    done

    echo "Could not download $URL"
    return 1
}

## Install git
add-apt-repository $GIT_REPO -y
apt-get update
apt-get install --upgrade git -y
git --version

# Install git-lfs
curl -s $GIT_LFS_REPO/script.deb.sh | bash
apt-get install -y git-lfs=2.13.3

# Install git-ftp
apt-get install git-ftp -y

# Remove source repo's
add-apt-repository --remove $GIT_REPO
rm /etc/apt/sources.list.d/github_git-lfs.list

#Install hub
tmp_hub="/tmp/hub"
mkdir -p "$tmp_hub"
url=$(curl --location -s https://api.github.com/repos/github/hub/releases/latest | jq -r '.assets[].browser_download_url | select(contains("hub-linux-amd64"))')
download_with_retries "$url" "$tmp_hub"
tar xzf "$tmp_hub"/hub-linux-amd64-*.tgz --strip-components 1 -C "$tmp_hub"
mv "$tmp_hub"/bin/hub /usr/local/bin

# Add well-known SSH host keys to known_hosts
ssh-keyscan -t rsa github.com >> /etc/ssh/ssh_known_hosts
ssh-keyscan -t rsa ssh.dev.azure.com >> /etc/ssh/ssh_known_hosts
