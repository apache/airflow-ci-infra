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
  cluster_name = "airflow-ci"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns    = {}
    kube-proxy = {}
    # before_compute: the module disables EKS's bootstrap self-managed CNI when
    # managed addons are used, so vpc-cni must exist BEFORE nodes boot — nodes
    # without a CNI never become Ready and the node group lands in CREATE_FAILED
    # (bitten by this on 2026-07-25 when a crashed apply skipped the addons).
    vpc-cni = {
      before_compute = true
    }
    # Required for Karpenter's Pod Identity association.
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  # Karpenter's EC2NodeClass discovers the node security group by this tag.
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  eks_managed_node_groups = {
    # Small always-on group for the controllers (Karpenter, ARC, listeners).
    # Everything else runs on Karpenter-provisioned nodes.
    system = {
      name           = "airflow-ci-system"
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        "airflow-ci/role" = "system"
      }
    }
  }
}
