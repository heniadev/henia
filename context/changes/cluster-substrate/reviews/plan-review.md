<!-- PLAN-REVIEW-REPORT -->
# Plan Review: Cluster Substrate — Operator, Build Path and Registry

- **Plan**: `context/changes/cluster-substrate/plan.md`
- **Mode**: full
- **Date**: 2026-08-19
- **Verdict**: SAFE TO EXECUTE (as reviewed: NEEDS FIXES — all 6 findings applied to the plan on 2026-08-19)
- **Findings**: 0 critical, 6 warnings, 0 observations — 6 fixed, 0 pending

> Harness note: this skill's step 5 delegates code verification to a read-only
> subagent. This session runs under a standing instruction not to spawn
> subagents, so the riskiest claims were verified inline against the live
> cluster instead. The claims checked and their evidence are recorded in the
> findings below, so nothing rests on an unverified assertion.

## Verdicts

| Dimension | As reviewed | After triage |
| --- | --- | --- |
| End-state reachability | WARNING | PASS |
| Execution economy | PASS | PASS |
| Architectural fit | WARNING | PASS |
| Blind spots | WARNING | PASS |
| Document completeness | WARNING | PASS |

Derivation as reviewed: five dimensions, four WARNING, no FAIL, no CRITICAL →
**NEEDS FIXES**. The approach was never in question — the collapse to a single
`Herd` kind, the in-cluster build, and the phase ordering all held up; every
finding was a gap in carrying a known constraint through to a phase.

Derivation after triage: all six findings applied to `plan.md`, every dimension
`PASS` → **SAFE TO EXECUTE**. Both columns are kept deliberately. The left one is
what the review found and does not get rewritten by the repairs; the right one is
what an executor now picks up.

## Grounding

Grounding: 5/5 paths exist, symbols found — `devcontainer/Dockerfile`,
`devcontainer/README.md`, `devcontainer/k8s/rbac.yaml`, `infra/tachiko/`,
`context/foundation/supervision-convention.md`. The Dockerfile uses the pinned
download pattern phase 1 says to follow, and `rbac.yaml` contains the explicit
`claude-devcontainer-cluster-scoped-view` block phase 8 extends. Contract-surface
registry is present but holds no registered surfaces, so that scan flagged
nothing.

## Findings

### F1 — Nothing creates the Harbor project the pipeline pushes to

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — needs a decision, but a bounded one
- **Dimension**: End-state reachability
- **Location**: `plan.md` phase 3 (changes 1–4), phase 5 criterion 5.2
- **Detail**: Phase 5 asserts "the built image is present in Harbor under the
  expected repository and tag", but no step in phase 3 or 5 creates the Harbor
  *project* that repository lives in. Harbor does not auto-create projects on
  push; a push to a non-existent project is rejected. The plan therefore reaches
  phase 5, runs a pipeline that has already cloned and built, and fails at the
  final step — the most expensive place to discover it.
- **Fix**: add a change to phase 3 creating the Harbor project (and the robot
  account the pipeline pushes with), and a phase 3 criterion asserting the
  project exists. Phase 5's push credential then references that robot account
  rather than the admin credential.
  - **Benefit**: moves the failure from mid-pipeline to install time, where it
    costs a minute; also stops the pipeline holding admin credentials.
  - **Cost**: one more thing created out-of-band and not tracked in git, since
    it carries a credential.
  - **Confidence**: high on the mechanism — Harbor's project model is
    long-standing and the plan's own criterion already assumes a "repository"
    that must live somewhere.
  - **Blind spot**: not verified whether the chart's values expose project
    bootstrapping, which would let this be declarative instead of manual.
- **Decision**: FIXED (2026-08-19) — phase 3 gains change 3, "Harbor project and
  push robot account", stating explicitly that Harbor rejects pushes to a missing
  project so it must exist before phase 5. Two automated criteria added: the
  project exists and the robot authenticates, and the push/pull test now uses the
  robot credential rather than admin — so the phase also proves the pipeline's
  narrower identity works, not just that *some* credential does.

### F2 — The build pipeline has no git ref, and the source will be on a branch

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: End-state reachability
- **Location**: `plan.md` phase 5 change 1
- **Detail**: The contract says "a git-clone step against
  `git.tobiko.kondi.net/kondi/henia`" and names no revision. Meanwhile
  `context/foundation/lessons.md` binds this work to a branch: *"Branch per
  change, merged via pull request rather than committed to the default branch."*
  So when phase 5 runs, the phase 2 scaffold exists on `feature/cluster-substrate`
  and **not** on `main`. A clone with no ref takes the default branch and builds
  a tree with no operator in it — and the failure looks like a broken Dockerfile
  rather than a wrong ref.
- **Fix**: make the revision an explicit pipeline parameter, defaulted to the
  working branch for this change and switched to `main` once the PR merges.
  - **Benefit**: removes a guess the executor would otherwise make silently, and
    makes the branch-to-main transition a visible parameter change rather than a
    surprise.
  - **Cost**: the pipeline definition carries a branch name that is only correct
    during this change, which must be updated at merge.
  - **Confidence**: high — the lesson is binding and the plan is silent; these
    cannot both be satisfied without a decision.
  - **Blind spot**: not verified whether Gitea's clone credential has access to
    non-default branches, though it would be unusual not to.
- **Decision**: FIXED (2026-08-19) — phase 5 change 1 now states the revision is
  an explicit parameter rather than a default, names why (the binding
  branch-per-change lesson puts the scaffold on `feature/cluster-substrate`, not
  `main`), and records the failure mode it prevents: a no-ref clone builds a tree
  with no operator and fails as though the Dockerfile were broken. The
  branch→`main` switch at merge is now a visible parameter change.

### F3 — Phase 1's criteria cannot be checked by an executor inside the container being rebuilt

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Blind spots
- **Location**: `plan.md` phase 1, criteria 1.1–1.4
- **Detail**: All four automated criteria are phrased "inside the rebuilt
  container". The agent executing this plan runs *in* that container and cannot
  rebuild and re-enter itself; a `docker build` is not even available to it. As
  written, the phase's automated criteria are unverifiable by the party expected
  to verify them. This is the same shape as finding F6 of the previous change's
  implementation review, where item 5.6 named a devcontainer restart that never
  happened and was checked on narrower evidence.
- **Fix**: move 1.1–1.3 to Manual (operator-run after rebuild) and keep only a
  criterion the executor can genuinely satisfy — that the Dockerfile edit is
  syntactically valid and the pinned versions resolve.
  - **Benefit**: stops the phase from being closable on evidence that does not
    match its wording, which is exactly the rubber-stamp the review contract
    exists to catch.
  - **Cost**: phase 1 becomes mostly manual, so it cannot be driven unattended.
  - **Confidence**: high — this is a structural property of where the executor
    runs, not a judgement call.
  - **Blind spot**: not checked whether the harness exposes any container-rebuild
    affordance that would change this.
- **Decision**: FIXED (2026-08-19) — phase 1's criteria are re-split, and the
  reason is written into the phase so it does not read as an oversight: the
  executor runs inside the container being rebuilt and has no build tooling, so
  only checks it can genuinely perform stay Automated. Those are now the
  Dockerfile linter (`droast`, already in the image) and resolution of the pinned
  download URLs. Everything requiring the rebuilt image — `go version`,
  `kubebuilder version`, the surviving tools, and the build itself — moved to
  Manual for the operator. Phase 1 becomes mostly manual, which is the honest
  cost and is now visible in the plan rather than discovered at execution.

### F4 — Phase 7 leaves an either/or the executor must decide

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Document completeness
- **Location**: `plan.md` phase 7 change 1
- **Detail**: The contract reads "with the scaffold's default authn/authz
  protection **either** satisfied by a scrape credential **or** relaxed
  deliberately and recorded". That is an unresolved design decision, which the
  planning skill's own invariant forbids — and the two branches are not
  equivalent: one gives Prometheus a token and RBAC, the other exposes an
  unauthenticated metrics endpoint inside the cluster. The previous change's
  most severe finding was an unauthenticated metrics surface; leaving this open
  invites the executor to pick the easy branch under time pressure.
- **Fix**: decide it here. Given the operator's metrics are cluster-internal and
  the previous finding was about *external* exposure, granting Prometheus's
  ServiceAccount the metrics-reader role is the tighter option and costs one
  binding.
  - **Benefit**: keeps the "no unauthenticated telemetry" property the previous
    review established, rather than re-opening it one change later.
  - **Cost**: a token-based scrape config is slightly more setup than disabling
    protection.
  - **Confidence**: medium-high — kubebuilder v4 scaffolds a metrics-reader
    ClusterRole for exactly this, but the wiring to the plain Prometheus chart's
    annotation-based discovery was not tested.
  - **Blind spot**: whether the annotation-driven `kubernetes-service-endpoints`
    job can carry a bearer token per-target without a static scrape config.
- **Decision**: FIXED (2026-08-19) — the either/or is gone. Phase 7 now requires
  the metrics endpoint to stay protected and Prometheus's ServiceAccount to be
  bound to the generated metrics-reader ClusterRole. The plan states outright
  that protection is not relaxed, and names why: it would reopen the previous
  change's most severe finding one change later. The blind spot is answered in
  the plan rather than left open — if the annotation-driven job cannot carry a
  per-target token, the instruction is to add a static scrape config for that one
  target, not to remove the protection.

### F5 — The image tag contract between phases 5 and 6 is unstated

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — the fix is mechanical
- **Dimension**: Broken contract
- **Location**: `plan.md` phase 5 change 3, phase 6 change 2
- **Detail**: Phase 5 produces an image with "the image tag as a parameter";
  phase 6 deploys "pulling from Harbor" without saying which tag it references or
  how that value travels between the phases. Data flowing from an earlier step to
  a later one with no stated carrier is precisely the broken-contract shape this
  review looks for.
- **Fix**: state the tagging scheme in phase 5 (short commit SHA is the obvious
  choice, and matches how Progress items already record SHAs) and have phase 6's
  Deployment reference that exact tag rather than a floating one.
- **Decision**: FIXED (2026-08-19) — phase 5 declares images are tagged with the
  short commit SHA of the revision built; phase 6 requires the Deployment to use
  that tag and explicitly forbids `latest` or a branch name, so what is running is
  always traceable to one commit. The carrier between the phases is now named.

### F6 — `registries.yaml` endpoint is underspecified, and the public hostname routes through the ingress

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM
- **Dimension**: Architectural fit
- **Location**: `plan.md` phase 3 change 3, Critical Implementation Details
- **Detail**: The contract says only "the Harbor endpoint declared with TLS
  verification disabled". If that endpoint is `harbor.tachiko.kondi.net`, every
  image pull leaves the node, hits the public IP, is DNATed back through HAProxy,
  and depends on firewall behaviour that is incidental rather than designed.

  Verified during this review: the node *can* reach its own ingress today —
  `curl` from the host to `88.99.160.8:80` returns 401 from Prometheus's basic
  auth, so the request arrives. But it works only because ingress traffic is
  DNATed onto the forward path and never meets the input chain's AS12912 rule.
  The previous change attempted exactly such a prerouting gate; had it stayed,
  image pulls would have broken cluster-wide with no obvious connection to the
  firewall edit.
- **Fix**: point `registries.yaml` at Harbor's in-cluster Service
  (`harbor-core.harbor.svc`) rather than the public hostname.
  - **Benefit**: removes the dependency on the ingress, the firewall, DNS and the
    TLS story in one move — pulls never leave the node's network namespace, and a
    future perimeter change cannot silently break them.
  - **Cost**: the in-cluster name is not resolvable from outside, so pushing from
    anywhere other than an in-cluster pipeline needs the public hostname too;
    two names for one registry.
  - **Confidence**: high on the fragility, medium on the exact service name —
    the chart's service naming should be read from the rendered release rather
    than assumed.
  - **Blind spot**: not verified whether k3s's containerd resolves cluster DNS
    for registry endpoints, which is the one thing that would invalidate this fix.
- **Decision**: FIXED (2026-08-19) — phase 3 change 4 now requires the in-cluster
  Service as the registry endpoint, explicitly not the public hostname, and says
  to read the service name from the rendered release rather than assume it. The
  reasoning is written into the plan, including that the public-hostname path
  works today only because ingress traffic is DNATed past the input chain. The
  blind spot stands and is now load-bearing: if containerd cannot resolve cluster
  DNS for registry endpoints, this fix fails and the public hostname returns as
  the fallback — so phase 3's criterion asserts the endpoint *and* a successful
  pull, which would catch it.

