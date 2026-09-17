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

# EKS standard mode with self-managed Karpenter, not EKS Auto Mode

Status: accepted (2026-07-25)

The CI runner cluster runs EKS in standard mode with Karpenter installed and
managed by us, even though EKS Auto Mode is AWS's recommended default and would
remove Karpenter, AMI, and addon management entirely. Auto Mode nodes are
locked-down Bottlerocket appliances — SELinux enforcing, immutable read-only
root, no SSH/SSM, no node-level customization — and our runner pods are
privileged docker-in-docker workloads that run KinD (Kubernetes *inside* that
dind) and require node sysctls (`fs.inotify.*`, `nf_conntrack`, `fs.nr_open`);
this is precisely the workload class that fights a locked host, and it is
battle-tested on plain AL2023 with our own user data. Auto Mode also adds a
per-instance management fee (~10–12% of the instance price) to a
compute-dominated, budget-capped bill.

Revisit if the workload ever stops needing privileged dind (e.g. jobs move to
rootless/kaniko-style builds and KinD is replaced), or if Auto Mode gains
supported node-level sysctl/privileged-workload customization at a fee that
undercuts our measured operational cost of self-managing Karpenter
(~a few hours per quarter).
