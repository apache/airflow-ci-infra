#!/usr/bin/env python3
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
"""Keep every Terraform lock file usable on the CI runners and on maintainers' Macs.

``terraform init`` records the package checksum (``h1:``) of the platform it runs on only, so a
lock file made on a Mac fails the workflows' ``terraform init -lockfile=readonly`` on Linux, and
the other way round. ``terraform providers lock`` with every platform below records one ``h1:``
per platform. The lock file does not say which platform a checksum is for, so this hook counts
them, which catches a lock file written by a plain ``terraform init``; it also checks that each
provider of the module's own ``required_providers`` is locked. That keeps it offline, so it runs in
CI too. Providers that only nested modules require, and changed version constraints, are left to
the workflows' ``terraform init -lockfile=readonly``. Where ``terraform`` is installed, the hook
regenerates the lock files that fail and exits non-zero so the result is committed, as any fixing
hook does.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

PLATFORMS = ["linux_amd64", "darwin_arm64", "darwin_amd64"]

PROVIDER_BLOCK = re.compile(r'^provider "([^"]+)" \{(.*?)^\}', re.MULTILINE | re.DOTALL)
SOURCE = re.compile(r'source\s*=\s*"([^"]+)"')
# A comment, or a quoted string to step over so a "#" inside it does not start one.
COMMENT_OR_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"|#[^\n]*|//[^\n]*|/\*.*?\*/', re.DOTALL)


def strip_comments(text: str) -> str:
    return COMMENT_OR_STRING.sub(lambda m: m.group() if m.group().startswith('"') else "", text)


def find_required_providers(directory: Path) -> set[str]:
    providers = set()
    for tf_file in directory.glob("*.tf"):
        text = strip_comments(tf_file.read_text())
        for start in (match.end() for match in re.finditer(r"required_providers\s*\{", text)):
            depth, end = 1, start
            while depth and end < len(text):
                depth += {"{": 1, "}": -1}.get(text[end], 0)
                end += 1
            for source in SOURCE.findall(text[start:end]):
                providers.add(source if source.count("/") == 2 else f"registry.terraform.io/{source}")
    return providers


def find_problems(directory: Path) -> list[str]:
    lock_file = directory / ".terraform.lock.hcl"
    if not lock_file.exists():
        return [f"{lock_file} is missing"]
    locked = dict(PROVIDER_BLOCK.findall(lock_file.read_text()))
    problems = [
        f"{lock_file}: {provider} is required but not locked"
        for provider in sorted(find_required_providers(directory) - locked.keys())
    ]
    for provider, body in locked.items():
        h1_count = body.count('"h1:')
        if h1_count < len(PLATFORMS):
            problems.append(
                f"{lock_file}: {provider} has {h1_count} h1: checksum(s), expected one for each of "
                f"{', '.join(PLATFORMS)}"
            )
    return problems


def regenerate(directory: Path) -> bool:
    platform_args = [f"-platform={platform}" for platform in PLATFORMS]
    for command in (
        # providers lock needs the modules installed to see their provider requirements.
        ["terraform", "init", "-backend=false", "-input=false"],
        ["terraform", "providers", "lock", *platform_args],
    ):
        if subprocess.run(command, cwd=directory).returncode != 0:
            return False
    return True


def main(filenames: list[str]) -> int:
    directories = sorted({Path(name).parent for name in filenames})
    failed = False
    for directory in directories:
        problems = find_problems(directory)
        if not problems:
            continue
        failed = True
        print("\n".join(problems))
        if shutil.which("terraform") is None:
            print(
                f"Run in {directory}: terraform init -backend=false && terraform providers lock "
                + " ".join(f"-platform={platform}" for platform in PLATFORMS)
            )
        elif regenerate(directory):
            print(f"Regenerated {directory / '.terraform.lock.hcl'}; review and commit it.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
