# Devserver Setup — Cluster Substrate Implementation Plan

## Overview

Turn `tachiko.kondi.net` (88.99.160.8) from a bare Ubuntu 26.04 machine into the
secured, single-node k3s cluster that Henia's own development runs on. This is
roadmap item **F-01 `cluster-substrate`**, scoped to the substrate: the cluster,
its perimeter, its storage boundary, a read-only identity to read it back, a
telemetry collector, and a recorded supervision convention.

The Henia operator itself is **not** built or deployed here. That is a deliberate
scope decision (see *What We're NOT Doing*), and it means F-01's outcome
statement — "the framework runs in a cluster" — is only partially satisfied when
this change closes. What this change delivers is everything the framework needs
to exist *in*, ready for the operator to arrive.

## Current State Analysis

Probed directly on 2026-08-19, not recalled.

**The machine.** Ubuntu 26.04 LTS, kernel 7.0.0-22, Intel i7-8700 (12 threads),
62 GiB non-ECC DDR4, 2 × 954 GB NVMe in mdraid RAID1 (`md0` swap, `md1` `/boot`,
`md2` `/`), all arrays clean. `/` is 905 GB with 857 GB free. Both disks are
fully partitioned with no unallocated space and no LVM.

**What runs on it: nothing.** No container runtime, no k3s, no application code.
`sshd` is the only externally listening service; `systemd-resolved` and `chrony`
are on loopback. Zero failed units, no pending updates.

**Virtualisation is available.** `/dev/kvm` present, `vmx` flag, `kvm_intel`
loaded, nested virtualisation enabled — the capability that selected bare metal
over managed Kubernetes holds on the delivered hardware.

**No firewall exists.** No ufw, no nftables ruleset, `nftables.service` disabled
and inactive. `nft` and `iptables` binaries are present.

**Root filesystem quota is already enabled** (done during planning on
2026-08-19, in the rescue window): `/dev/md2` now carries the `quota` and
`project` ext4 features, `/etc/fstab` mounts `/` with `prjquota`, and the mount
is live. A backup of the original fstab sits at `/etc/fstab.bak-prjquota`.
`/var/lib/rancher/k3s/storage` is pre-created. Quota *tooling* is not installed
and no project limit is set yet.

**A second, separate cluster already exists** and is unrelated to this machine:
k3s **v1.25.5+k3s2** (build date 2023-01-11) reachable at `10.242.0.10:6443`
over a private network. It hosts ~30 namespaces including `gitea`, `argocd`,
`tekton`, `cert-manager`, `harbor`, `velero` and `metallb`, plus ~20 unrelated
applications. Its ingress controller is HAProxy
(`haproxy.org/ingress-controller/haproxy`, image
`haproxytech/kubernetes-ingress:1.9.0` in namespace `haproxy`) and its default
StorageClass is `local-path`. This cluster is **not** in scope; it matters only
because Gitea lives there and Henia must reach it.

**The devcontainer harness already assumes a cluster.**
`devcontainer/kubeconfig.yaml` points at `https://10.242.0.10:6443`;
`devcontainer/run.sh` derives a firewall exception from that `server:` value and
additionally hardcodes `88.99.160.8:6443`. `devcontainer/k8s/rbac.yaml` defines
a working read-only identity bound to `view`, plus explicit cluster-scoped
grants — but it was written against the *existing* cluster, so it grants Argo CD
resources that will not exist on tachiko.

The devcontainer egresses from **46.205.216.245**, inside `46.205.216.0/21`,
announced by **AS12912 (T-Mobile Polska)**. That AS announces 47 IPv4 prefixes
covering ~1,355,520 addresses.

## Desired End State

A single-node k3s cluster on tachiko, pinned to the Kubernetes minor that the
project's scaffold targets, reachable only through a deliberate perimeter, with
agent-workspace storage that cannot consume the whole disk, a read-only identity
the devcontainer uses to read cluster state back, a running metrics collector,
and a written statement of what supervises what.

### Key Discoveries:

- **k3s `v1.36.3+k3s1` exists** (released 2026-08-04) and matches kubebuilder
  v4.15.0's Kubernetes 1.36 target exactly. The "client-go ahead of the API
  server" risk in `infrastructure.md` costs nothing to avoid — it is a version
  string, not a trade-off.
- **ext4 project quota required an offline filesystem change.** Root had neither
  the `project` nor the `quota` feature, and ext4 cannot add `project` to a
  mounted filesystem. This forced a Hetzner rescue boot, already performed.
  Inode size is 256, which is the precondition project quota needs.
- **The existing cluster's ingress is HAProxy, not Traefik.** Matching it means
  disabling the k3s-bundled Traefik at install time rather than removing it
  afterwards.
- **`local-path` is already the default StorageClass on the existing cluster**,
  so the storage decision recorded in `infrastructure.md` needs no divergence.
- **k3s auto-deploys manifests** from `/var/lib/rancher/k3s/server/manifests`,
  including `HelmChart` custom resources. Ingress and Prometheus can be
  installed declaratively with no Helm binary on the host.
- **`nodes` is forbidden to the `view` ClusterRole**, which is why the existing
  rbac.yaml adds explicit cluster-scoped grants. The same pattern is needed here.

## What We're NOT Doing

- **Not scaffolding or deploying the Henia operator.** No `kubebuilder init`, no
  Go module, no image build. F-01's "the framework runs in a cluster" therefore
  does not fully close in this change.
- **Not migrating Gitea.** It stays on the existing cluster; Henia reaches it
  over the network.
- **Not touching the existing 10.242.0.10 cluster** beyond reading it.
- **Not installing cert-manager, Tekton, Virtink or Harbor.** Later changes.
- **Not setting up off-box backups** of the k3s datastore. Named in the
  infrastructure risk register; explicitly deselected for this change.
- **Not hardening SSH or rotating the SSH key.** Explicitly deselected.
- **Not introducing LVM or reinstalling the machine.** Recorded as closed in
  `infrastructure.md`.
- **Not building a VPN.** The 6443 perimeter is a firewall allowlist.
- **Not narrowing the 6443 allowlist to a single prefix** — see the debt slice
  in *Migration Notes*.

## Implementation Approach

Work outward from the host to the cluster, so that each layer is verifiable
before the next depends on it. Two orderings are forced rather than chosen:

1. **The filesystem quota came first**, because ext4 cannot enable `project` on
   a mounted root. It is done.
2. **The firewall lands before k3s**, because a k3s install opens 6443
   immediately. Installing first and firewalling second means an unprotected API
   server on a public address for however long the gap lasts.

Everything in-cluster is delivered as declarative manifests dropped into k3s's
auto-deploy directory, so the cluster's contents are reproducible from files
rather than from a sequence of typed commands.

## Critical Implementation Details

- **Do not lock yourself out.** The nftables ruleset must be loaded in a way that
  survives a mistake — load it, verify the existing SSH session still responds,
  and only then `systemctl enable nftables`. SSH stays open to the world by
  decision, which also makes it the recovery path if the 6443 rules are wrong.
- **The AS12912 prefix set rots.** 47 prefixes announced today; BGP announcements
  change. The refresh script is part of the deliverable, not an afterthought.
- **`--disable=traefik` must be passed at install time.** Removing Traefik after
  the fact leaves its HelmChart resource behind, which k3s will reconcile back.
- **k3s writes its kubeconfig with the server address `127.0.0.1`.** The
  devcontainer's copy must be rewritten to the public address, or it will point
  at the wrong host.
- **The `view` ClusterRole cannot read cluster-scoped resources.** StorageClass
  and IngressClass need explicit grants, exactly as the existing rbac.yaml does.
- **Project quota is enforced by directory inheritance.** The project ID must be
  set on `/var/lib/rancher/k3s/storage` with the inherit flag, so PVC
  subdirectories created later by local-path inherit it automatically.

## Phase 1: Root filesystem quota enablement

### Overview

Give agent-workspace storage a hard capacity boundary, so a runaway workspace
cannot fill `/` and stall the k3s datastore that shares it. The offline half is
already complete; this phase finishes the tooling and applies a limit.

### Changes Required:

#### 1. `/dev/md2` ext4 features — COMPLETE (2026-08-19)

Intent: make project quota possible at all. Contract: the filesystem carries the
`quota` and `project` features; inode size 256. Performed in the Hetzner rescue
system with `e2fsck -fp` before and after; the filesystem verified clean.

#### 2. `/etc/fstab` — COMPLETE (2026-08-19)

Intent: mount root with project quota accounting active. Contract: the `/` entry
reads `defaults,prjquota`. Original preserved at `/etc/fstab.bak-prjquota`.
Verified live after reboot: `findmnt -no OPTIONS /` reports `prjquota`.

#### 3. Quota tooling

Intent: provide the userspace commands that set and report quotas. Contract: the
`quota` package is installed, providing `repquota` and `setquota`.

#### 4. Project quota on `/var/lib/rancher/k3s/storage`

Intent: cap what local-path-provisioner can consume. Contract: project ID `1000`
assigned to the directory with the inherit flag set, and a block limit of
**200 GiB**. The value is a starting point, not a constraint discovered from
measurement — it is ~23% of the disk and leaves the datastore ample room.

### Success Criteria:

#### Automated Verification:

- `findmnt -no OPTIONS /` contains `prjquota`
- `tune2fs -l /dev/md2` lists both `quota` and `project` features
- `repquota -P /` reports project 1000 with a 200 GiB block limit
- Writing past the limit inside the directory fails with a quota error rather
  than filling the disk

#### Manual Verification:

- The machine boots unattended with the new fstab (already exercised once)

## Phase 2: Host firewall

### Overview

Establish the perimeter that `infrastructure.md` names as the whole
access-protection model, before anything is listening behind it.

### Changes Required:

#### 1. `/etc/nftables.conf`

Intent: default-deny inbound with deliberate exceptions. Contract: an `inet
filter` table with `input` policy `drop`; accept loopback, established/related,
and ICMP/ICMPv6; accept `tcp dport 22` from any source; accept `tcp dport 6443`
only from the AS12912 address set.

#### 2. AS12912 prefix set

Intent: express the 6443 allowlist as data rather than inline rules. Contract: a
named nftables set of IPv4 prefixes, populated from AS12912's announced
prefixes.

#### 3. Prefix refresh script

Intent: keep the set from silently rotting as BGP announcements change.
Contract: a script that regenerates the set from a public routing data source and
reloads it, plus a scheduled invocation.

#### 4. `nftables.service`

Intent: make the ruleset survive reboot. Contract: enabled and active.

### Success Criteria:

#### Automated Verification:

- `nft list ruleset` shows input policy `drop` with the four accept rules
- `systemctl is-enabled nftables` reports `enabled`
- The AS12912 set is non-empty and contains `46.205.216.0/21`
- Port 22 is reachable from the devcontainer
- The refresh script runs and produces a set of the expected shape

#### Manual Verification:

- An existing SSH session survives loading the ruleset
- A fresh SSH connection succeeds after `systemctl enable --now nftables`

## Phase 3: k3s install, pinned

### Overview

Install the cluster itself, pinned to the Kubernetes minor the project's scaffold
targets, with the bundled ingress disabled and bundled storage kept.

### Changes Required:

#### 1. k3s server install

Intent: a single-node cluster at a known version. Contract: k3s
`v1.36.3+k3s1`, installed with `--disable=traefik`; local-path-provisioner
retained as the default StorageClass; the API server listening on 6443.

#### 2. Devcontainer-facing kubeconfig address

Intent: make the generated kubeconfig usable from outside the host. Contract: the
`server:` value is `https://88.99.160.8:6443`, not `127.0.0.1`.

#### 3. Egress verification to Gitea

Intent: confirm the cross-cluster dependency the Gitea decision creates.
Contract: a pod on tachiko can reach `git.tobiko.kondi.net` over HTTPS.

### Success Criteria:

#### Automated Verification:

- `/version` on the API server reports `v1.36.3+k3s1`
- The single node reports `Ready`
- `local-path` exists and is the default StorageClass
- No Traefik deployment, service or HelmChart exists
- A pod resolves and reaches `git.tobiko.kondi.net` over HTTPS

#### Manual Verification:

- The API server is reachable from the devcontainer through the firewall, and
  refused from an address outside AS12912

## Phase 4: HAProxy ingress

### Overview

Provide the single hostname-routed entry point the infrastructure document
describes, using the same controller as the existing cluster so the two
environments do not diverge.

### Changes Required:

#### 1. HAProxy ingress HelmChart manifest

Intent: install the controller declaratively via k3s auto-deploy. Contract: a
`HelmChart` resource in `/var/lib/rancher/k3s/server/manifests` installing
haproxytech's kubernetes-ingress at the version matching the existing cluster
(`1.9.0`), in its own namespace.

#### 2. Default IngressClass

Intent: make Ingress resources work without per-object class annotations.
Contract: an IngressClass named `haproxy` carrying
`ingressclass.kubernetes.io/is-default-class: "true"`.

#### 3. Routing smoke test

Intent: prove the path end to end. Contract: a throwaway Deployment, Service and
Ingress that returns a known response body by hostname, removed afterwards.

### Success Criteria:

#### Automated Verification:

- The controller pods reach `Ready`
- IngressClass `haproxy` exists and is marked default
- A test Ingress returns HTTP 200 with the expected body via the controller

#### Manual Verification:

- Hostname-based routing resolves from outside the host

## Phase 5: Read-only cluster identity (FR-085)

### Overview

Give the devcontainer an identity that can read everything the cluster has
reconciled and change none of it — the concrete form of FR-085 and, per the
infrastructure document, the central claim of the conference talk.

### Changes Required:

#### 1. `devcontainer/k8s/rbac.yaml` — tachiko variant

Intent: reuse the working identity without carrying grants for components that
do not exist here. Contract: Namespace, ServiceAccount and a binding to the
built-in `view` ClusterRole; plus one explicit cluster-scoped ClusterRole
granting `get`/`list`/`watch` on `storageclasses` and `ingressclasses`. The Argo
CD grants are dropped — Argo CD is not installed on this cluster. No verb
outside `get`/`list`/`watch` appears anywhere in the file.

#### 2. `devcontainer/kubeconfig.yaml`

Intent: point the harness at the new cluster. Contract: regenerated by
`devcontainer/k8s/generate-kubeconfig.sh` against tachiko, with `server:` set to
`https://88.99.160.8:6443`. `run.sh` derives its firewall exception from this
value, so no change to `run.sh` is required.

#### 3. Negative-permission verification

Intent: prove read-only is actually read-only rather than assumed. Contract:
write attempts and Secret content reads are denied.

### Success Criteria:

#### Automated Verification:

- The identity can list pods across all namespaces
- Creating and deleting a resource are both denied with 403
- Reading a Secret's contents is denied
- StorageClasses and IngressClasses are readable
- `kubectl` from the devcontainer, using the regenerated kubeconfig, reaches the
  cluster

#### Manual Verification:

- A devcontainer restart picks up the new kubeconfig and its firewall exception
  without manual intervention

## Phase 6: Telemetry collector (FR-270)

### Overview

Stand up the external collector that FR-270's published telemetry is meant to be
read by. Nothing Henia-specific is emitted yet — this phase makes the collector
exist and prove it scrapes.

### Changes Required:

#### 1. Prometheus HelmChart manifest

Intent: declarative install via k3s auto-deploy. Contract: a `HelmChart`
resource installing Prometheus into a monitoring namespace, with persistence
backed by the `local-path` StorageClass.

#### 2. k3s component scraping

Intent: give the collector something real to read from day one. Contract: scrape
configuration covering the kubelet and API server.

#### 3. Ingress exposure

Intent: make the collector reachable for inspection. Contract: an Ingress on the
HAProxy class routing a hostname to the Prometheus service.

### Success Criteria:

#### Automated Verification:

- Prometheus pods reach `Ready`
- `/-/healthy` returns HTTP 200
- Targets for kubelet and API server report `up`
- The Prometheus PVC is bound on `local-path`

#### Manual Verification:

- The Prometheus UI is reachable by hostname through the ingress

## Phase 7: Supervision convention (FR-470)

### Overview

Record what supervises Henia instances, and demonstrate it. FR-470's own Socratic
resolution already answers this — the platform is the supervising layer — so this
phase writes that down and verifies the behaviour rather than building anything.

### Changes Required:

#### 1. Supervision convention document

Intent: make the answer explicit rather than implied. Contract: a document
stating that k3s is the supervising layer; that an instance is healthy when all
its components are running (a liveness definition, not a progress definition);
that instances are delivered as Deployments with liveness and readiness probes;
and that agent-level restarts remain inside the instance's own main loop, per
FR-240.

#### 2. Supervision demonstration

Intent: verify the convention holds on this cluster. Contract: a throwaway
Deployment whose pod is deleted and observed to be replaced automatically;
removed afterwards.

### Success Criteria:

#### Automated Verification:

- A deleted pod belonging to a Deployment is replaced and reaches `Running`
- A container failing its liveness probe is restarted

#### Manual Verification:

- The convention document is reviewed and agreed as the answer to FR-470

## Testing Strategy

There is no application code in this change, so testing is verification of
system state rather than unit or integration tests. Three kinds appear:

- **Assertion on live state** — querying the API server, `nft list ruleset`,
  `repquota`, `findmnt`. These are the bulk of the automated criteria and are
  re-runnable at any time.
- **Negative testing** — the read-only identity is only proven by the operations
  that are *denied*. Phase 5 asserts 403s deliberately; a phase that only proves
  reads work has not tested FR-085.
- **Destructive smoke tests, cleaned up** — the ingress route and the supervision
  demonstration create throwaway objects and remove them. Nothing from a smoke
  test is left running.

The quota limit is verified by exceeding it on purpose. A quota that has never
refused a write has not been shown to work.

## Performance Considerations

The dominant risk on this machine is resource contention, not throughput: agents
and the k3s control plane share one box, and the infrastructure risk register
rates that High/High. This change contributes two mitigations — the project quota
bounds disk, and Prometheus makes pressure visible before it becomes an outage —
and deliberately defers memory limits and reservations to the change that
actually runs agents.

Two smaller notes: project quota accounting on ext4 is effectively free at this
scale, and Prometheus with local-path persistence writes to the same spindles as
everything else, so its retention should stay modest until the storage picture is
revisited.

## Migration Notes

Nothing is being migrated. Two forward-looking obligations are created:

**Debt slice — narrow the 6443 allowlist.** This change ships the wide rule (all
of AS12912, ~1.36M addresses) so that a T-Mobile reassignment cannot lock the
operator out. The narrowing to `46.205.216.0/21`, or to a VPN-based perimeter, is
recorded as its own item at the moment the corner is cut, per the debt-as-slices
practice in the shape-notes forward block. It is written up as **D-01
`narrow-cluster-api-allowlist`** in `context/foundation/roadmap.md` (§ Debt),
opened on 2026-08-19 — not deferred to after the conference.

**The devcontainer will point at a different cluster.** Once Phase 5 lands,
`devcontainer/kubeconfig.yaml` targets tachiko rather than `10.242.0.10`. Any
workflow that assumed the harness could read the Gitea cluster's state loses that
access, and the hardcoded `88.99.160.8:6443` entry in `run.sh` becomes the one
that matters.

## References

- `context/foundation/infrastructure.md` — platform decision, delivered-hardware
  findings, risk register
- `context/foundation/roadmap.md` — F-01 `cluster-substrate`, its unknowns and
  blockers
- `context/foundation/prd.md` — FR-085, FR-270, FR-470
- `context/foundation/tech-stack.md` — kubebuilder v4.15.0, Kubernetes 1.36
- `devcontainer/k8s/rbac.yaml` — the existing read-only identity this phase 5
  adapts
- `devcontainer/k8s/generate-kubeconfig.sh` — credential issuance for that
  identity
- `devcontainer/run.sh` — firewall exception derived from `kubeconfig.yaml`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Root filesystem quota enablement

#### Automated

- [x] 1.1 `findmnt -no OPTIONS /` contains `prjquota` — d44385d
- [x] 1.2 `tune2fs -l /dev/md2` lists both `quota` and `project` features — d44385d
- [x] 1.3 `repquota -P /` reports project 1000 with a 200 GiB block limit — d44385d
- [x] 1.4 Writing past the limit fails with a quota error rather than filling the disk — d44385d

#### Manual

- [x] 1.5 The machine boots unattended with the new fstab — d44385d

### Phase 2: Host firewall

#### Automated

- [x] 2.1 `nft list ruleset` shows input policy `drop` with the four accept rules — 3a73e54
- [x] 2.2 `systemctl is-enabled nftables` reports `enabled` — 3a73e54
- [x] 2.3 The AS12912 set is non-empty and contains `46.205.216.0/21` — 3a73e54
- [x] 2.4 Port 22 is reachable from the devcontainer — 3a73e54
- [x] 2.5 The refresh script runs and produces a set of the expected shape — 3a73e54

#### Manual

- [x] 2.6 An existing SSH session survives loading the ruleset — 3a73e54
- [x] 2.7 A fresh SSH connection succeeds after `systemctl enable --now nftables` — 3a73e54

### Phase 3: k3s install, pinned

#### Automated

- [x] 3.1 `/version` on the API server reports `v1.36.3+k3s1` — 7696c9b
- [x] 3.2 The single node reports `Ready` — 7696c9b
- [x] 3.3 `local-path` exists and is the default StorageClass — 7696c9b
- [x] 3.4 No Traefik deployment, service or HelmChart exists — 7696c9b
- [x] 3.5 A pod resolves and reaches `git.tobiko.kondi.net` over HTTPS — 7696c9b

#### Manual

- [x] 3.6 The API server is reachable from the devcontainer and refused from outside AS12912 — 7696c9b

### Phase 4: HAProxy ingress

#### Automated

- [x] 4.1 The controller pods reach `Ready`
- [x] 4.2 IngressClass `haproxy` exists and is marked default
- [x] 4.3 A test Ingress returns HTTP 200 with the expected body

#### Manual

- [x] 4.4 Hostname-based routing resolves from outside the host

### Phase 5: Read-only cluster identity (FR-085)

#### Automated

- [ ] 5.1 The identity can list pods across all namespaces
- [ ] 5.2 Creating and deleting a resource are both denied with 403
- [ ] 5.3 Reading a Secret's contents is denied
- [ ] 5.4 StorageClasses and IngressClasses are readable
- [ ] 5.5 `kubectl` from the devcontainer reaches the cluster with the regenerated kubeconfig

#### Manual

- [ ] 5.6 A devcontainer restart picks up the new kubeconfig and its firewall exception

### Phase 6: Telemetry collector (FR-270)

#### Automated

- [ ] 6.1 Prometheus pods reach `Ready`
- [ ] 6.2 `/-/healthy` returns HTTP 200
- [ ] 6.3 Targets for kubelet and API server report `up`
- [ ] 6.4 The Prometheus PVC is bound on `local-path`

#### Manual

- [ ] 6.5 The Prometheus UI is reachable by hostname through the ingress

### Phase 7: Supervision convention (FR-470)

#### Automated

- [ ] 7.1 A deleted pod belonging to a Deployment is replaced and reaches `Running`
- [ ] 7.2 A container failing its liveness probe is restarted

#### Manual

- [ ] 7.3 The convention document is reviewed and agreed as the answer to FR-470
