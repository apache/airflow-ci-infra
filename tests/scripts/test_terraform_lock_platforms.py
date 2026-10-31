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
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))

from terraform_lock_platforms import find_problems  # noqa: E402

LOCK = """
provider "registry.terraform.io/hashicorp/aws" {
  version = "6.70.0"
  hashes = [
%s
    "zh:068ca7ed4fc77e3d63d7fac54515a426a32f3dc143b55a6ad00963fe68289955",
  ]
}
"""
THREE_PLATFORMS = '    "h1:a=",\n    "h1:b=",\n    "h1:c=",'
REQUIRES_AWS = """
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws" # "#" in a comment
      version = "~> 6.0"
    }
    # random = { source = "hashicorp/random" }
    // time = { source = "hashicorp/time" }
    /* null = { source = "hashicorp/null" } */
  }
}

module "runs_on" {
  source = "runs-on/runs-on/aws//modules/flex"
}
"""


@pytest.mark.parametrize(
    "hashes, version_tf, expected",
    [
        pytest.param(THREE_PLATFORMS, REQUIRES_AWS, [], id="complete"),
        pytest.param(
            '    "h1:a=",',
            REQUIRES_AWS,
            ["registry.terraform.io/hashicorp/aws has 1 h1: checksum(s)"],
            id="one-platform",
        ),
        pytest.param(
            THREE_PLATFORMS,
            REQUIRES_AWS + 'terraform {\n  required_providers {\n    random = {\n'
            '      source = "hashicorp/random"\n    }\n  }\n}\n',
            ["registry.terraform.io/hashicorp/random is required but not locked"],
            id="unlocked-provider",
        ),
    ],
)
def test_find_problems(tmp_path, hashes, version_tf, expected):
    (tmp_path / ".terraform.lock.hcl").write_text(LOCK % hashes)
    (tmp_path / "version.tf").write_text(version_tf)

    problems = find_problems(tmp_path)

    assert len(problems) == len(expected)
    for problem, fragment in zip(problems, expected):
        assert fragment in problem


def test_find_problems_without_lock_file(tmp_path):
    (tmp_path / "version.tf").write_text(REQUIRES_AWS)

    assert find_problems(tmp_path) == [f"{tmp_path / '.terraform.lock.hcl'} is missing"]
