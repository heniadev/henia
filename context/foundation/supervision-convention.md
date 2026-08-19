---
project: "Henia"
requirement: FR-470
established: 2026-08-19
cluster: tachiko.kondi.net (88.99.160.8), k3s v1.36.3+k3s1
---

# Supervision convention

The answer to **FR-470** — *a supervising layer manages the lifecycle of each
instance* — for Henia's own cluster. Written during `devserver-setup` phase 7,
and demonstrated on the cluster rather than asserted.

Placed in `context/foundation/` rather than the change folder because it is a
durable project decision: the change that produced it will be archived, and this
must outlive it.

## The convention

**k3s is the supervising layer.** Henia does not build one.

This follows the delegate-to-native-mechanisms position the PRD holds throughout
Access Control, and it is the resolution already recorded in FR-470's own
Socratic notes: the supervising layer is itself supervised by the platform.
Building a bespoke supervisor would rebuild what the platform already provides,
and would then need supervising in turn.

Concretely:

- **Instances are delivered as Deployments.** A Deployment's controller
  maintains the declared replica count; a pod that dies is replaced with no
  human action.
- **Health is liveness, not progress.** An instance is healthy when all of its
  components are running. This is deliberately a liveness definition — a loop
  that runs while making no progress still counts as healthy. Detecting
  no-progress is the concern of FR-112's observation path, not of supervision.
- **Components declare liveness and readiness probes.** A container failing its
  liveness probe is restarted by the kubelet; a container failing readiness is
  removed from service endpoints without being killed.
- **Agent-level restarts stay inside the instance's own main loop.** The
  supervising layer restarts *components*, never individual agent runs.
  FR-240 requires an agent to stop into a stated recoverable condition, and a
  supervisor-initiated restart would bypass that guarantee. This boundary is the
  reason the convention has to be written down rather than assumed.

## What was demonstrated

On tachiko, 2026-08-19, with a throwaway Deployment (removed afterwards):

| Behaviour | Observed |
| --- | --- |
| Pod deleted from a Deployment | Replaced automatically; new pod reached `Running` without intervention |
| Container failing its liveness probe | Restarted repeatedly; `restartCount` climbed 2 → 3 under observation |
| Failure surfaced as an event | `Warning Unhealthy … Liveness probe failed: HTTP probe failed with statuscode: 404` |

The liveness probe pointed at a path the container does not serve, so the
failure was induced rather than waited for.

## Known limits

- **A single node has nowhere to reschedule to.** Supervision here means
  restart-in-place, not failover. The infrastructure risk register already
  carries this as "single point of failure — no HA, nowhere to reschedule".
- **Restart loops are not progress.** A component that crashes and is restarted
  forever satisfies this convention while delivering nothing. Prometheus
  (FR-270) is what makes that visible; supervision alone will not surface it.
- **Nothing supervises k3s itself** beyond systemd on the host. That is the
  accepted end of the chain on a self-administered single-node cluster.
