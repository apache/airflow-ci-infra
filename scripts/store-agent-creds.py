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
import json
import os
import platform
import subprocess
import tempfile
from typing import Optional, Tuple

import boto3
import click
import requests
from botocore.exceptions import NoCredentialsError


@click.command()
@click.option(
    "--runner-version",
    default="2.275.1",
    help="Runner version to register with",
    metavar="VER",
)
@click.option("--repo", default="apache/airflow")
@click.option("--store-as", default="apache/airflow")
@click.option("--runnergroup")
@click.option("--token", help="GitHub runner registration token", required=False)
@click.option("--index", type=int, required=False)
def main(
    token, runner_version, store_as: Optional[str], repo, runnergroup: Optional[str], index: Optional[int]
):
    check_aws_config()
    dir = make_runner_dir(runner_version)

    if not token:
        token = click.prompt("GitHub runner registration token")

    if store_as is None:
        store_as = repo

    if index is None:
        index = get_next_index(store_as)
    click.echo(f"Registering as runner {index}")

    register_runner(dir.name, token, repo, runnergroup, store_as, index)


def check_aws_config():
    click.echo("Checking AWS account credentials")
    try:
        whoami = boto3.client("sts").get_caller_identity()
    except NoCredentialsError:
        click.echo("No AWS credentials found -- maybe you need to set AWS_PROFILE?", err=True)
        exit(1)

    if whoami["Account"] != "827901512104":
        click.echo("Wrong AWS account in use -- maybe you need to set AWS_PROFILE?", err=True)
        exit(1)


def make_runner_dir(version):
    """Extract the runner tar to a temporary directory"""
    dir = tempfile.TemporaryDirectory()

    tar = _get_runner_tar(version)

    subprocess.check_call(
        ["tar", "-xzf", tar],
        cwd=dir.name,
    )

    return dir


def get_next_index(repo: str) -> int:
    """Find the next available index to store the runner credentials in AWS SSM ParameterStore"""
    paginator = boto3.client("ssm").get_paginator("describe_parameters")

    path = os.path.join('/runners/', repo, '')

    pages = paginator.paginate(ParameterFilters=[{"Key": "Path", "Option": "Recursive", "Values": [path]}])

    seen = set()

    for page in pages:
        for param in page['Parameters']:
            name = param['Name']

            # '/runners/1/config' -> '1'
            index = os.path.basename(os.path.dirname(name))
            seen.add(int(index))

    if not seen:
        return 1

    # Fill in any gaps too.
    for n in range(1, max(seen) + 2):
        if n not in seen:
            return n


def register_runner(dir: str, token: str, repo: str, runnergroup: Optional[str], store_as: str, index: int):
    os.chdir(dir)

    cmd = [
        "./config.sh",
        "--unattended",
        "--url",
        f"https://github.com/{repo}",
        "--token",
        token,
        "--name",
        f"Airflow Runner {index}",
    ]

    if runnergroup:
        cmd += ['--runnergroup', runnergroup]

    res = subprocess.call(cmd)

    if res != 0:
        exit(res)
    _put_runner_creds(store_as, index)


def _put_runner_creds(repo: str, index: int):
    client = boto3.client("ssm")

    with open(".runner", encoding='utf-8-sig') as fh:
        # We want to adjust the config before storing it!
        config = json.load(fh)
        config["pullRequestSecurity"] = {}

        client.put_parameter(
            Name=f"/runners/{repo}/{index}/config",
            Type="String",
            Value=json.dumps(config, indent=2),
        )

    with open(".credentials", encoding='utf-8-sig') as fh:
        client.put_parameter(Name=f"/runners/{repo}/{index}/credentials", Type="String", Value=fh.read())

    with open(".credentials_rsaparams", encoding='utf-8-sig') as fh:
        client.put_parameter(Name=f"/runners/{repo}/{index}/rsaparams", Type="SecureString", Value=fh.read())


def _get_system_arch() -> Tuple[str, str]:
    uname = platform.uname()
    if uname.system == "Linux":
        system = "linux"
    elif uname.system == "Darwin":
        system = "osx"
    else:
        raise RuntimeError("Un-supported platform")

    if uname.machine == "x86_64":
        arch = "x64"
    else:
        raise RuntimeError("Un-supported architecture")

    return system, arch


def _get_runner_tar(version) -> str:
    system, arch = _get_system_arch()

    cache = os.path.abspath(".cache")

    try:
        os.mkdir(cache)
    except FileExistsError:
        pass

    fname = f"actions-runner-{system}-{arch}-{version}.tar.gz"
    local_file = os.path.join(cache, fname)

    if os.path.exists(local_file):
        return local_file

    url = f"https://github.com/actions/runner/releases/download/v{version}/{fname}"
    click.echo(f"Getting {url}")
    resp = requests.get(url, stream=True)
    resp.raise_for_status()
    with open(local_file, "wb") as fh, click.progressbar(length=int(resp.headers["content-length"])) as bar:
        for chunk in resp.iter_content(chunk_size=40960):
            fh.write(chunk)
            bar.update(len(chunk))
    return local_file


if __name__ == "__main__":
    main()
