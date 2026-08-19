# Devserver Setup — Cluster Substrate — Plan Brief

> Full plan: `context/changes/devserver-setup/plan.md`

## What & Why

Turn the delivered Hetzner machine `tachiko.kondi.net` (88.99.160.8) into the
secured single-node k3s cluster that Henia's own development runs on. This is
roadmap **F-01 `cluster-substrate`** — the item everything else descends from,
and the one whose blocker ("hardware not delivered or verified") cleared on
2026-08-19.

## Starting Point

A bare Ubuntu 26.04 box: RAID1 across two NVMes, 62 GiB non-ECC RAM, 857 GB free,
KVM available, **nothing installed**, and **no firewall at all**. Separately, an
older k3s v1.25 cluster at `10.242.0.10` already runs Gitea, Tekton, Argo CD and
cert-manager — it is not in scope, but Henia must reach its Gitea.

One piece of the plan is already done: the root filesystem's ext4 `project` and
`quota` features were enabled during a Hetzner rescue boot on 2026-08-19, because
ext4 cannot add them to a mounted root.

## Desired End State

k3s `v1.36.3+k3s1` running behind a deliberate perimeter, with HAProxy ingress,
a capacity-bounded workspace directory, a read-only identity the devcontainer
uses to read cluster state back, Prometheus collecting, and a written supervision
convention. The Henia operator is not deployed.

## Key Decisions Made

| Decision | Choice | Why | Source |
| --- | --- | --- | --- |
| Scope vs F-01 | This change *is* F-01, substrate only | The roadmap item is what the work serves; the operator does not exist yet | this planning |
| Operator code | Not scaffolded or deployed | Keeps the change to substrate; accepted cost is that F-01 does not fully close | this planning |
| Gitea | Stays on the existing cluster | Zero migration risk to the one system the whole loop depends on | this planning |
| Platform | Hetzner dedicated + k3s | Bare metal is the only option that supplies real virtualisation for the `knest` sandbox | foundation |
| k3s version | Pinned `v1.36.3+k3s1` | Matches kubebuilder v4.15.0's Kubernetes 1.36 target exactly; costs nothing | probe |
| Storage | k3s local-path, kept | Already the recorded decision, and already the existing cluster's default | foundation |
| Ingress | HAProxy 1.9.0, Traefik disabled | Matches the existing cluster, so the two environments do not diverge | this planning |
| Workspace boundary | ext4 project quota, 200 GiB | Buys the capacity boundary LVM would have, without a reinstall | this planning |
| Quota mechanism | Rescue boot, native on root | ext4 cannot enable `project` while mounted; chosen over a loopback image | this planning |
| LVM | Not used | Both disks fully allocated; nothing in the plan needs snapshots or resizing | this planning |
| SSH exposure | Open to the world | Operator decision; also the recovery path if the 6443 rules are wrong | this planning |
| 6443 exposure | Public, allowlisted to AS12912 | Survives T-Mobile reassignment; narrowing deferred to a debt slice | this planning |
| FR-470 supervision | k3s is the supervising layer | The PRD's own Socratic resolution already says the platform supervises | foundation |
| FR-270 telemetry | Prometheus on tachiko | Keeps the project cluster self-contained | this planning |
| FR-085 challenge gap | Noted as an open risk, not blocking | The design is already prototyped and working in `rbac.yaml` | this planning |

## Scope

**In:** ext4 project quota and tooling; nftables perimeter with an AS12912 set and
a refresh script; k3s install pinned, Traefik disabled; HAProxy ingress as default
class; read-only ServiceAccount and regenerated devcontainer kubeconfig;
Prometheus with k3s scraping; a supervision convention document and its
demonstration.

**Out:** the Henia operator; Gitea migration; the existing cluster; cert-manager,
Tekton, Virtink, Harbor; off-box datastore backups; SSH hardening and key
rotation; LVM or reinstall; VPN; narrowing the 6443 allowlist.

## Architecture / Approach

Work outward from host to cluster so each layer is verifiable before the next
depends on it. Two orderings are forced, not chosen: the quota had to precede
everything (offline filesystem change on root), and the firewall must precede k3s
(installing k3s opens 6443 immediately). Everything in-cluster is delivered as
declarative manifests in k3s's auto-deploy directory, so cluster contents are
reproducible from files rather than from typed commands.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1 · Root filesystem quota | Hard cap on workspace storage | Offline part done; remaining risk is a limit set too low to be useful |
| 2 · Host firewall | The perimeter, before anything listens | Locking yourself out — mitigated by world-open SSH |
| 3 · k3s install, pinned | The cluster itself, Traefik disabled | Version pin drifting from what the scaffold targets |
| 4 · HAProxy ingress | Single hostname-routed entry point | Divergence from the existing cluster's controller config |
| 5 · Read-only identity | FR-085 — read cluster state, change nothing | A stray write verb silently defeating the central claim |
| 6 · Prometheus | FR-270 — a collector that demonstrably scrapes | Retention competing for the same disk as everything else |
| 7 · Supervision convention | FR-470 — written and demonstrated | Satisfying a must-have with a document rather than behaviour |

**Prerequisites:** none outstanding. The hardware is delivered and verified, the
rescue-boot filesystem work is complete, and the machine is reachable.

**Estimated effort:** roughly two focused days. Phases 2–3 are the substance;
phases 1, 4 and 7 are short; phase 6 expands to fill whatever time is given it,
so it should be timeboxed.

## Open Risks & Assumptions

- **F-01 will not fully close.** Its outcome statement says the framework runs in
  a cluster; with substrate-only scope, FR-270 and FR-470 are prepared rather
  than demonstrated against real Henia components. A follow-up change is needed
  before F-01 can be marked done. This was an explicit, informed decision.
- **FR-085 has never had its Socratic challenge** (roadmap Open Question #4,
  which says to resolve it before F-01 is planned). Carried as a known unmet
  review step rather than a blocker.
- **The 6443 allowlist is wide** — ~1.36M addresses across 47 prefixes — and it
  rots as BGP announcements change. Both the refresh script and the narrowing
  debt slice exist because of this.
- **Non-ECC memory** on a box whose dominant risk is memory pressure. Cannot be
  fixed on this hardware; it raises the value of off-box datastore backups, which
  this change deliberately does not deliver.
- **Cross-cluster dependency on Gitea.** Every pipeline run reaches another host;
  if that link or that older cluster degrades, Henia's loop stops.
- **Assumption:** the devcontainer's egress stays inside AS12912. If it moves to
  another carrier, 6443 access is lost until the set is widened — recoverable
  over SSH.

## Success Criteria (Summary)

The cluster answers as `v1.36.3+k3s1` on a node that is `Ready`, reachable from
the devcontainer and refused from outside the allowlist. A write past 200 GiB in
the workspace directory is refused by quota rather than filling the disk. The
read-only identity lists pods everywhere and is denied every write and every
Secret read. An Ingress routes by hostname through HAProxy. Prometheus reports
kubelet and API-server targets `up`. A deleted pod comes back by itself.
