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

# IAM + SQS plumbing for Karpenter (controller role via EKS Pod Identity, node
# role + access entry, spot-interruption queue). Karpenter itself is installed
# with helmfile (helm/infra-helmfile.yaml); the names below are referenced from
# the helm values, so they are pinned instead of name-prefixed.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.24"

  cluster_name = module.eks.cluster_name

  # Referenced by helm/values/karpenter.yaml (settings.interruptionQueue).
  queue_name = "airflow-ci-karpenter"

  # Referenced by the EC2NodeClass (spec.role) in helm/karpenter-resources.
  node_iam_role_name            = "airflow-ci-runner-node"
  node_iam_role_use_name_prefix = false

  create_pod_identity_association = true
}
