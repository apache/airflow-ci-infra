<!--
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
-->

# AGENTS instructions

## Terraform lock files

Every Terraform module under `terraform/` commits its `.terraform.lock.hcl`, and the lock file
must hold provider checksums for Linux (the CI runners) and macOS (maintainers' machines). The
workflows run `terraform init -lockfile=readonly`, which fails on a platform the lock file does
not cover. `terraform init` alone records only the platform it runs on.

Whenever a pull request adds a module, adds a provider or changes a provider version, generate
the lock file for all platforms and commit it in the same pull request:

```bash
cd terraform/<module>
terraform init -backend=false
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

The `terraform-lock-platforms` prek hook (`scripts/terraform_lock_platforms.py`) checks this on
every commit that touches a module, and in the `prek` workflow on every pull request. Where
`terraform` is installed it runs the commands above itself and fails the commit, so you review and
commit the regenerated lock file. If `terraform` cannot reach the registry (in an agent sandbox, for
example), ask the user to run the commands; never hand-edit the checksums.
