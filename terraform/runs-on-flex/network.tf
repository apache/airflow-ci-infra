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

# Runners get public IPs in public subnets (no NAT cost, Docker Hub pulls per runner IP), as on the
# CloudFormation stack, but in all three zones of the region: that stack is fixed to the first two,
# and on 2026-10-30 their Spot placement score for the runners' families was 1 against 9 in
# use2-az3 (README, "Why this module"). Zones are pinned by ID because zone names map to different
# zones in every account, and Spot placement scores are reported by ID.
locals {
  zone_ids = ["use2-az1", "use2-az2", "use2-az3"]
}

resource "aws_vpc" "runners" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.stack_name}-vpc"
  }
}

resource "aws_internet_gateway" "runners" {
  vpc_id = aws_vpc.runners.id

  tags = {
    Name = "${var.stack_name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(local.zone_ids)

  vpc_id                  = aws_vpc.runners.id
  availability_zone_id    = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, index(local.zone_ids, each.key))
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.stack_name}-public-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.runners.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.runners.id
  }

  tags = {
    Name = "${var.stack_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Free, and keeps the stash payloads in the cache bucket (multi-gigabyte image tars) off the
# internet gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.runners.id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = {
    Name = "${var.stack_name}-s3"
  }
}
