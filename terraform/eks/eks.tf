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
  version = "20.24.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type                   = "AL2_ARM_64"
    use_custom_launch_template = false
    disk_size                  = 50
    desired_size               = 0
  }

  eks_managed_node_groups = {

    default_nodes = {
      name = "default"

      instance_types = ["t4g.medium"]

      min_size     = 0
      max_size     = 5
      desired_size = 1

      capacity_type = "SPOT"

      labels = {
        "node-type" = "default"
      }
    }

    # GHA arm runners' nodes
    GHA_runners_small = {
      name = "gha-runners-small"

      instance_types = [for node_type in var.runners_node_types: "${node_type}.${var.small_runners_node_size}"]

      min_size = 0
      max_size = 30

      capacity_type = "SPOT"

      disk_size = 50

      labels = {
        "node-type" = "gha-runners"
        "size"      = "small"
        "arch"      = "arm64"
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

      instance_types = [for node_type in var.runners_node_types: "${node_type}.${var.medium_runners_node_size}"]

      min_size = 0
      max_size = 30

      capacity_type = "SPOT"

      disk_size = 50

      labels = {
        "node-type" = "gha-runners"
        "size"      = "medium"
        "arch"      = "arm64"
      }

      taints = [
        {
          "key"    = "node-type"
          "value"  = "gha-runners"
          "effect" = "NO_SCHEDULE"
        }
      ]
    }

    GHA_runners_large = {
      name = "gha-runners-large"

      instance_types = [for node_type in var.runners_node_types: "${node_type}.${var.large_runners_node_size}"]

      min_size = 0
      max_size = 30

      capacity_type = "SPOT"

      labels = {
        "node-type" = "gha-runners"
        "size"      = "large"
        "arch"      = "arm64"
      }

      taints = [
        {
          "key"    = "node-type"
          "value"  = "gha-runners"
          "effect" = "NO_SCHEDULE"
        }
      ]
    }

    # GHA x64 runners' nodes
    x64_GHA_runners_small = {
      name = "gha-x64-runners-small"

      ami_type = "AL2_x86_64"

      instance_types = [for node_type in var.x64_runners_node_types: "${node_type}.${var.small_runners_x64_node_size}"]

      min_size = 0
      max_size = 30

      capacity_type = "SPOT"

      disk_size = 50

      labels = {
        "node-type" = "gha-runners"
        "size"      = "small"
        "arch"      = "x64"
      }

      taints = [
        {
          "key"    = "node-type"
          "value"  = "gha-runners"
          "effect" = "NO_SCHEDULE"
        }
      ]
    }

    x64_GHA_runners_medium = {
      name = "gha-x64-runners-medium"

      ami_type = "AL2_x86_64"

      instance_types = [for node_type in var.x64_runners_node_types: "${node_type}.${var.medium_runners_node_size}"]

      min_size = 0
      max_size = 30

      capacity_type = "SPOT"

      disk_size = 50

      labels = {
        "node-type" = "gha-runners"
        "size"      = "medium"
        "arch"      = "x64"
      }

      taints = [
        {
          "key"    = "node-type"
          "value"  = "gha-runners"
          "effect" = "NO_SCHEDULE"
        }
      ]
    }

    x64_GHA_runners_large = {
      name = "gha-x64-runners-large"

      ami_type = "AL2_x86_64"

      instance_types = [for node_type in var.x64_runners_node_types: "${node_type}.${var.large_runners_node_size}"]

      min_size = 0
      max_size = 30

      capacity_type = "SPOT"

      labels = {
        "node-type" = "gha-runners"
        "size"      = "large"
        "arch"      = "x64"
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

