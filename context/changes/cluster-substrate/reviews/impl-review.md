<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Cluster Substrate — Operator, Build Path and Registry

- **Plan**: `context/changes/cluster-substrate/plan.md`
- **Scope**: whole plan — all 8 phases, 43 of 43 Progress items checked. Second round; round 1 is preserved at `git show dfc64fc:context/changes/cluster-substrate/reviews/impl-review.md`
- **Date**: 2026-08-20
- **Diff basis**: Progress SHAs. All 25 commits in `main..HEAD` carry the change's `<type>(cluster-substrate):` subject convention and the merge-base range coincides exactly with the change. This round concentrates on `dfc64fc..HEAD` — the three fix commits `9a46f1a`, `b181ab0`, `5893187` — because fixes are where new defects live.
- **Verdict**: NEEDS ATTENTION — triaged 2026-08-20: all 10 findings fixed, and every fix that touches the cluster verified on it
- **Findings**: 0 critical, 6 warnings, 4 observations

## Verdicts

| Dimension | Verdict |
| --- | --- |
| Plan Adherence | WARNING |
| Scope Discipline | PASS |
| Safety & Quality | WARNING |
| Architecture | WARNING |
| Pattern Consistency | WARNING |
| Success Criteria | WARNING |

**Round 1's nine findings are closed and verified independently.** `HerdSpec` carries `repositories` with the generated CRD matching the Go types; the Deployment names a pull secret; the metrics-reader binding is tracked and its `roleRef` matches what `config/rbac` actually renders under the `henia-` prefix; the tag is derived from the cloned tree and the whole chain connects; the devcontainer pipeline is wired correctly and has run green. No exclusion is violated, and the plan amendment accurately describes the tree.

What remains is a tier down from round 1: no criticals, nothing broken in the cluster. Six warnings, of which the sharpest three are consequences of the fixes themselves — a verification check that can still pass without verifying, a delivery pipeline rewritten and never run, and a push-scoped credential doing a pull job in the one place the fix commit did not look.

## Findings

### F1 — Check 2.3 can report PASS without regenerating anything

- **Severity**: ⚠️ WARNING
- **Impact**: 🧠 HIGH
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:106-115`

**Detail**: Check 2.3 runs `controller-gen` twice with `>/dev/null 2>&1`, discarding both the output *and* the exit status, then asserts `git diff --quiet -- api config`. If the chosen binary exists and is `-x` but fails at runtime — wrong architecture, missing loader, OOM, a changed flag — nothing is regenerated, the tree is unchanged, and the check reports PASS having verified nothing.

This is the exact class the 2.7 rewrite closed one check above it, left untouched. The script's own header promises that a check which cannot run says SKIP.

Correcting the round-2 agent that raised it: it claimed a live reproduction via `bin/controller-gen` exiting 126, but `[[ -x bin/controller-gen ]]` is **false** in this repo (the symlink is unreadable), so the selector falls through to `bin/controller-gen-v0.21.0`, which works. **The PASS 2.3 results in this session were genuine**, and regeneration was separately confirmed by running controller-gen directly. The defect is latent, not firing.

A residual on the success path: 2.7 now handles git's error exit, but still treats empty output as clean. A `git show` that exits 0 with no file list would pass having inspected nothing. Not reachable today — `2604250` is single-parent and lists 51 files.

**Fix ⭐** — check controller-gen's exit status and FAIL on it; assert 2.7's file list is non-empty.
- *Strength*: Two lines each, in the same shape as the 2.7 fix that is already proven.
- *Tradeoff*: None; the check gets stricter in the direction the script already claims.
- *Confidence*: High — the discarded status is directly readable, and the failure mode was demonstrated in this very environment by a different binary.
- *Blind spot*: I did not enumerate the other checks for the same pattern; 2.3 and 2.7 were the two examined closely, and a sweep might find more.

**Decision**: FIXED — including the sweep, which found a third instance. 2.3 now captures controller-gen's exit status and FAILs on it; 2.7 FAILs when the commit lists no files; and 5.5 distinguishes grep's three exit codes — 1 is "looked, found nothing", 2 is "could not look", and collapsing them let an unreadable `deploy/tekton/` report PASS having scanned nothing. Both new failure paths were proved with a deliberate break, staged first so the break could not leak into a commit: a controller-gen stub exiting 3 produced `FAIL 2.3 … crd/rbac generation failed (exit 3)`, and a missing scan directory produced `FAIL 5.5 … could not scan`.

### F2 — The operator build pipeline has not run since it was rewritten

- **Severity**: ⚠️ WARNING
- **Impact**: 🧠 HIGH
- **Dimension**: Success Criteria
- **Location**: `deploy/tekton/henia-operator-build.yaml`

**Detail**: `b181ab0` and `9a46f1a` changed this pipeline in three substantive ways — the credential mechanism (`GIT_ASKPASS`, then git's `store` helper), a per-run workspace path, and a tag derived from Tekton results. The last `henia-operator` PipelineRun was `henia-build-2` on **2026-08-19**, a day before those changes.

Criterion 5.1 nonetheless reports PASS: `hack/verify.sh` counts *any* succeeded PipelineRun, and `devcontainer-verify-3` satisfies it. So the criterion that would have caught this is answered by a different pipeline.

This is the same defect class as round 1's F3 — code committed and never exercised — relocated to the sibling file. Round 1 made exactly this argument, and F3's own history is the evidence for it: running that pipeline cost three attempts and surfaced two real defects invisible to inspection. The two files share the rewritten clone step almost verbatim, which is reassuring but not the same as having run it.

**Fix A ⭐ Recommended** — run a `PipelineRun` of `henia-operator`, then redeploy from the tag it produces.
- *Strength*: Exercises the rewritten code on the path that actually delivers the operator, and closes F8 in the same motion — the redeploy replaces an image built before the API change.
- *Tradeoff*: A full operator build and a rollout on a single-node box.
- *Confidence*: High that it is the right move. Moderate that it will pass first time — the sibling took three attempts, and the shared code is the part that failed.
- *Blind spot*: The pipeline clones from Gitea, and this branch is unpushed, so a run today builds `origin`'s tip rather than HEAD. Unlike the devcontainer image, the operator's source **has** changed since — so this run would rebuild the *old* API types unless the branch is pushed first.

**Fix B** — tighten criterion 5.1 to name the pipeline, and defer the run.
- *Strength*: Stops one pipeline's success standing in for another's, which is the reporting defect underneath.
- *Tradeoff*: Leaves the rewritten pipeline unexercised — the thing round 1 argued hardest against.
- *Confidence*: High.
- *Blind spot*: None material.

**Decision**: FIXED — Fix A, in full. The branch was pushed to `origin` (`81c527e..7c1d139`), and `PipelineRun henia-build-3` ran the pipeline **as rewritten** and Succeeded, deriving its own tag: `image=harbor-core.harbor.svc/henia/henia-operator:7c1d139`, `commit=7c1d139`. That exercised the credential rewrite, the per-run workspace path, the results chain and the non-root clone step on the path that actually delivers the operator. `devcontainer-verify-4` had already exercised the same shapes beforehand — including the F10 assumption I could not verify by reading, that uid 1000 can write the `local-path` PVC.

### F3 — A push-scoped credential does the pulling

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Pattern Consistency
- **Location**: `deploy/tekton/henia-operator-build.yaml:21-24`

**Detail**: `b181ab0` created a pull-scoped Harbor robot for the operator, arguing that a push credential where pulls happen "would let every node-level pull overwrite images, which is the opposite of what F2 is about". The `tekton-build` ServiceAccount, in the same commit, still carries `imagePullSecrets: [harbor-push]`.

That was inert before, because every step image came from a public registry. It is load-bearing now: the F3 split gave `devcontainer-start` a step image pulled from Harbor, so the push robot is what fetches it. The reasoning was applied in one file and not in its sibling.

`secrets: [gitea-auth]` on the same ServiceAccount is separately vestigial — Tekton's creds-init only consumes SA secrets annotated `tekton.dev/git-*`, and the clone step mounts the Secret itself. Harmless today, but if that annotation were ever added, creds-init would write its own `$HOME/.git-credentials` into every step, silently competing with the hand-written one.

**Fix ⭐** — point `tekton-build`'s `imagePullSecrets` at the pull robot, and drop the inert `secrets:` list.
- *Strength*: Applies the fix commit's own stated principle where it actually bites.
- *Tradeoff*: One more place the pull credential must exist — it is currently only in `henia-system`.
- *Confidence*: High.
- *Blind spot*: I did not check whether anything else in `default` relies on `tekton-build`'s pull secret.

**Decision**: FIXED — `tekton-build`'s `imagePullSecrets` names `harbor-pull`, and the vestigial `secrets: [gitea-auth]` list is gone. The ServiceAccount's comment now records why both changed, including what would have happened had that Secret ever gained a `tekton.dev/git-*` annotation. Needs the `harbor-pull` Secret to exist in `default` as well as `henia-system`.

### F4 — The verify step runs an unvetted image with a writable workspace and a mounted token

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Safety & Quality
- **Location**: `deploy/tekton/devcontainer-verify.yaml:200-215`

**Detail**: The `start` step runs a freshly built image the file itself calls unvetted. Round 1's F3 fix gave it uid/gid 1000 and dropped all capabilities, which is right as far as it goes. Two things it does not cover: the shared workspace is mounted **read-write**, so that image can read and modify every other run's tree on a PVC that persists across runs; and the `tekton-build` ServiceAccount token is automounted — `automountServiceAccountToken` appears nowhere in `config/` or `deploy/`.

**Fix ⭐** — set `automountServiceAccountToken: false` on the verify PipelineRun's pod template, and mount the workspace read-only for the `start` task.
- *Strength*: Closes both without weakening the check, which only reads the tree.
- *Tradeoff*: A read-only workspace mount needs the Task to declare it, and Tekton's per-task workspace `readOnly` applies to the whole task.
- *Confidence*: High on the token; moderate on the mount, which I have not exercised.
- *Blind spot*: I did not verify a read-only workspace still satisfies the `test -d .git` assertion — it should, but the pipeline took three runs to go green, so "should" has a poor record here.

**Decision**: FIXED — the `devcontainer-start` Task declares its workspace `readOnly: true`, and both PipelineRun recipes in the README set `podTemplate.automountServiceAccountToken: false`. No step in either pipeline talks to the Kubernetes API. The read-only mount is not yet exercised — that is part of the pipeline run queued under F2.

### F5 — Nothing durable records how to create `harbor-pull`

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Architecture
- **Location**: `config/manager/manager.yaml:101-108`

**Detail**: The Deployment now depends on a Secret created out-of-band. On a fresh cluster or a restore from git, `kubectl apply` succeeds and the failure surfaces only at pull time as `ImagePullBackOff`, with kubelet's message naming the missing Secret but nothing explaining what belongs in it.

The manifest comment records the *consequence*, and `registries.yaml` names the Secret — but no operational document says how to create one. `deploy/tekton/README.md` lists only `gitea-auth` and `harbor-push`; `infra/tachiko/README.md` names the admin password and the **push** robot. The only record that a pull-scoped robot backs it is `follow-ups/review-fixes.md`, which is change-scoped and will be archived with the change.

This is the same shape as round 1's F2 and F5: cluster state whose recreation is not written down anywhere that outlives the change.

**Fix ⭐** — add `harbor-pull` to `infra/tachiko/README.md`'s credential list, naming the robot and its scope.
- *Strength*: Puts it where the other three out-of-band credentials already are, which is where someone rebuilding the box will look.
- *Tradeoff*: None.
- *Confidence*: High.
- *Blind spot*: None material.

**Decision**: FIXED — `infra/tachiko/README.md` now lists `robot$henia+henia-pull` beside the other out-of-band credentials, naming its scope, both namespaces that hold the Secret, both consumers, the failure mode when it is absent, and why it is deliberately not the push robot.

### F6 — The build README contradicts itself about the image parameter

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW
- **Dimension**: Pattern Consistency
- **Location**: `deploy/tekton/README.md:46-48` vs `:50-53`

**Detail**: The F9 rewrite added its paragraph without removing the one it replaced. "**`image`** — the fully qualified reference *including the tag*" is immediately followed by "The tag is **not** yours to supply. Pass the repository without one." The Task's param description and the README's own example follow the second; a reader who obeys the first gets `repo:sha:sha`.

**Fix**: delete the stale bullet.

**Decision**: FIXED — the superseded bullet is deleted. The paragraph below it and the Task's own param description already state it correctly, and the README's example passes an untagged repository.

### F7 — `verify.sh` covers 41 of 43 criteria, and mis-reports three more when it cannot reach a dependency

- **Severity**: 📝 OBSERVATION
- **Impact**: 🔎 MEDIUM
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:125-131`, `:178-197`, `:283-295`

**Detail**: Four reporting gaps, none of which produces a false green, all of which weaken a script whose header claims its output "maps one-to-one onto the checkboxes":

- **1.1 and 1.2 appear nowhere.** The `droast` lint and the pinned-URL resolution are absent entirely — 41 of 43. `droast` is installed here and runs clean; it was invoked by hand in both reviews.
- **2.5 FAILs instead of SKIPping without a cluster.** Round 1's F4 sweep gave phases 4, 6, 8 and the drift guards per-criterion SKIPs; phase 2 was missed, because 2.5's cluster dependency sits inside a check whose else-branch is `fail`. Reproduced: `KUBECTL=/bin/false ./hack/verify.sh` → `Failed: 2.5`.
- **3.2 and 3.6 do the same** when Harbor is unreachable. Reproduced.
- **5.3's privileged-pod guard parses only `henia-operator-build.yaml`**, so the second pipeline — which gained a third Task in these commits — is not covered. 5.5's secret grep does scan the directory wholesale.

**Decision**: FIXED — all four. 1.1 runs `droast` and fails on a non-zero error count; 1.2 HEADs both pinned URLs, failing on a definite 4xx/5xx and skipping when the network is unreachable. Coverage is now **43 of 43** — the header's one-to-one claim is true. 2.5 skips rather than fails when there is no cluster, and 3.2/3.6 skip rather than fail when Harbor is unreachable: verified with `KUBECTL=/bin/false HARBOR_URL=http://127.0.0.1:9`, which now produces no FAILs at all. 5.3's privileged-pod guard parses every file in `deploy/tekton/` rather than only the first. The suite reports 31 passed, 0 failed, 14 skipped.

### F8 — The running operator predates the API it is supposed to serve

- **Severity**: 📝 OBSERVATION
- **Impact**: 🔎 MEDIUM
- **Dimension**: Architecture
- **Location**: `config/manager/kustomization.yaml:6-8`

**Detail**: The cluster runs `henia-operator:77c7c39`, built from a tree where `HerdSpec` was still the placeholder `Foo *string`. The CRD is served by the API server, so the schema is correct regardless, and the reconciler is a deliberate no-op that reads no spec field — it reconciled `herd-sample` under the new schema during this review, verified in its log. Nothing is broken.

But HEAD's API types are not the ones in the running binary, and drift guard D1 cannot see it: D1 asserts that `config/` renders the image the cluster runs, which it does. A reader would reasonably assume the running operator embeds the current types.

Resolved by F2's Fix A — a rebuild and redeploy closes both — provided the branch is pushed first, since the pipeline clones from Gitea and the operator's source *has* changed since `origin`'s tip.

**Decision**: FIXED — resolved by F2's run, as anticipated. `config/manager/kustomization.yaml` names `7c1d139` and the cluster runs it, so the running binary embeds the current API types rather than a build that predates them. Rollout clean, `imagePullSecrets: harbor-pull` on the live spec, the controller has logged a reconcile since. Verified on the live CRD: `secretRef: {}` is rejected with "secretRef.name must not be empty", a named reference is accepted, and a Herd with no `repositories` is rejected.

### F9 — Three small correctness gaps in the new API and pipelines

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Plan Adherence
- **Location**: `config/crd/bases/henia.dev_herds.yaml:89-98`, `deploy/tekton/henia-operator-build.yaml:113`, `:66-67`

**Detail**:
- `secretRef: {}` validates. `LocalObjectReference.Name` carries `default: ""` and is not required, so an empty reference is accepted and means nothing. No CEL guard.
- `git clone --branch` accepts a branch or tag only; a full commit SHA fails with "Remote branch … not found". Both `herd_types.go`'s comment ("branch, tag or commit") and the README ("the git ref to build") imply commits work.
- Both Tasks declare a `commit` result that no Pipeline surfaces and no step consumes — declared-but-dead output in both files.

**Decision**: FIXED — a CEL rule rejects `secretRef: {}` (`x-kubernetes-validations` confirmed present in the generated CRD); the type comment and the README both say "branch or tag" now, with the README explaining that `git clone --branch` will not take a bare SHA; and both Pipelines surface the `commit` result, so it is no longer declared-but-dead.

### F10 — The one container holding the git credential is the only one running as root

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Pattern Consistency
- **Location**: `deploy/tekton/henia-operator-build.yaml:73-74`, `deploy/tekton/devcontainer-verify.yaml:71-72`

**Detail**: Neither clone step sets a `securityContext`, so both run as uid 0 — while `devcontainer-verify.yaml:205-206` argues explicitly that a just-built image "gets no weaker a posture" than the build step. The step that writes `$HOME/.git-credentials` is the one exception to the rule the file states.

The credential handling itself was verified sound this round: `HOME=/root` exists and is writable in `alpine/git:2.49.0`, the `umask 077` subshell does apply to the redirection, the file lands in the container's own writable layer and never reaches the shared PVC, and nothing copies `$HOME`. Tekton v1.15.0 does not rewrite HOME. All three claims in the step's comment are true as written.

**Decision**: FIXED — both clone steps carry uid/gid 1000, `ALL` capabilities dropped and `RuntimeDefault` seccomp, matching the build step. `HOME` moves to `/tmp` with them: `alpine/git` leaves HOME unset, so the kubelet default is `/root`, which uid 1000 cannot write — and this step writes both `.git-credentials` and `.gitconfig`. **Unverified**: whether uid 1000 can write the `local-path` workspace PVC. That is exactly the kind of assumption that failed twice in round 1's F3, and it is proved or disproved by the pipeline run queued under F2.

## Automated Verification (re-run during review)

| Criterion | Command | Result |
| --- | --- | --- |
| 1.1 | `droast devcontainer/Dockerfile` | PASS — 0 errors, 6 warnings, 6 info (run by hand; not covered by `make verify`, see F7) |
| 2.1 | `go build ./...` | PASS |
| 2.2 | `go vet ./...` | PASS |
| 2.3 | `controller-gen` rbac+crd+object, then `git status` | PASS — no diff, confirmed by running the binary directly rather than through the check (F1) |
| 2.4–2.7 | via `make verify` | PASS |
| 3.1, 3.2, 3.6 | via `make verify` | PASS |
| 4.1–4.4 | via `make verify` | PASS |
| 5.1, 5.3, 5.5 | via `make verify` | PASS — 5.1 counts 3 succeeded runs, but see F2: none is the operator pipeline as rewritten |
| 6.1, 6.2, 6.3, 6.5 | via `make verify` | PASS — 6.3's reconcile log is current, against `herd-sample` under the new schema |
| 8.1–8.4 | via `make verify` | PASS |
| D1, D2 | via `make verify` | PASS |
| **Total** | `make verify` | **30 passed, 0 failed, 13 skipped** |

Six checked automated criteria could not be re-run and rest on implementation-time evidence: 3.3, 3.4 (Harbor robot credential), 3.5 (root on tachiko), 5.2 (Harbor credential), 5.4 (cluster write), 6.4 (destructive). 7.1–7.3 were verified out of band against Prometheus's ClusterIP.

## Manual Verification

Eleven manual criteria, all checked, all with evidence. The audit is materially stronger than round 1:

- **1.3, 1.4, 1.5** — solid, and now corroborated by machine: `devcontainer-verify-3`'s `start` task asserted `go1.26.7`, `kubebuilder v4.15.0` and every tool resolving inside the freshly built image, with the version assertions able to fail.
- **1.6** — was the weakest item in round 1, resting on the operator's word with no artefact. Now closed twice over: the human build, plus a green pipeline that built the image from a clean clone. Its architecture limit is measured rather than predicted — the pipeline proves **amd64**; the arm64 path rests on the manual build.
- **2.7** — solid, independently re-derivable.
- **3.6, 7.4** — the two that failed on first check and produced `81c527e` and `da23a3f`. Both re-verified.
- **5.5** — round 1 noted the review had happened but missed the credential-in-URL exposure. That is now fixed and the file re-reviewed; this round found the credential handling sound, with the residual root-user note at F10.
- **6.6** — unchanged and still accurate; the demonstration table still describes the throwaway Deployment rather than the real operator.
- **8.5** — confirmed. Worth re-reading against F8 before archive: the framework's own API now carries the declared type, but the *running* binary predates it.
