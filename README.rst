 .. Licensed to the Apache Software Foundation (ASF) under one
    or more contributor license agreements.  See the NOTICE file
    distributed with this work for additional information
    regarding copyright ownership.  The ASF licenses this file
    to you under the Apache License, Version 2.0 (the
    "License"); you may not use this file except in compliance
    with the License.  You may obtain a copy of the License at

 ..   http://www.apache.org/licenses/LICENSE-2.0

 .. Unless required by applicable law or agreed to in writing,
    software distributed under the License is distributed on an
    "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
    KIND, either express or implied.  See the License for the
    specific language governing permissions and limitations
    under the License.

CI Infrastructure for Apache Airflow
====================================

Apache Airflow uses Github Actions as its Continuous Integration (CI) tool. When Airflow contributors open a pull
request, Github Actions runs a series of tests on Apache organization runners. However, due to the limited resources
of these runners, the tests could take a significant amount of time, sometimes up to 2 hours. To improve efficiency
for active committers, a separate set of runners is available for them. These CI runs are executed on self-hosted
runners deployed on an Amazon Elastic Kubernetes Service (EKS) cluster, using
[Actions Runner Controller](https://github.com/actions/actions-runner-controller) (ARC).

This repository contains the necessary scripts and configuration files for managing the CI infrastructure
of Apache Airflow.

.. _aws_configuration:

Access to the AWS Account
-------------------------
Access to the AWS account is primarily restricted to the PMC members. However, as a committer, you can request access
to the account if you believe it is necessary for your contributions. To request access, please inquire on the
`#internal-airflow-ci-cd`_ Slack channel.

.. _#internal-airflow-ci-cd: https://apache-airflow.slack.com/archives/C015SLQF059


Once you have access to the AWS account, you can use the `awscli`_ to interact with the account. To configure the CLI,
you need to follow the steps below:

1. Get your `AWS access key ID`_ and secret access key from the AWS IAM console.

2. Run `aws configure` and enter the credentials when prompted::

       aws configure --profile airflow

   You will be asked to provide the access and secret keys, the region, and the output format.
   For the region, you should choose `us-east-2`, and for the output format, you could skip it to use the default value.

3. Update kubeconfig to access the EKS cluster::

       AWS_PROFILE=airflow aws eks --region us-east-2 update-kubeconfig --name airflow-ci --alias airflow-ci

   This command will update the kubeconfig file located at `~/.kube/config` to include the EKS cluster.
   You can verify that the cluster is added by running `kubectl get nodes`.


.. _awscli: https://aws.amazon.com/cli/
.. _AWS access key ID: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html


Airflow CI infrastructure architecture
--------------------------------------

The design is documented in `docs/eks-runner-architecture.md <docs/eks-runner-architecture.md>`_.
In short: an EKS cluster (standard mode) with a small always-on system node group runs
`Actions Runner Controller <https://github.com/actions/actions-runner-controller>`_ (runner
scale sets mode) and `Karpenter <https://karpenter.sh>`_; runner pods are ephemeral
docker-in-docker pods, one job per pod, on spot nodes that Karpenter provisions on demand
and reclaims when idle.

Deploying from scratch
~~~~~~~~~~~~~~~~~~~~~~

We use Terraform for the AWS resources and Helm (with helmfile) for everything inside the
cluster. The order matters on a fresh account:

1. **Terraform** — see `Terraform Documentation <terraform/README.rst>`_::

       cd terraform/eks
       terraform init
       terraform plan -out=terraform.tfplan
       terraform apply terraform.tfplan

2. **kubeconfig**::

       aws eks --region us-east-2 update-kubeconfig --name airflow-ci --alias airflow-ci

3. **Infra helmfile** (namespaces, Karpenter, NodePools)::

       helmfile -f helm/infra-helmfile.yaml diff
       helmfile -f helm/infra-helmfile.yaml apply

4. **GitHub App secret** — create a GitHub App (for repository-level runners:
   ``Administration: Read & write`` + ``Metadata: Read-only``; for organization-level
   runners: ``Self-hosted runners: Read & write``), install it on the target
   repo/org, then::

       kubectl create secret generic github-config --namespace arc-runners \
         --from-literal=github_app_id=<app-id> \
         --from-literal=github_app_installation_id=<installation-id> \
         --from-file=github_app_private_key=<path-to-private-key.pem>

5. **CI helmfile** (ARC controller + runner scale sets)::

       helmfile -f helm/ci-helmfile.yaml.gotmpl diff
       helmfile -f helm/ci-helmfile.yaml.gotmpl apply

The runner image extends the official ``ghcr.io/actions/actions-runner`` image with the
host tools airflow's CI expects (sudo, docker CLI + compose, python3, ...). Images are
**date-tagged, never ``:latest``** — the tag referenced in
``helm/values/gha-runner-scale-sets/runners.yaml`` must always be an explicit, reviewed
pin. Build and push::

    TAG=$(date +%Y%m%d)
    docker build --platform linux/amd64 \
        -t ghcr.io/apache/airflow-ci-infra/actions-runner:${TAG} runner
    docker push ghcr.io/apache/airflow-ci-infra/actions-runner:${TAG}
    # then update the image tag in helm/values/gha-runner-scale-sets/runners.yaml

Some important notes
~~~~~~~~~~~~~~~~~~~~

- Runner sizing is done with pod **resource requests** (see
  ``helm/values/gha-runner-scale-sets/runners.yaml``), not node selectors/anti-affinity:
  Karpenter picks the cheapest spot instance that fits the request. The current single
  ``airflow-runner-amd-xl`` class requests a whole 32-vCPU node per job.
- Scale-up path: job queued → ARC listener requests a runner pod → pod Pending →
  Karpenter launches a node (~60-90s). Scale-down: pod finishes → node empty →
  Karpenter consolidates it after 60s (``WhenEmpty`` — running jobs are never evicted).
- The dockerd inside each runner is configured (dind sidecar args in
  ``helm/values/gha-runner-scale-sets/common.yaml.gotmpl``) with a registry mirror,
  widened address pools and nofile ulimits — these fix real failures observed with
  airflow's CI and should not be removed casually.
- Workflows target the runners with ``runs-on: <scale-set-name>``, e.g.
  ``runs-on: airflow-runner-amd-xl``.
- **Spot policy (phase 1): spot-first for everything, deliberately.** A spot reclaim
  kills the job mid-run — the job shows red with a "runner lost communication"
  annotation; just re-run the failed jobs. Tripwire: if interruptions exceed ~2/week
  (or kill the same canary twice in a row), pin the heavy runner class to on-demand
  (``karpenter.sh/capacity-type`` requirement in the NodePool) once size classes are
  split.
