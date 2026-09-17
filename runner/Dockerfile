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
#
FROM ghcr.io/actions/actions-runner:latest

USER root

# Host-level tools the airflow CI workflows expect on a runner — the target
# contract is GitHub's hosted ubuntu-24.04 image, restricted to what the CI
# graph actually invokes (pip, uv-via-pip, aws, parallel, docker CLI). Jobs
# also run `sudo apt-get install ...` themselves (as on GitHub-hosted
# runners), so the runner user gets passwordless sudo instead of us baking in
# every package.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    sudo ca-certificates curl wget zip unzip zstd git jq parallel build-essential netcat-openbsd \
    libssl-dev libffi-dev python3 python3-venv python3-dev python3-pip python-is-python3 \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && echo "runner ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

# The actions-runner base ships a malformed tz config (/etc/timezone = "/UTC",
# localtime -> zoneinfo//UTC) which breaks local-timezone detection with
# 'ZoneInfo keys may not be absolute paths' (seen in shared timezones tests).
# Normalize to what GitHub-hosted runners have.
RUN ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime && echo "Etc/UTC" > /etc/timezone

# Same mechanism GitHub's runner image uses to make system `pip install` work
# on Ubuntu 24.04 despite PEP 668 (actions/runner-images install-python.sh):
# a global pip.conf, not deleting the EXTERNALLY-MANAGED marker. Non-root pip
# installs fall through to ~/.local, hence the PATH addition.
RUN printf '[global]\nbreak-system-packages = true\n' > /etc/pip.conf

# JDKs for the java-sdk prek hooks (sync-java-sdk-supervisor-schema, ktlint,
# spotless run gradle on the host; toolchains reference Java 11 and 17).
# GitHub-hosted runners ship the Temurin set — mirror the versions we use.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-11-jdk-headless openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s "/usr/lib/jvm/java-17-openjdk-$(dpkg --print-architecture)" /usr/lib/jvm/java-17
ENV JAVA_HOME=/usr/lib/jvm/java-17

# gh CLI (job-summary and finalize steps use `gh api`/`gh run view`; present
# on GitHub-hosted runners). Official apt repo per cli.github.com docs.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# kubectl (hosted runners ship it; the k8s workflows' cluster-state dump steps
# call it directly on the host). Pinned to the cluster's minor via pkgs.k8s.io.
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key -o /tmp/k8s.key \
    && gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/k8s.key \
    && chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends kubectl \
    && rm -rf /var/lib/apt/lists/* /tmp/k8s.key

# Real python3.10 on PATH (uv-managed build; hosted runners ship toolcache
# pythons, so this matches the contract). Provider-compat jobs check out old
# airflow branches whose prek configs pin python3.10 hooks; without a local
# interpreter prek downloads its own managed CPython, and that download is
# broken on arm64 (sysconfigdata missing build_time_vars, first ARM run
# 2026-07-31). A PATH python short-circuits the download on both arches.
RUN pip install uv \
    && UV_PYTHON_INSTALL_DIR=/opt/uv-python uv python install 3.10 \
    && ln -s /opt/uv-python/cpython-3.10.*/bin/python3.10 /usr/local/bin/python3.10 \
    && /usr/local/bin/python3.10 -c "import sysconfig; sysconfig.get_path('stdlib')" \
    && pip uninstall -y uv

# AWS CLI v2 (stash actions use `aws s3`); official installer, arch-aware.
RUN ARCH=$(uname -m) \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

ENV PATH="/home/runner/.local/bin:${PATH}"

# Hosted runners export USER; workflows rely on it (e.g. `sudo chown -R
# "${USER}"` — with USER unset that chown is a silent no-op, exit 0, leaving
# root-owned dirs that later non-sudo steps can't write).
ENV USER=runner

# breeze saves/loads CI image tars via `--image-file-dir /mnt` — on GitHub-hosted
# runners /mnt is the big scratch disk made writable by make_mnt_writeable.sh,
# which self-hosted runs deliberately skip. Backed here by the node's 200 GB
# root volume; sticky like /tmp.
RUN mkdir -p /mnt && chmod 1777 /mnt

USER runner
