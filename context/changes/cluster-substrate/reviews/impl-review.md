<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Cluster Substrate — Operator, Build Path and Registry

- **Plan**: `context/changes/cluster-substrate/plan.md`
- **Scope**: whole plan — all 8 phases, 43 of 43 Progress items checked
- **Date**: 2026-08-20
- **Diff basis**: Progress SHAs. All 21 commits in `main..HEAD` carry the change's `<type>(cluster-substrate):` subject convention and the merge-base range coincides exactly with the change, so the anchor is complete rather than partial. 64 changed files, of which ~40 are unmodified kubebuilder scaffold.
- **Verdict**: REWORK REQUIRED — triaged 2026-08-20: 8 of 9 findings fixed, F5 blocked on cluster access and queued
- **Findings**: 3 critical, 4 warnings, 2 observations

## Verdicts

| Dimension | Verdict |
| --- | --- |
| Plan Adherence | FAIL |
| Scope Discipline | WARNING |
| Safety & Quality | FAIL |
| Architecture | WARNING |
| Pattern Consistency | WARNING |
| Success Criteria | WARNING |

Two independent FAILs, and three CRITICAL findings — either alone forces REWORK REQUIRED.

The infrastructure work of this change is sound: Harbor, Tekton, the build pipeline, the read-back RBAC and the metrics protection all match what was planned, several of them with more care than the plan asked for. What fails is narrower and sharper: **the API the change exists to introduce was never written**, and **the operator cannot re-pull its own image**. Two of the three criticals sit in code added late in the session, after the plan's criteria were already closed.

## Findings

### F1 — The `Herd` API ships the scaffold placeholder, not the declared type

- **Severity**: 🔴 CRITICAL
- **Impact**: 🧠 HIGH
- **Dimension**: Plan Adherence
- **Location**: `api/v1alpha1/herd_types.go:28-37`, `config/crd/bases/henia.dev_herds.yaml`

**Detail**: Phase 2's contract states that `spec` carries the declared repositories — "one, several, or a monorepo, per FR-450" — and `status` represents the running instance. `HerdSpec` contains exactly one field: `Foo *string`, the kubebuilder placeholder, comment included ("foo is an example field of Herd. Edit herd_types.go to remove/update"). The served CRD's schema confirms it: `spec` properties are `['foo']`, `status` properties are `['conditions']`.

This is not a formatting difference. The plan's single most-argued architectural decision — that the declaration and the running instance are `spec` and `status` of one object rather than two kinds — is recorded in the type's doc comment and in the CRD description, but no field expresses it. The type documents a design it does not implement.

It is also already live: `herds.henia.dev` is served and stored on the cluster with `foo`, and a `Herd` named `sample` exists. Removing a served field later is an API break, however alpha the version.

Criteria 2.4 and 2.5 passed because they assert group, version, kind, categories and shortName — none of them looks at the spec's fields. The plan's exclusion "Not implementing reconciliation logic" covers the controller's *behaviour*; the type itself was explicitly in scope.

**Fix A ⭐ Recommended** — replace `Foo` with the repositories field the contract names, regenerate, re-apply the CRD.
- *Strength*: Closes the contract exactly, and does it while `v1alpha1` has one instance and no consumers — the cheapest moment this will ever have. `make manifests generate` already round-trips cleanly (2.3 re-verified today), so the mechanical part is proven.
- *Tradeoff*: Requires deciding the repository field's shape now, which S-01 `project-declaration` was going to decide with more information.
- *Confidence*: High that the change is safe — no controller reads `Foo`, the reconciler is a pure no-op, and the only `Herd` on the cluster is a sample. Lower confidence on the field's ideal shape, which is exactly what S-01 was for.
- *Blind spot*: I did not check whether anything outside this repository already consumes `herds.henia.dev` — only that nothing inside it does.

**Fix B** — leave the placeholder, and amend the plan to record that the type's fields were deferred to S-01.
- *Strength*: Honest about what happened, costs nothing, avoids designing the field under time pressure.
- *Tradeoff*: Leaves `foo` in a served API and leaves criterion 2.x closed against a contract that was not met. Every later reader of the CRD sees a placeholder.
- *Confidence*: High that it is safe; low that it is wise.
- *Blind spot*: Whether F-01's outcome statement can honestly be called satisfied with a placeholder type is a judgement I am not the one to make — 8.5 was already confirmed on other grounds.

**Decision**: FIXED — applied differently, at the operator's direction. A minimal working schema rather than the full FR-450 design: `repositories[]` (required, MinItems=1) each carrying `url`, an optional `revision` and an optional `secretRef`, plus an optional `targetNamespace`. `revision` was added beyond the three fields requested, because this change was already bitten once by a clone with no ref building a tree that lacked the code it was meant to build. `observedGeneration` was deliberately NOT added: the reconciler is a no-op, so it would be a status field that is always empty. Regeneration is idempotent, build and vet clean. The CRD still needs re-applying on the cluster before the schema is live.

### F2 — The operator has no image-pull credential path; it runs on a cached image

- **Severity**: 🔴 CRITICAL
- **Impact**: 🧠 HIGH
- **Dimension**: Safety & Quality
- **Location**: `config/manager/manager.yaml`, `infra/tachiko/etc/rancher/k3s/registries.yaml:16-19`

**Detail**: Phase 6's contract says "a Deployment pulling from Harbor **with an image pull secret**". No `imagePullSecrets` appears anywhere under `config/`, `deploy/` or `infra/` except on the Tekton ServiceAccount, and the live Deployment has none either. The tracked `registries.yaml` carries no `configs.*.auth` block and states, in a comment, "No credentials here on purpose: pulls authenticate with the imagePullSecret on the Deployment" — describing a mechanism that does not exist.

Anonymous pull does not work: `GET /v2/henia/henia-operator/manifests/77c7c39` with an anonymous Harbor token returns **401**, and `GET /api/v2.0/projects?name=henia` returns `[]` anonymously, so the project is not public.

The operator is therefore running because its image is already in the node's containerd store — the pod-replacement event says so verbatim: *"Container image ... already present on machine and can be accessed by the pod"*. Consequences: image GC, a node rebuild, or a deploy of any **new** tag would fail with `ImagePullBackOff`. Criterion 6.4 — the FR-470 supervision demonstration — passed against the cached image and so did not exercise this path.

One thing I could not check: the host's actual `/etc/rancher/k3s/registries.yaml`. If it carries an `auth` block the tracked copy lacks, pulls work and the finding becomes drift between the host and the repo instead. Either way something tracked is wrong.

**Fix A ⭐ Recommended** — create the pull Secret and reference it from `config/manager/manager.yaml`, so the tracked manifest matches its own documentation.
- *Strength*: Restores the mechanism `registries.yaml` already claims, keeps the credential out of git, and makes the Deployment reproducible from `config/` alone — which is what drift guard D1 assumes.
- *Tradeoff*: Another out-of-band Secret to create and remember, in a change that already has four.
- *Confidence*: High. The Harbor robot credential already exists as `harbor-push` in `default`; a read-scoped equivalent in `henia-system` is the same shape.
- *Blind spot*: I did not verify from the host whether the first pull at 17:18 actually succeeded over the network or whether the image reached containerd another way — that would distinguish "never worked" from "worked and then the mechanism was removed".

**Fix B** — put the credential in `registries.yaml`'s `configs` block on the host and delete the now-false comment.
- *Strength*: One place, applies to every pull from that registry, no per-Deployment wiring.
- *Tradeoff*: The file stops being trackable — it was deliberately kept free of secrets so it could live in `infra/tachiko/`. This trades the change's own stated discipline for convenience.
- *Confidence*: High that it works; it is the standard k3s pattern.
- *Blind spot*: Whether anything else pulls from this registry and would be affected.

**Decision**: FIXED — Fix A. `config/manager/manager.yaml` now declares `imagePullSecrets: [harbor-pull]`, and the false claim in `registries.yaml` is replaced by one that names where the secret actually is, with a line recording what it used to assert. The Secret itself is created out-of-band and not committed, like the other four. **Not yet effective**: the Secret does not exist on the cluster and the Deployment has not been re-applied, so the operator is still running on the cached image until both happen.

### F3 — The devcontainer-verify pipeline cannot run, and its key assertion cannot fail

- **Severity**: 🔴 CRITICAL
- **Impact**: 🔎 MEDIUM
- **Dimension**: Safety & Quality
- **Location**: `deploy/tekton/devcontainer-verify.yaml:110-127`

**Detail**: Three defects in one 130-line file, added by `a0d067b` to close criterion 1.6. The commit says "Not yet run", and nothing has run it.

1. **It cannot complete a first run.** Tekton compiles every step of a Task into containers of a *single pod*, and the kubelet pulls all of those images when the pod is created — before any step's script executes. Step `start` declares `image: $(params.image)`, the image step 2 is about to build. So `step-start` enters `ImagePullBackOff` at pod creation, the build step never gets to push, and the run hangs until the 1h timeout. The syntax is valid — `image` does accept variable substitution in Tekton v1 — so this passes webhook validation and fails at scheduling. It needs a separate TaskRun, or a second Pipeline task with `runAfter`.
2. **Its central assertion cannot fail.** The hard `command -v` loop covers `kubectl tea kustomize sops make` and omits **`go` and `kubebuilder`** — the two tools phase 1 added and the only two this pipeline exists to verify. They appear only inside `echo "$(go version)"`, where `set -e` does not propagate a command substitution's exit status. An image with no Go toolchain prints a blank line and exits 0.
3. **It runs an unvetted image as root.** `start` carries no `securityContext`, and `devcontainer/Dockerfile` declares no `USER`, so a just-built image executes as root in `default` with the workspace mounted — while the sibling build step two lines above is pinned to uid/gid 1000.

**Fix A ⭐ Recommended** — split `start` into its own Task with `runAfter: [build]`, add `go` and `kubebuilder` to the hard assertion loop, and give the step a `securityContext` matching its sibling.
- *Strength*: Fixes all three without changing the pipeline's shape, and the split is what makes the image exist before its pod is created.
- *Tradeoff*: A second TaskRun means a second pod and a second workspace attachment; slightly slower.
- *Confidence*: High on defects 2 and 3, which are plainly readable in the file. High on defect 1 as well — the single-pod, pull-all-images-first behaviour is long-standing Tekton semantics — but it has not been demonstrated on this cluster, because the pipeline has never run.
- *Blind spot*: I did not test the corrected pipeline either. Until a PipelineRun completes, this file remains unexercised code, and the argument for it is exactly the argument F3 makes against it.

**Fix B** — delete the file and leave 1.6 a manual check.
- *Strength*: Removes untested infrastructure whose whole purpose was to make a check trustworthy. 1.6 was already closed by a human running the build.
- *Tradeoff*: Loses the repeatable clean-context guarantee for future changes, and the credential-free build context that a clone gives and a workstation does not.
- *Confidence*: High.
- *Blind spot*: None material.

**Decision**: FIXED — Fix A, all three defects. `start` is now its own `devcontainer-start` Task with `runAfter: [build]`, so its pod is created after the image exists. Its assertion loop covers `go` and `kubebuilder` as hard checks and additionally asserts the versions (`go1.26.`, `v4.15.0`), which makes it verify criteria 1.3–1.5 in the image rather than merely print them. It carries a `securityContext` matching its sibling — uid/gid 1000, `ALL` capabilities dropped, `RuntimeDefault` seccomp. **Still unexercised**: a PipelineRun has not been executed, which is the remaining half of this decision.

### F4 — `hack/verify.sh` under-reports: silent omissions and one vacuous pass

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:146-153`, `:224`, `:303`, `:381`

**Detail**: The script's stated contract is that a check which cannot run says SKIP and why, because "a verification script that quietly reports green for what it never attempted is worse than no script" (`:9-11`). Three ways it breaks its own rule:

- **Silent omission without a cluster.** Each phase's `else` branch emits exactly one SKIP — 3.1, 4.1, 5.1, 6.1, 8.1, D1. Criteria 4.2, 4.3, 4.4, 6.2, 6.3, 6.5, 8.2, 8.3 and 8.4 are then neither PASS nor FAIL nor SKIP: they vanish from the table *and* from the "these stay unconfirmed" list. Nine criteria disappear silently.
- **Vacuous pass in 2.7.** `git show --name-only --format= 2604250 2>/dev/null` discards all errors. On a shallow clone or rewritten history the commit is unreachable, `strays` is empty, and 2.7 reports PASS having inspected nothing.
- **7.x has never executed.** Every run in this session had `PROM_AUTH` unset, so 7.1–7.4 always SKIPped. The 7.4 check counts targets with `grep -o '"job":"henia-operator"'` over raw JSON while counting `up` with a Python parser; Prometheus emits `job` in both `labels` and `discoveredLabels`, so the count can be 2 for one healthy target. It errs toward FAIL rather than toward a lie, but the two halves of one check use different methods and neither has ever run.

**Fix ⭐** — give every criterion its own SKIP in the no-cluster branches, drop the `2>/dev/null` in 2.7 and FAIL when the commit is unreachable, and count 7.4's targets with the same parser that counts `up`.
- *Strength*: Restores the property the script is *for*; each change is local and mechanical.
- *Tradeoff*: More lines in the else branches; slightly more verbose output when the cluster is unreachable.
- *Confidence*: High — the omission is directly readable, and the 2.7 vacuous pass reproduces with any unknown SHA.
- *Blind spot*: The 7.4 double-counting is reasoned from Prometheus's documented response shape, not observed — the path has never run.

**Decision**: FIXED — all three. Every criterion now emits its own SKIP in the no-cluster branches: the suite reports 43 checks with a cluster and 43 without, where it previously dropped nine silently. 2.7 no longer discards git's errors and FAILs on an unreachable commit — verified by substituting a bogus SHA, which now produces `FAIL 2.7 … commit deadbee unreachable` where it previously produced PASS. 7.4 counts targets and `up` with the same parser.

### F5 — Prometheus's metrics-reader authorisation exists only in the cluster

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Plan Adherence
- **Location**: `infra/tachiko/var/lib/rancher/k3s/server/manifests/prometheus.yaml:31`

**Detail**: Phase 7's contract binds Prometheus's ServiceAccount to the kubebuilder-generated metrics-reader ClusterRole. The ClusterRole is tracked (`config/rbac/metrics_reader_role.yaml`); the **binding is not**. The only occurrences of `metrics-reader` in the repository are that role, its kustomization entry, and a comment in `prometheus.yaml` asserting that authorisation happens "by the henia-metrics-reader ClusterRole".

The scrape works, so something authorises it in the cluster — untracked. This is the same class as F2: a comment in a tracked file describing cluster state that no tracked file creates. The plan's Implementation Approach restated the track-what-you-apply discipline "rather than assumed" precisely because the previous change's review found this copy drifting.

I could not confirm the binding exists, only that the repo does not create it: the read-only identity cannot list ClusterRoleBindings.

**Fix ⭐** — add the ClusterRoleBinding to the tracked manifests, next to the scrape config that depends on it.
- *Strength*: Makes the comment true and the telemetry path reproducible from the repo.
- *Tradeoff*: None material.
- *Confidence*: High that it is missing from the repo; medium on the exact live binding's shape, which I could not read.
- *Blind spot*: The live binding may be named or scoped differently from what I would write; it should be read from the cluster before being committed.

**Decision**: PENDING — accepted (read the live binding and track it), but blocked: the read-only identity cannot list ClusterRoleBindings, so the live shape has to be read with cluster access. Queued with the other cluster-side actions.

### F6 — The clone credential travels in the git URL

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Safety & Quality
- **Location**: `deploy/tekton/henia-operator-build.yaml:65-67`, `deploy/tekton/devcontainer-verify.yaml:64-66`

**Detail**: Both pipelines clone with `https://$(cat /gitea/username):$(cat /gitea/password)@git.tobiko.kondi.net/...`. The substitution is shell, not Tekton, so the value never reaches the TaskRun or pod spec — that part is right, and criterion 5.5 checked it. But at runtime the password lands in `git`'s argv, readable through `/proc` by anything in that pod; it is echoed by git's own `fatal: unable to access '<url>'` on failure; and it is persisted as `remote.origin.url` in `.git/config` on the node's local-path PVC, where it survives until the next run's `rm -rf`.

Worth noting for the record: criterion 5.5 — "the pipeline definition is reviewed for credential handling" — was confirmed against this same file. The review happened; this is what it did not catch.

**Fix ⭐** — use `GIT_ASKPASS` or a credential helper so the secret never enters the URL.
- *Strength*: Removes all three exposures at once; a few lines in the clone step.
- *Tradeoff*: Slightly less obvious than an inline URL to a future reader.
- *Confidence*: High — all three exposure paths are standard git behaviour.
- *Blind spot*: I did not check whether the PVC's contents are readable by other workloads on this single-node cluster; the exposure window is real but its reachability is unquantified.

**Decision**: FIXED — `GIT_ASKPASS` in both pipelines. The clone URL no longer carries the credential, so it is absent from git's argv, from git's error output, and from `remote.origin.url` in the persisted `.git/config`.

### F7 — Concurrent PipelineRuns clobber each other's source

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW
- **Dimension**: Safety & Quality
- **Location**: `deploy/tekton/henia-operator-build.yaml:27-36`, `:64`

**Detail**: The workspace is a single fixed PVC and the clone path has no per-run component. Two PipelineRuns of the same pipeline land on the same node — it is a single-node cluster, so `ReadWriteOnce` does not prevent it — and the second run's `rm -rf .../repo` deletes the first one's source mid-build. The first fails with a corrupted-tree error that reads like a Dockerfile fault.

**Fix**: include `$(context.pipelineRun.name)` in the clone path.

**Decision**: FIXED — each PipelineRun clones into its own tree, named by `$(context.pipelineRun.name)` passed from the Pipeline. Trees older than three days are pruned at clone time so the workspace does not grow without bound; three days exceeds any run, so a concurrent run is never the one pruned.

### F8 — The operator and the Tekton assets bypass k3s auto-deploy

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Architecture
- **Location**: `deploy/tekton/README.md:135-136`, `infra/tachiko/var/lib/rancher/k3s/server/manifests/`

**Detail**: The plan's Implementation Approach says everything on the cluster is delivered as manifests in k3s's auto-deploy directory and tracked under `infra/tachiko/` in the same commit that applies it. That directory holds four entries — haproxy-ingress, harbor, prometheus, tekton-pipelines — and no henia manifest. The operator is applied imperatively with `kustomize build config/default | kubectl apply -f -`; the Tekton Pipeline, Task, PVC and ServiceAccount live in `deploy/tekton/` and are applied the same way.

Both are tracked, and drift guard D1 in `hack/verify.sh` compares the rendered image against the running one — a reasonable compensating control. Recording this as an observation rather than a warning because a rendered copy in the auto-deploy directory would create a second source of truth against the kustomize base, which is a worse outcome. The plan's blanket statement is what needs amending, not the implementation.

**Decision**: FIXED — the plan's wording is amended, not the implementation. A note under Implementation Approach records that kustomize-managed and hand-applied assets are a deliberate exception to the auto-deploy half of the rule but not to the tracking half, with D1 as the compensating control, and that the blanket wording predates those bases. The Progress section was not touched.

### F9 — The image tag is not derived from the revision the pipeline cloned

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Plan Adherence
- **Location**: `deploy/tekton/henia-operator-build.yaml:33`, `deploy/tekton/README.md:43`

**Detail**: Phase 5 says images are tagged with the short commit SHA of the revision built, so that a deployment names exactly one build. The Task takes a fully-formed `image` param and never derives the tag; the short SHA is computed on the *caller's* local clone. The clone step does compute the real short SHA and echoes it — but nothing binds the two. A caller whose working copy differs from the branch tip tags the image with a SHA the pipeline did not build. Convention rather than mechanism.

**Decision**: FIXED — the tag is now derived where the tree is. The clone step writes the real short SHA to a Tekton result and the build step tags from it; the `image` parameter is the repository without a tag, and the resolved reference is published as a Pipeline result for the deploy step to read. In `devcontainer-verify` the start task consumes `$(tasks.build.results.image)` rather than the untagged parameter. The README no longer asks the caller to compute a SHA from their own working copy.

## Automated Verification (re-run during review)

| Criterion | Command | Result |
| --- | --- | --- |
| 1.1 | `droast devcontainer/Dockerfile` | PASS — 0 errors, 6 warnings, 6 info |
| 2.1 | `go build ./...` | PASS |
| 2.2 | `go vet ./...` | PASS |
| 2.3 | `controller-gen` rbac+crd+object, then `git diff` | PASS — no diff |
| 2.4–2.6 | via `make verify` | PASS |
| 2.7 | via `make verify` | PASS — but see F4, the check can pass vacuously |
| 3.1, 3.2, 3.6 | via `make verify` | PASS |
| 4.1–4.4 | via `make verify` | PASS — controller reports `v1.15.0` |
| 5.1, 5.3, 5.5 | via `make verify` | PASS |
| 6.1, 6.2, 6.3, 6.5 | via `make verify` | PASS |
| 8.1–8.4 | via `make verify` | PASS — writes denied, Secret contents denied |
| D1, D2 | via `make verify` | PASS |
| **Total** | `make verify` | **30 passed, 0 failed, 13 skipped** |

Six checked automated criteria could not be re-run during the review and rest on their implementation-time evidence: 3.3 and 3.4 (need the Harbor robot credential), 3.5 (needs root on tachiko), 5.2 (needs a Harbor credential), 5.4 (needs cluster write), 6.4 (destructive). 7.1–7.3 were re-verified out of band against Prometheus's ClusterIP but SKIP under `make verify` without `PROM_AUTH`.

## Manual Verification

Eleven manual criteria, all checked. Audit outcome — no rubber-stamping found, three items resting on weaker evidence than the others:

- **1.3, 1.4, 1.5** — solid. Re-verified today: `go1.26.7` at `/usr/local/go/bin/go`, kubebuilder `v4.15.0`, all four legacy tools resolve. The image path rather than `/home/agent` is what proves these came from the rebuild rather than the phase-2 hand-install.
- **1.6** — **weakest evidence in the set.** Confirmed on the operator's word that a clean rebuild succeeded; no artefact records it, and the pipeline written to produce one cannot run (F3). Not rubber-stamping — a human did the work — but nothing in the repository will remember it.
- **2.7** — solid, and independently re-derivable from `git show 2604250`.
- **3.6** — solid, and it earned its place: it failed on first check and produced `81c527e`.
- **4.4** — solid; the release label reads `v1.15.0`.
- **5.5** — checked, and the review did happen, but F6 was visible in the reviewed file and was not caught. The criterion's wording ("reviewed for credential handling") is satisfied by the act; the outcome was incomplete.
- **6.6** — checked with a caveat already noted during implementation: the convention's "What was demonstrated" table still describes the throwaway Deployment from `devserver-setup`, not the real operator. Accurate as written, understated.
- **7.4** — solid, and the strongest of the manual set: it failed on first check, produced `da23a3f`, and was re-confirmed independently by the operator after the fix.
- **8.5** — a judgement, confirmed. Worth re-reading against F1 before archive: F-01's outcome was agreed satisfied while the framework's own API carries a placeholder field.
