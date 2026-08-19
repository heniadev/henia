---
project: "Henia"
researched_at: 2026-08-18
hardware_verified_at: 2026-08-19
recommended_platform: hetzner-auction-dedicated-k3s
runner_up: digitalocean-doks
context_type: mvp
tech_stack:
  language: go
  framework: kubebuilder
  runtime: kubernetes
---

# Infrastructure decision — Henia

Reduced mode: Kubernetes is a locked product requirement, so this document
describes an imposed platform operationally rather than racing platforms against
each other. Scope is the project's own cluster — the one that runs Gitea, Tekton,
Prometheus and Henia itself for dogfooding and for the conference on 2026-10-22.
Adopters' clusters are their decision, not this one.

Every platform claim below traces to a web check made on **2026-08-18**. Nothing
here comes from training memory.

## Recommendation

**A Hetzner server-auction dedicated machine running k3s.** The hardware was
already ordered on 2026-08-18, which supersedes the interview's "new managed
Kubernetes" answer — this document records the decision that exists rather than
one that does not.

The decisive technical argument is capability, and it is worth stating because it
would have excluded most of the alternatives anyway. Henia's named inner-loop
sandbox, `knest`, runs on Virtink, which requires a privileged DaemonSet and
`--allow-privileged=true` (checked 2026-08-18). Bare metal supplies real
virtualization; several managed options do not. GKE Autopilot blocks privileged
containers by default, does not support host namespaces, and disallows hostPath
writes — it cannot run this stack, which is the hard "runtime not supported"
filter rather than a low score. Bare metal removes the `/dev/kvm` question that
otherwise dominated the risk picture: on a managed provider whose nodes are
themselves virtual machines, whether a privileged pod can open `/dev/kvm` is
undocumented and per-provider.

**The honest counterweight, recorded rather than smoothed over.** The interview
answer was *minimise operational effort*, and a self-administered bare-metal box
is the opposite of that. You now own OS patching, kernel, k3s upgrades,
certificates, firewall, monitoring and backups — several days of setup plus
ongoing time, against a nine-week deadline where the product is the deliverable
(guide checked 2026-08-18 puts initial setup at "several days"). The purchase is
a fact and this document is written against it; the tension is real and appears
in the risk register rather than being argued away.

## Delivered hardware

The machine ordered on 2026-08-18 was delivered and inspected over SSH on
**2026-08-19**. Everything in this section is a direct observation from that
machine, not a listing claim. It supersedes the per-listing uncertainties
recorded under *Unknown Unknowns*.

**`tachiko.kondi.net` — 88.99.160.8**, Ubuntu 26.04 LTS, kernel 7.0.0-22.

| Facet | Observed |
| --- | --- |
| CPU | Intel i7-8700, 6 cores / 12 threads, `vmx` present |
| Memory | 62 GiB usable (4 × 16 GB DDR4) — **non-ECC** |
| Storage | 2 × 954 GB NVMe, **mdraid RAID1**, arrays `md0` swap / `md1` `/boot` / `md2` `/`, all clean `[UU]` |
| Capacity | `/` is 905 GB with 857 GB free; both disks fully partitioned, no unallocated space |
| Virtualisation | `/dev/kvm` present, `kvm_intel` loaded, nested virtualisation on |
| Installed | nothing — no container runtime, no k3s, no application code; sshd is the only listening service |
| Firewall | **none active** — no ufw, no nftables ruleset |

Three consequences for decisions already recorded:

- **Redundant storage exists**, which the roadmap listed as an open unknown and
  this document listed as a per-listing fact. Node-local storage is mirrored,
  so the *Storage: node-local* decision carries less exposure than written.
- **Virtink's hardware requirement is satisfied.** The capability argument that
  selected bare metal over managed Kubernetes holds on the actual machine, not
  only in principle. The cluster-side requirements —
  `--allow-privileged=true` and the privileged DaemonSet — remain untested until
  k3s is installed.
- **No LVM, and none needed.** Storage is plain mdraid plus ext4 with no volume
  manager, and both disks are fully allocated with no free extents. Since the
  storage decision is k3s local-path-provisioner writing into a directory on
  `/`, introducing LVM would require a reinstall to buy flexibility nothing in
  this plan asks for. Recorded so the question is not reopened without a reason.
  The capacity boundary that LVM would have provided is better bought with an
  ext4 project quota on the local-path directory — see the risk register.

## Platform Comparison

Reduced mode replaces the platform race with configuration-level decisions inside
the fixed platform. Six options were researched; the comparison below is what
survives as a decision.

| Option | Control plane | Cost | Privileged / KVM | Verdict |
| --- | --- | --- | --- | --- |
| Hetzner auction + k3s | self-run | from ~€39/mo | yes, bare metal | **chosen** — capability, cost |
| DigitalOcean DOKS | free (HA $40/mo) | nodes from $12/mo | privileged yes; KVM unverified | runner-up / fallback |
| Civo | free | nodes from $5/mo | privileged yes; KVM unverified | third |
| Akamai LKE | free (HA $60/mo) | compute only | privileged yes; KVM unverified | researched |
| Scaleway Kapsule | managed | managed pricing | unverified | researched — ships Prometheus and logging integration; genuinely close |
| GKE Autopilot | $0.10/hr, one cluster covered by $74.40/mo free-tier credit | pod-based | **no** — privileged blocked | **excluded on capability** |

Two provider families are represented: managed Kubernetes and self-administered.
The self-administered family won on a capability requirement, not on price.

Component-level decisions inside the fixed platform:

- **Distribution: k3s.** Bundles the control plane into one binary and ships
  Traefik plus local-path-provisioner. Single-node friendly, and it lets you pin
  the Kubernetes version yourself rather than waiting for a provider — which
  matters, because kubebuilder v4.15.0 targets Kubernetes 1.36.
- **Storage: node-local.** No managed block storage exists on Hetzner dedicated.
  Agent workspaces (FR-040) live on the same disk as everything else.
- **Ingress: one public address.** Gitea, Tekton, the Henia GUI and the metrics
  surface all route by hostname behind a single certificate story.
- **Secrets: in-cluster Kubernetes Secrets**, per the interview.

### Shortlisted Platforms

**Hetzner auction dedicated + k3s (chosen).** Real virtualization, so the
inner-loop sandbox works as designed rather than as a compromise. Auction
hardware is refurbished, priced from around €39/mo, with no setup fee. Hetzner
guarantees functional hardware and replaces defective components, but auction
support runs at lower priority than regular servers. Full root access, fully
unmanaged.

**DigitalOcean DOKS (runner-up, and the documented fallback).** Free control
plane, nodes from $12/mo, HA control plane $40/mo. Strongest CLI and
documentation of the managed three, predictable flat pricing, full node access
and privileged workloads permitted. The open question is whether `/dev/kvm` is
available to a privileged pod on standard node types — unverified, and the single
thing to test before falling back here.

**Civo (third).** Free control plane, nodes from $5/mo, k3s-based with very fast
cluster creation. Cheapest managed option and closest in shape to what will run
on the Hetzner box, which makes it the least disruptive emergency migration.
Smaller ecosystem means fewer answers when something behaves oddly — which
weighs more for a solo builder.

## Anti-Bias Cross-Check

The lenses were run twice: once against DOKS as the original leader, then again in
full against the Hetzner box after the swap. Only the second run is recorded here,
per the swap rule.

### Devil's Advocate — Weaknesses

- **Refurbished hardware fails more often, and support is deprioritised.** The
  auction line is explicitly positioned for workloads that tolerate higher
  hardware-failure risk. A disk failing in week seven is a live possibility, and
  auction tickets are handled at lower priority than regular servers.
- **One box is the entire environment.** No control-plane HA, nowhere to
  reschedule, no second place to try anything. If it goes, the demo goes and
  there is no partial degradation — it is binary.
- **Node-local storage with no managed alternative.** k3s's local-path
  provisioner puts agent workspaces on the same disk as the control plane
  datastore. Whether that disk is redundant depends on whether RAID was
  configured at install, which is a per-listing fact rather than a platform
  guarantee.
- **Resource contention is the likeliest failure, not hardware.** Gitea, Tekton,
  Prometheus, Henia and nested agent VMs share one machine's CPU and RAM. Agent
  workloads are bursty and memory-hungry; a runaway agent starves the k3s control
  plane that lives on the same box, so the failure mode is the whole cluster
  going unresponsive rather than one workload dying.
- **Operational effort is inverted against the stated preference.** OS patching,
  kernel, k3s upgrades, certificate renewal, firewall, monitoring and backups are
  all now yours, in the nine weeks where the product is what needs building.

### Pre-Mortem — How This Could Fail

Written from 2026-10-22, in the failure case.

Weeks one and two went to the box: operating system, k3s, firewall,
cert-manager, Tekton, Prometheus, and moving Gitea in from its old home. It all
worked, and it felt like progress because it was visible.

Week five was the first parallel-agent test. Three agents, each running a nested
virtual machine, exhausted RAM. The kubelet began evicting, and because the k3s
control plane lives on the same machine, the cluster itself became unresponsive
rather than merely shedding a workload. You added memory limits, which converted
the failure from "cluster dies" into "agents fail mid-work" — better, but now
FR-230's budget bound was not what stopped an agent; the memory limit was.

Week seven, a disk reported errors. Hetzner replaced it at auction-tier priority,
which took three days you had not budgeted, and the rebuild took another.

You arrived at the conference with a system that worked when one agent ran.
FR-050 — parallel agents, must-have — was described rather than demonstrated. The
loop ran, the story held together, and the single most impressive thing about the
design was the part you had to say "yes, it supports that" about instead of
showing it.

### Unknown Unknowns

- **k3s makes two decisions for you at install.** Traefik as ingress and
  local-path-provisioner as storage are both bundled and both on by default.
  Neither is wrong; both are choices you did not make and will inherit.
- **Auction listings differ in ways that matter after purchase.** RAID
  configuration, disk type and ECC support vary per listing, and `installimage`
  defaults are not uniform across them. Whether you have software RAID across two
  disks or a single unprotected disk is a fact about your specific machine.
  *Resolved 2026-08-19 by inspection — see § Delivered hardware: software RAID1
  across two NVMe disks (good), and no ECC (a new risk, registered below).*
- **Virtink's documented cert-manager range is v1.0 to v1.8.** A current
  cert-manager install is well past that ceiling. This surfaces at install time,
  not before.
- **Installing "Tekton" via its operator does not get you current Tekton.** The
  operator's LTS track (v0.78.x) delivers Pipeline v1.6.x with a minimum
  Kubernetes of 1.28, while the current release is v1.13.0 (2026-05-29). The two
  tracks have different API fields; choosing accidentally is easy.
- **Self-hosting is better than managed on exactly one axis here: version
  currency.** Kubebuilder v4.15.0 targets Kubernetes 1.36 and Go 1.26, and
  managed providers typically trail upstream by a minor or two. On k3s you pick.
- **One public IPv4 and typically a /64 IPv6** means Gitea, Tekton, the GUI and
  the metrics surface all route by hostname through one ingress, with one
  certificate story that has to be right before anything is demonstrable
  remotely.

**Decision:** continue with the imposed platform — a Hetzner server-auction
dedicated machine running k3s, ordered 2026-08-18, superseding the interview's
"new managed Kubernetes" answer. DigitalOcean DOKS is retained as runner-up and
as the documented fallback if hardware or contention forces a move.

## Operational Story

- **Preview deploys.** There are none per pull request. Tekton PipelineRuns are
  triggered from git and run in-cluster against the same machine. Access
  protection is therefore not per-preview but perimeter: the k3s API server on
  port 6443 is restricted to known addresses at the host firewall, and every
  HTTP-facing component sits behind hostname-routed ingress with TLS.
- **Secrets.** Kubernetes Secrets, in-cluster. Readable by anything holding RBAC
  `get` in the namespace, and by anyone with root on the box — which, on a
  single-node self-administered cluster, is the same person. Rotation is manual:
  replace the Secret and restart its consumers. k3s keeps them in its datastore
  on local disk; encryption at rest is off unless explicitly enabled at install.
- **Rollback.** `kubectl rollout undo deployment/henia-operator -n henia-system`
  — seconds. Data caveat: this rolls back the Deployment only. It does not undo
  a CRD schema change, and after a CRD version bump previously stored custom
  resources may fail to deserialize, so a CRD change needs a forward fix rather
  than a rollback.
- **Human versus agent.** The agent may read cluster state (FR-085), tail logs,
  open pull requests, and commit pipeline configuration to git. A human only:
  provisioning the machine, installing and upgrading k3s, firewall changes,
  writing secrets, CRD version bumps, and any `kubectl apply` made directly
  against the cluster instead of through git.
- **Read-only log tailing.** A ServiceAccount bound to a Role granting `get`,
  `list` and `watch` on `pods` plus `get` on `pods/log`, with no write verb
  anywhere, used via `kubectl logs -f`. This is the concrete form of FR-085's
  read-only platform access.

## Risk Register

| Risk | Source | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- | --- |
| Resource contention takes down the control plane, because agents and k3s share one machine | pre-mortem | High | High | Set memory limits and reservations before the first parallel-agent test, not after; reserve headroom for the control plane; treat FR-280's concurrency limit as a resource decision, not only a cost one |
| Refurbished disk or component fails inside the nine weeks | devil's advocate | Medium | **Medium** (was High) | RAID configuration confirmed 2026-08-19 — RAID1 across both NVMes, so a single disk failure degrades rather than destroys. Still: back up the k3s datastore off-box daily, and know that auction support is lower priority, so budget days rather than hours for a replacement |
| Memory is non-ECC, so bit flips corrupt silently rather than being caught | delivered hardware, 2026-08-19 | Low | High | Accept — it cannot be fixed on this machine. Weigh it when sizing agent concurrency, because this box's dominant risk is already memory pressure; corruption in the k3s datastore is the expensive case, which is another reason for off-box datastore backups that are verified rather than assumed |
| No host firewall exists, while the perimeter is the whole access-protection model | delivered hardware, 2026-08-19 | High | High | Harmless today — sshd is the only listener and 6443 is unbound — and dangerous the moment k3s starts. Put the ruleset in place as part of F-01, before the API server first listens, not after |
| Agent workspaces exhaust the root filesystem and take the control plane with them | delivered hardware, 2026-08-19 | Medium | High | k3s local-path-provisioner does **not** enforce PVC capacity — it is a directory on `/`, the same filesystem as the k3s datastore, so this is the top contention risk arriving by disk instead of RAM. Set an ext4 project quota on the local-path directory when k3s is installed, and alert on root usage. 857 GB free today makes this cheap to defer but easy to forget |
| Single point of failure — no HA, nowhere to reschedule | devil's advocate | Medium | High | Keep DOKS as a tested fallback rather than a theoretical one; rehearse the demo from a second environment at least once |
| Operational effort displaces product work against a fixed date | devil's advocate | High | Medium | Timebox cluster setup explicitly; anything not needed for the eight-step loop is post-conference |
| Virtink's cert-manager ceiling (v1.0–v1.8) conflicts with a current install | unknown unknowns | Medium | Medium | Check the supported range before installing cert-manager, not after; pin deliberately |
| Wrong Tekton track installed — operator LTS (Pipeline v1.6.x) instead of current v1.13.0 | unknown unknowns | Medium | Medium | Choose the track explicitly and record which; verify the API fields you depend on exist in that track |
| Agent workspaces on node-local storage | devil's advocate | Medium | **Low** (was Medium) | "Unprotected" turned out to be wrong: the storage is RAID1-mirrored (verified 2026-08-19), so this is now about durability of the *contents*, not the disk. Treat workspaces as disposable — FR-240 already requires stopping into a recoverable state, and FR-330 allows removal; do not let anything durable accumulate there. The live concern moved to the disk-exhaustion row above |
| Client-go ahead of the API server if k3s is pinned below Kubernetes 1.36 | research | Low | Medium | Pin k3s to a version at or near what kubebuilder v4.15.0 targets |
| One public address serving Gitea, Tekton, GUI and metrics | unknown unknowns | Medium | Low | Get hostname-routed ingress and certificates working before anything needs demonstrating remotely |

## Getting Started

Verified against the concrete versions in the stack, checked 2026-08-18.

- **kubebuilder v4.15.0**, released 2026-06-15: targets Kubernetes 1.36, Go
  1.26, and scaffolds controller-runtime v0.24.1.
- Scaffold into an empty subdirectory and move the contents up — this matches the
  `subdir-then-move` strategy recorded in the tech-stack hand-off, and is
  necessary because the repository root already holds `context/`, `.claude/` and
  `3rd_party/`.
- `kubebuilder init --domain <domain> --repo <go module path>`
- `kubebuilder create api --group henia --version v1alpha1 --kind <Kind>` — the
  scaffold is two steps, not one, which is why the hand-off records confidence as
  `expected` rather than `verified`.
- Pin k3s to a Kubernetes version at or near 1.36 so the scaffolded client-go is
  not ahead of the API server. Self-hosting is the one place you control this.
- Install cert-manager before Virtink, checking the supported version range
  first.
- Choose the Tekton release track deliberately: current v1.13.0 (2026-05-29), or
  the operator's LTS track (Pipeline v1.6.x, minimum Kubernetes 1.28).

## Out of Scope

This document does not build container images, does not configure CI pipelines,
and does not plan beyond the first production release. Also deliberately absent:

- **The adopter reference environment.** Scoped out at the start — this covers
  the project's own cluster only. What a recommended adopter deployment looks
  like is a separate decision, and one the adopter disclosure (FR-185) will
  eventually need.
- **Target-scale architecture.** High availability, multi-node scheduling and
  anything about running Henia beyond one machine are later, separate decisions.
- **Backup and disaster recovery design.** Named in the risk register as a
  mitigation; not designed here.
