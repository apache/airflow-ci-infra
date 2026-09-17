# Airflow CI Infrastructure

Self-hosted GitHub Actions runner infrastructure (EKS + ARC + Karpenter) that offloads
selected Apache Airflow CI workloads from GitHub-hosted runners to AWS.

## Language

### Workload categories

**Trusted run**:
A workflow run whose code ref is not attacker-controllable: `schedule`, `push`, or
`workflow_dispatch` events on `apache/airflow` itself. The only category eligible for
self-hosted runners in phase 1.
_Avoid_: using "trusted" for committer-authored PRs — those are Committer runs.

**Canary run**:
A full-matrix CI run of main, triggered by cron (`schedule`) or by a push to main.
"Scheduled canary" and "push canary" distinguish the trigger when it matters.

**Committer run**:
A CI run of a PR authored by someone with merge access (regardless of whether it comes
from a fork or a branch). Not a Trusted run — the PR code is still unreviewed; serving
these from self-hosted runners is a separate, unresolved decision.
_Avoid_: trusted PR, member run.

**Fork PR run**:
A CI run of a PR from a contributor without merge access. Never eligible for
self-hosted runners.

### Infrastructure

**Runner scale set**:
An ARC unit of runner capacity targeted by a single `runs-on` label (e.g.
`airflow-runner-amd-xl`). One helm release per scale set.
_Avoid_: runner deployment (legacy ARC term), runner pool.

**Runner class**:
The size tier of a scale set, expressed as pod resource requests (CPU/memory), not as a
node type. Karpenter chooses the actual instance.

**System node group**:
The small always-on EKS managed node group hosting the controllers (ARC, Karpenter,
listeners). Everything else runs on Karpenter-provisioned nodes.

**Stash**:
The S3-backed mechanism for passing artifacts between jobs of a run (drop-in for the
`apache/infrastructure-actions/stash` actions).
