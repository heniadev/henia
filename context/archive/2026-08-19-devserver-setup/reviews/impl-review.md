<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Devserver Setup — Cluster Substrate Implementation Plan

- **Plan**: `context/changes/devserver-setup/plan.md`
- **Scope**: whole plan — all 7 phases, 36/36 Progress items checked
- **Date**: 2026-08-19
- **Diff basis**: Progress SHAs (`3e6f331..36b169f`, plus `ca4878c`; closing commit `34c2ceb`). All 36 items carry commit ids, so the primary anchor applied — no fallback needed.
- **Verdict**: REWORK REQUIRED
- **Findings**: 2 critical, 3 warnings, 3 observations (F8 added during triage, after the initial save)

> Harness note: this skill specifies two parallel read-only subagents for drift and safety scanning. This session operates under a standing instruction not to spawn subagents unless explicitly requested, so both passes were performed inline. The changed set is 8 files plus host state, well inside what one context holds, so the context-discipline rationale for delegation does not bind here. Recorded because it is a deviation from the harness, not from the criteria.

## Verdicts

| Dimension | Verdict |
| --- | --- |
| Plan Adherence | WARNING |
| Scope Discipline | PASS |
| Safety & Quality | FAIL |
| Architecture | WARNING |
| Pattern Consistency | WARNING |
| Success Criteria | WARNING |

## Findings

### F1 — Prometheus is readable by anyone on the internet, without authentication

- **Severity**: 🔴 CRITICAL
- **Impact**: 🧠 HIGH
- **Dimension**: Safety & Quality
- **Location**: `plan.md` phase 6 change 3 (Ingress exposure); host `/var/lib/rancher/k3s/server/manifests/prometheus.yaml`; nftables rule `tcp dport { 80, 443 } accept`
- **Detail**: The Prometheus Ingress carries no TLS block and no authentication annotation, and port 80 accepts from any source. Verified anonymously from off-box: `GET /api/v1/label/__name__/values` returns **1538 metric names**, and `kube_secret_info` returns **7 series naming Secrets and their namespaces** — including `kube-system/k3s-serving`. Contents are not exposed, but names, namespaces, full pod/node inventory, resource usage and cluster topology are.

  The asymmetry is what makes this severe rather than merely untidy: phase 5 built an identity that is *denied* Secret reads (criterion 5.3, verified 403), while phase 6 published Secret names to the open internet with no credential at all. The perimeter model in `infrastructure.md` states that every HTTP-facing component sits behind hostname-routed ingress **with TLS**; that condition is unmet.

  This is partly a flaw in the plan, not only in the execution. Phase 6's contract says "make the collector reachable for inspection" and never asks who may inspect. `cert-manager` is a declared exclusion, which neutralises the TLS half — it does not neutralise the missing-authentication half.
- **Fix A ⭐ Recommended** — restrict at the perimeter, matching the pattern the plan already uses for 6443
  - **Approach**: add an nftables source restriction for 80/443 to the AS12912 set (or a narrower prefix), leaving the ingress itself unchanged.
  - **Strength**: reuses a mechanism already built, tested and running in this change; no new components, no chart values, no cert-manager dependency. One rule edit, immediately verifiable with the same off-box curl used to find this.
  - **Tradeoff**: blocks all public HTTP, so anything later intended to be genuinely public (a Henia GUI, a demo at the conference) will need its own carve-out. Given the conference on 2026-10-22, that carve-out will be needed.
  - **Confidence**: high. The mechanism is proven on this host — 6443 already refuses from outside AS12912, confirmed by the operator from two vantage points.
  - **Blind spot**: not verified whether HAProxy's own health or metrics endpoints bind separately and would survive the restriction; not verified what the conference demo needs to expose publicly.
- **Fix B** — add authentication in front of Prometheus
  - **Approach**: basic-auth or forward-auth annotation on the Ingress, credentials in a Secret.
  - **Strength**: keeps the endpoint reachable from anywhere, which survives a change of operator location; closer to how this will need to work once more components are exposed.
  - **Tradeoff**: introduces a credential to manage and rotate, over plain HTTP until cert-manager exists — so the credential itself travels in the clear. That is a worse posture than Fix A until TLS lands.
  - **Confidence**: medium. The HAProxy chart supports auth annotations, but the exact annotation set for controller 3.2.13 was not verified on this cluster.
  - **Blind spot**: no check of whether basic-auth interferes with Prometheus's own API clients later (the FR-270 collector contract assumes something scrapes it).
- **Decision**: NOT FIXED (2026-08-19) — reopened after the operator tested from outside AS12912 and got `HTTP/1.1 200 OK` from `10.242.0.10`. Prometheus remains world-readable. Three things were established while attempting the fix, and they constrain any future attempt:

  1. **Fix A as written cannot work.** k3s DNATs 80/443 to the ingress pod at PREROUTING (`KUBE-SERVICES -d 88.99.160.8/32 --dport 80 -j KUBE-EXT-…`). Those packets are then *forwarded*, never traversing the `input` chain, so an `input` rule can gate 6443 (a host-local listener, which is why that restriction genuinely works) but can never gate the ingress. The rule was verified as correct text sitting in a chain the traffic does not use.
  2. **A `prerouting` filter chain at `mangle` priority does work** — it runs after conntrack and before dstnat, so it still sees the true external port. Verified: added incrementally, in-AS access preserved at 200, and a temporary self-block rule did sever the connection, proving the drop path functions.
  3. **But persisting it through `/etc/nftables.conf` is hazardous.** That file opens with `flush ruleset`, which flushes *every table in every family* — including the `iptables-nft` KUBE-* NAT tables. Every reload therefore destroys k3s's service NAT. kube-proxy did **not** resync on its own; `KUBE-EXT` sat at 0 and the ingress stayed down until `systemctl restart k3s` rebuilt it. This caused a real outage during the review session, recorded as **F8** below.

  Consequence for the fix choice: a durable answer should live where firewall reloads cannot reach it — a HAProxy ingress allowlist annotation, or authentication in front of Prometheus (the report's original Fix B) — rather than in nftables. Pending the operator's decision.

  **FIXED (2026-08-19), via Fix B — basic auth.** The operator chose authentication over an address restriction, which also survives their carrier-assigned egress changing. Implemented as `haproxy.org/auth-type: basic-auth` + `haproxy.org/auth-secret: monitoring/prometheus-basic-auth` on the Prometheus Ingress, set through the chart's `server.ingress.annotations` so it lives in the tracked manifest. Enforced by the ingress controller, so it is immune to both the DNAT path and the flush-ruleset hazard that defeated the two nftables attempts.

  First attempt stored a plaintext password and failed closed — 401 for everyone, including valid credentials. The controller expects a crypt hash; the Secret now holds a SHA-512 crypt (`openssl passwd -6`). The plaintext lives only in `/root/prometheus-basic-auth.txt` (mode 0600) on the host and was never printed into the session transcript.

  Verified from the devcontainer over the public path — all three endpoints that previously leaked now refuse anonymously: `/-/healthy` 401, `/api/v1/query?query=kube_secret_info` 401, `/api/v1/label/__name__/values` 401. Verified on-box with credentials: 200, and a live query returns data.

  **Residual risk, deliberately accepted**: there is no TLS (cert-manager is a declared exclusion of this change), so the credential travels in clear text over HTTP. That is a weaker posture than an address restriction would have been, and it is the tradeoff the report named under Fix B. It should be revisited when cert-manager lands.

### F2 — Pod/service CIDR accepts are not interface-bound, so they are spoofable and bypass the 6443 restriction

- **Severity**: ⚠️ WARNING
- **Impact**: 🧠 HIGH
- **Dimension**: Safety & Quality
- **Location**: host `/etc/nftables.conf`, rules `ip saddr 10.42.0.0/16 accept` and `ip saddr 10.43.0.0/16 accept`
- **Detail**: Both rules match on source address alone, with no `iifname` qualifier, and they accept **all ports**. A packet arriving on the public interface with a forged RFC1918 source in either range is therefore accepted to any service — including 6443, whose careful AS12912 restriction sits two rules above and is simply skipped when the source-address rule matches first.

  These rules are also **redundant**: the preceding `iifname { "cni0", "flannel.1", "cilium_host" } accept` already admits legitimate CNI traffic. Pod egress to Gitea was verified working (criterion 3.5) with both rule families present, so which one carried the traffic was not isolated.
- **Fix ⭐ Recommended** — delete both `ip saddr` rules, keeping the interface-based rule
  - **Approach**: remove the two lines from `/etc/nftables.conf`, reload, re-run the phase 3 egress check.
  - **Strength**: removes the problem class rather than narrowing it, and costs nothing if the `iifname` rule is sufficient — which it should be, since all pod traffic arrives on a CNI interface by construction.
  - **Tradeoff**: if some k3s component reaches the host from a pod IP over an interface not in the list, it breaks; the egress test must be re-run to confirm, and a k3s restart is the honest way to exercise it.
  - **Confidence**: medium-high. The redundancy is clear from the rule order, but I did not empirically isolate which rule admits pod traffic — deleting them is the test.
  - **Blind spot**: spoofing was not attempted from outside, so real-world exploitability is unproven. Return-path constraints make TCP session hijacking impractical; the exposure is strongest for one-way and UDP traffic. Hetzner may also filter RFC1918 sources upstream — unverified.
- **Decision**: FIXED (2026-08-19) — recommended fix applied. Both `ip saddr 10.42.0.0/16` and `ip saddr 10.43.0.0/16` accept rules deleted; the `iifname { "cni0", "flannel.1", "cilium_host" }` rule retained. The predicted regression did **not** occur: `cni0` (10.42.0.1/24) and `flannel.1` both exist and carry the traffic, so the deleted rules were genuinely redundant. Re-verified criterion 3.5 with a log-readable pod — DNS resolves, `git.tobiko.kondi.net` returns 200, `kubernetes.default.svc` returns 401 as expected. An initial ephemeral `--rm -i` test appeared to fail; that was a harness artifact, not a cluster fault, and was disproven by the logged re-run.

### F3 — None of the host or cluster configuration is under version control

- **Severity**: ⚠️ WARNING
- **Impact**: 🧠 HIGH
- **Dimension**: Architecture
- **Location**: `plan.md` § Implementation Approach; repo diff `3e6f331..36b169f` (8 files, all documents plus `rbac.yaml`)
- **Detail**: The plan states as an explicit architectural decision: *"Everything in-cluster is delivered as declarative manifests dropped into k3s's auto-deploy directory, so the cluster's contents are reproducible from files rather than from a sequence of typed commands."* The manifests were indeed written declaratively — but they exist **only on the box**. `/etc/nftables.conf`, `/etc/nftables.d/as12912.nft`, `/usr/local/sbin/refresh-as12912-set.sh`, `as12912-refresh.{service,timer}`, `haproxy-ingress.yaml` and `prometheus.yaml` appear in no commit.

  So the decision is satisfied in form and defeated in substance: the configuration is declarative but not reproducible, because reproducing it depends on a disk the risk register rates as Medium-likelihood of failure inside nine weeks. Today the only record of these files is prose inside commit messages. This also compounds the deliberate exclusion of off-box backups.
- **Fix ⭐ Recommended** — commit the host and cluster manifests into the repo
  - **Approach**: add a directory (e.g. `infra/tachiko/`) holding the nftables config, the refresh script, the systemd units and both k3s manifests, as the source of truth; deploy from there.
  - **Strength**: makes the plan's stated architecture true, gives the manifests review and history, and turns a rebuild from archaeology into a copy. Cheap now — the files are small and already written.
  - **Tradeoff**: creates a second copy that can drift from the box unless deployment always goes through it; a half-adopted version of this is worse than neither, because it looks authoritative while being stale.
  - **Confidence**: high on the problem, medium on the shape — whether these belong in this repo or a separate infra repo is a real decision this review should not make.
  - **Blind spot**: did not check whether committing the AS12912 set file is wanted (it is generated and would churn weekly), nor whether the public GitHub mirror should receive infra files at all — the operator already chose to keep the substrate branch off GitHub for exactly that reason.
- **Decision**: PARTIALLY FIXED (2026-08-19) — recommended fix applied as far as it goes. Six files captured into `infra/tachiko/`, mirroring their host paths, verified byte-identical to the host by sha256. `/etc/nftables.d/as12912.nft` deliberately excluded (generated weekly from live BGP data; a committed copy would churn and mislead) — the script producing it is tracked instead. No credentials included; the branch stays off the public GitHub mirror.

  **The finding is not fully closed.** Nothing deploys *from* this directory — it is a copy, and copy and host will drift the moment someone edits the box. The README states this explicitly rather than implying authority the directory does not have. Building the deployment path is queued in `follow-ups/review-fixes.md`. Also still absent: the k3s install invocation and the rescue-boot quota procedure, neither of which is expressible as a file to apply.

### F4 — The Prometheus chart is unpinned while HAProxy is pinned

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Pattern Consistency
- **Location**: host `/var/lib/rancher/k3s/server/manifests/prometheus.yaml` (no `version:` key) vs `haproxy-ingress.yaml` (`version: 1.53.0`)
- **Detail**: Two manifests written in the same change, one pinned and one not. The unpinned HelmChart resolves whatever is latest at reconcile time, so a node rebuild or a re-reconcile can silently install a different Prometheus than the one reviewed (currently `prometheus:v3.14.0`). This sits badly against the change's own headline decision — k3s was pinned to `v1.36.3+k3s1` deliberately, and the plan argues at length that controlling versions is the one axis where self-hosting beats managed.
- **Fix ⭐ Recommended** — pin the Prometheus chart to the version now installed
  - **Approach**: add the resolved chart `version:` to the manifest, matching what is currently running.
  - **Strength**: restores determinism and makes the two manifests consistent; a one-line edit.
  - **Tradeoff**: pinned charts need deliberate upgrades, which is work someone must remember to do.
  - **Confidence**: high — the mechanism is identical to the one already working for HAProxy.
  - **Blind spot**: the installed chart version was not read back from the Helm release, only the image tag; the exact chart version to pin must be read from the release before editing.
- **Decision**: FIXED (2026-08-19) — the blind spot was closed first: the chart version was read back from the Helm release secret (`chart: prometheus, version: 29.27.0, appVersion: v3.14.0`) rather than guessed from the image tag. `version: 29.27.0` added to the manifest, so it pins exactly what was already running and the reconcile was a no-op — pods kept the same names and did not restart. Both auto-deploy manifests are now pinned, matching the change's own k3s version-pinning rationale.

### F5 — The workspace quota does not constrain host-root processes

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Plan Adherence
- **Location**: `plan.md` phase 1 § Overview and change 4
- **Detail**: The plan's stated purpose is that "a runaway workspace cannot fill `/` and stall the k3s datastore". What was delivered is narrower: project quota is not enforced against processes holding `CAP_SYS_RESOURCE`, so any host-root process remains unbounded. Verified during implementation — a root `dd` wrote 20 MiB against a 10 MiB limit, while the same write as an unprivileged user failed with `EDQUOT` at 9 MiB. Containers drop that capability by default, so the agent-workspace case the plan actually cares about *is* covered; the discrepancy is between the plan's wording and the mechanism's reach, and it was recorded in the phase 1 commit rather than hidden.
- **Fix**: amend the plan's phase 1 wording (or `infrastructure.md`'s risk row) to state that the boundary binds pods, not host-root processes.
- **Decision**: FIXED (2026-08-19) — documented in `infrastructure.md`'s risk register rather than in the plan, so the correction lands in the durable document rather than in an approved artifact that describes work already done. The row now records the quota as applied and verified, states plainly that the cap binds pods and not the host because the kernel exempts `CAP_SYS_RESOURCE`, and drops the impact from High to Medium — the mitigation is real, just narrower than the original wording implied. Alerting on root usage is retained as still-worth-adding.

### F6 — Manual item 5.6 was checked without the restart it names

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Success Criteria
- **Location**: `plan.md` Progress item 5.6
- **Detail**: The item reads "A devcontainer **restart** picks up the new kubeconfig and its firewall exception". No devcontainer restart occurred. The evidence accepted was a `kubectl` call from the already-running container returning `403 Forbidden` on `nodes` — which proves the kubeconfig authenticates and RBAC applies, but not that `run.sh` re-derives the firewall exception from the new `server:` value on a cold start. That derivation is the part only a restart exercises.
- **Fix**: restart the devcontainer once and confirm cluster access still works; if it does, the item is honestly checked.
- **Decision**: DEFERRED (2026-08-19) — queued in `follow-ups/review-fixes.md` with the exact check to run. It cannot be closed from inside the container that needs restarting, and the Progress item stays checked rather than being flipped back: the operator confirmed the identity works from their own machine, so what is untested is narrowly the cold-start re-derivation of `ALLOWED_HOSTS` in `run.sh`, not whether the kubeconfig functions. Recorded so the gap between the item's wording and its evidence is visible rather than lost.

### F7 — The cert-manager grant was dropped without the plan authorising it

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Plan Adherence
- **Location**: `devcontainer/k8s/rbac.yaml:47-57` (removed block, previous revision)
- **Detail**: Phase 5's contract names exactly one removal — "The Argo CD grants are dropped". The implementation also removed the `cert-manager.io/clusterissuers` grant. The reasoning is sound and was stated in the commit (cert-manager is not installed here, and the plan excludes installing it), but it is a second undeclared removal inside a phase whose contract was written removal-by-removal. Worth naming only because this file is the FR-085 surface, where undeclared edits are exactly what review exists to catch.
- **Fix**: none needed if intentional — record it, and restore the grant when cert-manager is installed.
- **Decision**: ACCEPTED (2026-08-19) — the removal stands; it was correct, just undeclared. Documented in `devcontainer/k8s/rbac.yaml` itself rather than only here, so the note sits where the next editor of that file will read it. The comment records why the grant went and what its absence costs: once cert-manager exists, the ClusterIssuer grant must be restored or the devcontainer cannot independently confirm a ClusterIssuer is present, which is precisely the "don't take the operator's word for it" property the cluster-scoped grants exist to provide.

### F8 — `flush ruleset` in `/etc/nftables.conf` destroys k3s service NAT on every reload

- **Severity**: 🔴 CRITICAL
- **Impact**: 🧠 HIGH
- **Dimension**: Safety & Quality
- **Location**: host `/etc/nftables.conf:11` (`flush ruleset`), tracked copy `infra/tachiko/etc/nftables.conf`
- **Detail**: Found during F1 triage, not present in the original review. `flush ruleset` is the conventional opening of an nftables config, but on a k3s node it is destructive: it flushes every table in every family, including the `iptables-nft` tables kube-proxy owns. Observed directly — after a reload, `iptables -t nat -S | grep -c KUBE-EXT` went from 30 to **0**, ingress returned `HTTP 000` from both the host and off-box, and kube-proxy did not rebuild the rules on its own. Recovery required `systemctl restart k3s`, after which the count returned to 30 within 5 seconds.

  This makes every firewall change a potential cluster-networking outage, which is exactly the kind of coupling the operator will not remember six weeks from now. It also means the phase 2 ruleset, as tracked, is unsafe to reload on a running cluster — including at boot, where ordering between `nftables.service` (sysinit) and `k3s.service` (multi-user) happens to save it today.
- **Fix A ⭐ Recommended** — scope the flush to this table only
  - **Approach**: replace `flush ruleset` with `table inet filter { }` + `delete table inet filter` (or `flush table inet filter`), leaving other families untouched.
  - **Strength**: keeps reloads idempotent for our own rules while never touching kube-proxy's tables; a two-line change to a file already tracked in the repo.
  - **Tradeoff**: no longer a clean-slate reload, so stale rules in *other* tables we might add later would survive a reload and need explicit removal.
  - **Confidence**: high on the diagnosis — the counter going 30 → 0 across a reload, and recovery on k3s restart, is direct evidence. Medium on the exact replacement syntax being drop-in; it needs a `nft -c -f` check and one reload test with the KUBE-EXT count watched.
  - **Blind spot**: not tested across a reboot, where service ordering rather than reload semantics decides the outcome. Also not checked whether anything else on the host owns nftables tables.
- **Decision**: FIXED (2026-08-19) — Fix A applied. `flush ruleset` replaced with `table inet filter` / `delete table inet filter`, scoping the reset to our own table. Proven by re-running the exact operation that caused the outage: `KUBE-EXT` count stayed at **30 across the reload** (previously 30 → 0), our three chains rebuilt, the AS12912 set repopulated to 30 entries, and the ingress stayed at 200 throughout. The stated blind spot stands — this was a reload test, not a reboot test, so boot-ordering between `nftables.service` and `k3s.service` remains unverified.

## Automated Verification (re-run during review)

| Criterion | Command | Result |
| --- | --- | --- |
| 1.1 | `findmnt -no OPTIONS /` | `prjquota` present — PASS |
| 1.2 | `tune2fs -l /dev/md2` | `project`, `quota` present — PASS |
| 1.3 | `repquota -P /dev/md2` | project `k3s-storage`, hard `209715200` KiB (200 GiB), 10928 KiB used — PASS |
| 1.4 | quota enforcement | previously verified `EDQUOT` at 9 MiB against a 10 MiB limit (unprivileged) — PASS, see F5 |
| 2.1 | `nft list chain inet filter input` | policy `drop`, 9 accept rules — PASS, but see F2 |
| 2.2 | `systemctl is-enabled nftables` | `enabled` — PASS |
| 2.3 | set membership | `46.205.216.245` → `46.204.0.0/15` (auto-merged) — PASS |
| 3.1 | `kubectl get nodes` | `v1.36.3+k3s1` — PASS |
| 3.2 | node condition | `Ready` — PASS |
| 3.3 | `kubectl get sc` | `local-path (default)` — PASS |
| 3.4 | traefik search | 0 matches cluster-wide — PASS |
| 4.2 | `kubectl get ingressclass` | `haproxy (default)` — PASS |
| 6.2 | `/-/healthy` | HTTP 200 — PASS |
| 6.3 | active targets | api-servers, nodes, cadvisor all `up` — PASS |
| 6.4 | `kubectl get pvc -n monitoring` | `Bound` on `local-path` — PASS |

Every automated criterion still holds at review time. No regressions since the phase commits.

## Manual Verification

Rubber-stamp audit of the 8 checked Manual items:

- **1.5, 2.6, 2.7, 3.6, 4.4** — supported by direct evidence, and 3.6 was verified by the operator from two independent vantage points (connect from AS12912, timeout from `10.242.0.10`), which is stronger evidence than the automated items carry.
- **6.5** — verified live during review: wildcard DNS resolves and the ingress serves. Sound, though see F1 — the item proves reachability, and reachability turned out to be the problem.
- **7.3** — the operator agreed with a substantive qualification, and that qualification was written into the artifact (`ca4878c`) rather than noted only in conversation. Correctly checked.
- **5.6** — **flagged, see F6.** Checked on evidence that does not cover what the item's wording claims.

One of eight items shows a gap between the wording and the evidence. The remaining seven are honestly checked.
