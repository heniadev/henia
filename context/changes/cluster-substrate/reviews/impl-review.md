<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Cluster Substrate — Operator, Build Path and Registry

- **Plan**: `context/changes/cluster-substrate/plan.md`
- **Scope**: whole plan — all 8 phases, 43 of 43 Progress items checked. Third round; round 1 at `git show dfc64fc:…/reviews/impl-review.md`, round 2 at `git show d0b57ac:…/reviews/impl-review.md`
- **Date**: 2026-08-20
- **Diff basis**: Progress SHAs. All 28 commits in `main..HEAD` carry the change's `<type>(cluster-substrate):` subject convention and the merge-base range coincides exactly with the change. This round concentrates on `d0b57ac..HEAD` — `7c1d139`, `14ba22b`, `d4f7409` — plus an exhaustive audit of `hack/verify.sh`, which produced a false-PASS finding in two of the three rounds.
- **Verdict**: REWORK REQUIRED
- **Findings**: 1 critical, 5 warnings, 4 observations

## Verdicts

| Dimension | Verdict |
| --- | --- |
| Plan Adherence | WARNING |
| Scope Discipline | PASS |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | FAIL |

Round 2's ten findings are closed and verified, most of them on the cluster rather than on the page: the CEL guard rejects `secretRef: {}` on the live CRD, the read-only workspace and the non-root clone step both ran green, `tekton-build` pulls with the pull robot, and the operator runs an image its own pipeline derived a tag for. Every one of the plan's 23 Changes Required items has an artifact; no exclusion is violated.

The verdict is driven by a single finding, and it is not a regression — it has been latent since phase 2. **A success criterion that has been checked since `2604250` is false**, and the harness written to catch exactly this class passes it by running a different command than the plan names. That is a Success Criteria FAIL, and one FAIL is REWORK REQUIRED regardless of the rest.

## Findings

### F1 — Criterion 2.3 is false: `make manifests generate` dirties the tree

- **Severity**: 🔴 CRITICAL
- **Impact**: 🧠 HIGH
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:153`, `Makefile:52`, `api/v1alpha1/zz_generated.deepcopy.go:4`

**Detail**: Phase 2's criterion reads *"`make manifests generate` produces no diff on a second run."* Running it produces a diff.

`Makefile:52` invokes `object:headerFile="hack/boilerplate.go.txt",year=$(YEAR)`. `hack/boilerplate.go.txt` carries the literal `YEAR` placeholder, and the committed `zz_generated.deepcopy.go` reads `Copyright .` — the year-less output. Running the Makefile's own invocation rewrites the header to `Copyright 2026.`:

```
  committed:            Copyright .
  after make generate:  Copyright 2026.
  git status:           M api/v1alpha1/zz_generated.deepcopy.go
```

Criterion 2.3 is green only because `hack/verify.sh:153` regenerates *differently from the project* — it omits `year=`. `manifests` matches; `generate` does not.

The origin is recorded in `2604250`'s own commit message: `make` was missing from the image at scaffold time, so "kubebuilder's post-scaffold step failed and criterion 2.3 could not run as written", and idempotency was "verified by invoking the same controller-gen v0.21.0 the Makefile pins, directly". That workaround baked a year-less header into the tree, and every check since has repeated the workaround rather than the criterion — including `hack/verify.sh`, written two rounds ago specifically to stop criteria being answered by something other than what they say.

Nothing is broken at runtime: the header is a comment. What is broken is the criterion, and the check that was supposed to defend it.

**Fix A ⭐ Recommended** — regenerate with the Makefile's invocation, commit the result, and change `hack/verify.sh` to shell out to `make manifests generate` rather than reimplementing it.
- *Strength*: Makes the criterion true and makes the check test the thing the criterion names. A check that reimplements the command it verifies can always drift from it — that is the general defect, and this is the general fix.
- *Tradeoff*: `make` must be on PATH for 2.3 to run; where it is not, the check SKIPs instead of testing a近 approximation. It is in the image (`devcontainer/Dockerfile:22`, added by `2604250` for exactly this reason).
- *Confidence*: High. The divergence is two literal strings, and the diff was reproduced and restored.
- *Blind spot*: `YEAR` defaults to `$(shell date +%Y)`, so the committed header will read `2026` and a regeneration in 2027 will dirty the tree again — the criterion becomes time-dependent. Pinning `YEAR` in the Makefile would remove that, but changes a scaffold default the plan did not discuss.

**Fix B** — leave the tree, and change `hack/verify.sh` to assert what the project actually does.
- *Strength*: No generated churn; acknowledges that the year-less header is what the repo has always carried.
- *Tradeoff*: The criterion stays false while reporting green, which is the situation this finding is about.
- *Confidence*: High that it is safe; low that it is honest.
- *Blind spot*: None material.

**Decision**: PENDING

### F2 — Round 2's 3.2 fix reopened an empty-input false PASS, and split a sibling pair

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:240-248`

**Detail**: Before `7c1d139`, 3.2 read `[[ -n "$health" ]] && ! grep -q unhealthy`. The round-2 rewrite — mine, to make an unreachable Harbor SKIP rather than FAIL — dropped the non-empty guard. A 200 with an empty body (an ingress answering for a dead Harbor) now exits 0, leaves `health` empty, `grep -q` finds nothing in nothing, and 3.2 PASSes having inspected nothing.

The same rewrite also left 3.2 on `curl -fsS` while its sibling 3.6 deliberately dropped `-f` two checks later. With `-f`, any non-2xx collapses into the SKIP branch, so a 5xx from Harbor or a moved API path reports "unreachable" forever. Two checks against the same host, changed in the same commit, now disagree about what an HTTP error means.

**Fix ⭐** — restore the non-empty guard and drop `-f` from 3.2, matching 3.6: unreachable SKIPs, a definite HTTP error FAILs, an empty body FAILs.
- *Strength*: Restores what the fix removed and makes the pair consistent.
- *Tradeoff*: None.
- *Confidence*: High — both behaviours were reproduced.
- *Blind spot*: I did not check whether Harbor's health endpoint can legitimately return 2xx with an empty body under any condition.

**Decision**: PENDING

### F3 — Phase 7 never got the "unreachable is not failed" treatment

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:404-450`

**Detail**: With `PROM_AUTH` set and Prometheus down or the credential wrong, `prom` fails, `targets` is empty, the parser throws, and all four phase-7 checks report FAIL. Reproduced with `PROM_AUTH='x:y' PROM_URL='http://127.0.0.1:9'` → `FAIL 7.1 7.2 7.3 7.4`.

This is the third consecutive round in which this class appears. Round 1's F4 found criteria vanishing silently; round 2's F7 found 2.5/3.2/3.6 reporting FAIL for an unreachable dependency and fixed those three; phase 7 was not touched, and the round-2 commit states the principle in its own message — "unreachable is not unhealthy" — while leaving four checks that violate it.

It errs toward alarm, never toward false green. But a suite that cries wolf when the VPN is down is a suite people stop reading.

**Fix ⭐** — distinguish a parse/transport failure from a real answer, as 7.4's counting already does downstream: SKIP when `targets` is empty or unparseable, FAIL only on a parsed response that disagrees.
- *Strength*: Completes the sweep begun in round 2 and matches the commit's own stated rule.
- *Tradeoff*: A malformed-but-non-empty response would still SKIP rather than FAIL.
- *Confidence*: High.
- *Blind spot*: The distinction rests on `json.loads` throwing; a valid JSON error document from a proxy would parse and yield zero targets, which reads as FAIL.

**Decision**: PENDING

### F4 — The pipelines' own prerequisites omit the credential they now require

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Pattern Consistency
- **Location**: `deploy/tekton/README.md:13-18`

**Detail**: The prerequisites section says "**Both** Secrets live in `default`" and tables `gitea-auth` and `harbor-push`. Since round 2's F3, `tekton-build` names `harbor-pull` as its `imagePullSecrets`, and `devcontainer-start`'s step image is pulled from Harbor with it. `harbor-pull` is documented only in `infra/tachiko/README.md`.

Someone standing the pipelines up on a fresh cluster from this README gets `ImagePullBackOff` on the `start` task. That is precisely the failure mode round 2's F5 was raised about — fixed in the host README, reproduced one file over, in the document whose entire job is to list what must exist first.

**Fix ⭐** — add `harbor-pull` to the table and correct "Both" to "Three".
- *Strength*: One table; the credential's details already exist in `infra/tachiko/README.md` to copy from.
- *Tradeoff*: A third place naming the same Secret.
- *Confidence*: High.
- *Blind spot*: None material.

**Decision**: PENDING

### F5 — The non-root clone step cannot prune the trees earlier runs left, and says nothing

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Safety & Quality
- **Location**: `deploy/tekton/henia-operator-build.yaml:137-138`, `deploy/tekton/devcontainer-verify.yaml:124-125`

**Detail**: Round 2's F10 fix moved the clone step to uid 1000. The workspace PVCs still hold trees from `henia-build-1` and `henia-build-2`, which ran as uid 0 and left root-owned `0755` directories. `rm -rf` must write into a directory to unlink its contents; uid 1000 cannot, so those trees survive — and the prune ends in `2>/dev/null || true`, so nothing is reported.

Latent: the trees are about a day old and the prune only touches `-mtime +3`. The consequence is silent unbounded growth of a 10Gi and a 20Gi PVC on a single-node box whose risk register rates contention top, while `deploy/tekton/README.md` tells the reader trees are pruned after three days.

`rm -rf "$DEST"` is safe by contrast: `runId` is unique per run, and a collision would fail loudly under `set -eu`.

**Fix A ⭐ Recommended** — delete the pre-existing root-owned trees by hand once, and make the prune report what it could not remove instead of swallowing it.
- *Strength*: Fixes the actual backlog and stops the next instance being silent. The mixed-ownership situation is a one-off caused by the uid change.
- *Tradeoff*: A manual step on the host, and the prune gets noisier.
- *Confidence*: High on the mechanism, which was demonstrated; the trees themselves I have not deleted.
- *Blind spot*: Whether `local-path`'s directory really is 0777 at the root for both PVCs — the finding assumes the run directories, not the mount point, are the obstacle.

**Fix B** — set `fsGroup` on the PipelineRun pod template so every run's tree is group-writable.
- *Strength*: Structural; future ownership changes stop mattering.
- *Tradeoff*: Does not help the already-root-owned trees, and changes the pod template for both pipelines.
- *Confidence*: Moderate — I have not tested `fsGroup` against `local-path` here.
- *Blind spot*: Interaction with the read-only workspace on `devcontainer-start`.

**Decision**: PENDING

### F6 — Three plan sentences were superseded by better implementations and never amended

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW
- **Dimension**: Plan Adherence
- **Location**: `context/changes/cluster-substrate/plan.md` — phases 5 and 7

**Detail**: Round 2's F8 established that when the implementation knowingly departs from the plan's wording, the plan gets an amendment note rather than the implementation getting bent. Three sentences still lack one:

- **P5.2** — "both as Secrets created out-of-band, **referenced by ServiceAccount**". They are Task-level Secret volumes; round 2's F3 fix removed the ServiceAccount's `secrets:` list on correct Tekton grounds, moving further from the wording.
- **P5.3** — "a documented `PipelineRun` invocation **with the image tag as a parameter**". Round 1's F9 made the tag derived rather than passed, deliberately.
- **P7.2** — "the metrics Service carries `prometheus.io/scrape` annotations". A static scrape job is used instead, which phase 7's own escape clause authorises — but the contract sentence still says annotations, and no note records the choice.

Each is a better implementation than the sentence it contradicts. The defect is the silence, not the choice.

**Fix ⭐** — add amendment notes in the same shape as the auto-deploy one.

**Decision**: PENDING

### F7 — The telemetry path has not been re-verified since the operator was redeployed

- **Severity**: 📝 OBSERVATION
- **Impact**: 🔎 MEDIUM
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:404-450`

**Detail**: `14ba22b` rolled the operator to a new pod with a new IP. Prometheus's `endpoints` role should rediscover it, and criteria 7.1–7.3 were last confirmed before the redeploy. Nothing has checked since.

The harness cannot close the gap: 7.1–7.4 SKIP without `PROM_AUTH`, and the credential lives in a root-only file on tachiko. So FR-270 — one of F-01's three outcome clauses — currently rests on an inference about how Kubernetes service discovery behaves rather than on an observation, and `make verify` reports SKIP rather than telling anyone.

F3's fix would make this louder but not closable. Reaching Prometheus at its ClusterIP from the host closes it without the credential, as was done after `da23a3f`.

**Decision**: PENDING

### F8 — Five residual `verify.sh` weaknesses, none a false green

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:90-122`, `:158`, `:311-320`, `:59`

**Detail**: From an exhaustive per-check audit; all err toward FAIL or toward under-reporting, none toward a false PASS:

- **2.3 is blind to files regeneration creates.** `git diff --quiet -- api config` sees tracked content only; a new untracked artifact leaves it green. `git status --porcelain` would not.
- **1.1's error-detection branch is dead code.** `droast` exits 1 both when it reports errors and when it cannot read the file, so both land in the `else` reporting "droast exited non-zero" — the FAIL is right, the reason is wrong. Today's PASS is genuine: droast exits 0 with `0 error(s)`.
- **1.2 duplicates the pins it guards.** `1.26.7` and `v4.15.0` are hardcoded in the check while the pins live in `devcontainer/Dockerfile`. After a version bump the check keeps HEADing the old URLs and passes on something the image no longer downloads. Both URLs were confirmed to return 200 today, including the GitHub redirect.
- **5.1 counts any succeeded PipelineRun**, not the operator's. Round 2 chose to run the pipeline rather than tighten the check; the looseness survives.
- **`have_cluster` is true for a reachable API server with no RBAC**, which would make every phase FAIL rather than SKIP.

**Decision**: PENDING

### F9 — 5.3 blames the assertion when it cannot parse the file

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Success Criteria
- **Location**: `hack/verify.sh:327-343`

**Detail**: The Python probe exits 1 both when it finds `privileged: true` and when it throws on an unparseable file. The `else` branch reports "no privileged: true in the pipeline definition" either way, so a syntax error in a pipeline YAML is reported as a security assertion failing. Same shape as F1 — the check cannot distinguish "the answer is no" from "I could not ask" — and the fix is the same one applied to 5.5 in round 2.

**Decision**: PENDING

### F10 — A comment in `devcontainer-verify.yaml` refers to its own file in the third person

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW
- **Dimension**: Pattern Consistency
- **Location**: `deploy/tekton/devcontainer-verify.yaml:73-78`

**Detail**: The clone step's comment was copied verbatim from the sibling file and still reads "while `devcontainer-verify.yaml` argues explicitly that…" — inside `devcontainer-verify.yaml`. Cosmetic. Recorded because the two clone steps being otherwise byte-identical is the right outcome and worth keeping visible.

**Decision**: PENDING

## Automated Verification (re-run during review)

| Criterion | Command | Result |
| --- | --- | --- |
| 1.1 | `droast devcontainer/Dockerfile` | PASS — 0 errors |
| 1.2 | pinned Go and kubebuilder URLs | PASS — both 200 |
| 2.1, 2.2 | `go build ./...`, `go vet ./...` | PASS |
| 2.3 | via `make verify` | PASS — **but the criterion it names is false, see F1** |
| 2.4–2.7 | via `make verify` | PASS |
| 3.1, 3.2, 3.6 | via `make verify` | PASS — 3.2 has a reopened empty-body hole, see F2 |
| 4.1–4.4 | via `make verify` | PASS |
| 5.1, 5.3, 5.5 | via `make verify` | PASS |
| 6.1–6.5 | via `make verify` | PASS |
| 8.1–8.4 | via `make verify` | PASS |
| D1, D2 | via `make verify` | PASS — D1 confirms the cluster runs `7c1d139` |
| **Total** | `make verify` | **32 passed, 0 failed, 13 skipped** |

Independently of the harness: `go build`, `go vet` and a direct controller-gen regeneration are clean; the live Deployment runs `harbor-core.harbor.svc/henia/henia-operator:7c1d139` with `imagePullSecrets: harbor-pull` and reports Available; the live Tekton objects match the repository byte for byte (`harbor-pull`, no `secrets:`, `readOnly: true`, clone at uid 1000 with `HOME=/tmp`, both results surfaced); `bin/` is gitignored and no stale `Foo` reference survives.

7.1–7.3 were last verified before the operator was redeployed — see F7.

## Manual Verification

Eleven manual criteria, all checked. The audit is stronger than either previous round, and no rubber-stamping was found:

- **1.3, 1.4, 1.5** — machine-corroborated twice over: `devcontainer-verify-4`'s start task asserted `go1.26.7`, `kubebuilder v4.15.0` and every tool, with version assertions that can fail.
- **1.6** — closed by a human clean-context build and by two green pipeline runs. Architecture coverage is explicit: the pipeline proves **amd64**; arm64 rests on the manual build.
- **2.7** — solid, independently re-derivable, and its check now fails rather than passing vacuously on an unreachable commit.
- **3.6, 7.4** — the two that failed on first inspection and produced `81c527e` and `da23a3f`; both re-verified since.
- **4.4** — `v1.15.0`.
- **5.5** — reviewed three times now. Round 1 missed the credential-in-URL; round 2 fixed it; this round confirmed `HOME=/tmp` is not a regression — the file is 0600 in the step container's own layer, `/tmp` is not mounted from anywhere shared, and no other process runs in that container.
- **6.6** — unchanged and still accurate; the convention's demonstration table still describes the throwaway Deployment rather than the real operator, which is understatement rather than error.
- **8.5** — confirmed, and better supported than when it was first agreed: the framework's own API now carries the declared type and the running binary embeds it.
