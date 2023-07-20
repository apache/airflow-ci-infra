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

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "airflow"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = local.cluster_name
  cluster_version = "1.27"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_ARM_64"
  }

  eks_managed_node_groups = {

    default_nodes = {
      name = "default"

      instance_types = ["t4g.small"]

      min_size     = 1
      max_size     = 3

      capacity_type  = "SPOT"

      labels = {
        "node-type" = "default"
      }
    }

    GHA_runners_small = {
      name = "gha-runners-small"

      instance_types = ["t4g.small"]

      min_size     = 0
      max_size     = 3
      desired_size = 0

      capacity_type  = "SPOT"

      labels = {
        "node-type" = "gha-runners"
        "size" = "small"
      }

      taints = [
        {
          "key"    = "node-type"
          "value"  = "gha-runners"
          "effect" = "NO_SCHEDULE"
        }
      ]
    }

    GHA_runners_medium = {
      name = "gha-runners-medium"

      instance_types = ["t4g.medium"]

      min_size     = 0
      max_size     = 3
      desired_size = 0

      capacity_type  = "SPOT"

      labels = {
        "node-type" = "gha-runners"
        "size" = "medium"
      }

      taints = [
        {
          "key"    = "node-type"
          "value"  = "gha-runners"
          "effect" = "NO_SCHEDULE"
        }
      ]
    }
  }
}

