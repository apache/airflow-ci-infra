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

output "entry_point" {
  description = "RunsOn web entry point: open it once after creation to register the GitHub App."
  value       = module.runs_on.ingress.url
}

output "cache_bucket" {
  description = "S3 bucket the runners can use under the cache/ prefix (stash payloads)."
  value       = module.runs_on.platform.cache.bucket_name
}

output "subnets" {
  description = "Public subnet of the runners in each zone, by zone ID."
  value       = { for zone_id, subnet in aws_subnet.public : zone_id => subnet.id }
}

output "getting_started" {
  description = "RunsOn's post-apply instructions, including the env= label jobs need for this stack."
  value       = module.runs_on.stack.getting_started
}
