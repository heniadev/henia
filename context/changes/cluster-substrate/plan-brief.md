# Cluster Substrate — Operator, Build Path and Registry — Plan Brief

> Full plan: `context/changes/cluster-substrate/plan.md`

## What & Why

Finish roadmap **F-01 `cluster-substrate`** by putting Henia itself into the
cluster that `devserver-setup` built. F-01 says the framework *runs* in a
cluster, can *read* that cluster without changing it, and *exposes* its own
telemetry. The previous change delivered the reading and prepared the telemetry
against the platform; there was no framework to run. This change supplies it.

## Starting Point

k3s `v1.36.3+k3s1` on tachiko, healthy: HAProxy ingress, `local-path` storage
with a 200 GiB quota, Prometheus scraping the platform, a read-only identity
proven to be read-only, and a default-deny perimeter.

What is missing is everything needed to produce a running Henia: **no Go code**
(no `go.mod` in the tree), **no toolchain** (the devcontainer is `node:22-slim`
with no Go, kubebuilder, docker or make), **no registry**, and **no pipeline
engine**. Harbor and Tekton exist only on the older, unrelated cluster.

## Desired End State

An operator built by a pipeline inside its own cluster, from git, pushed to a
registry on the same machine, deployed with a `Herd` CRD registered,
supervised by k3s, emitting metrics the existing Prometheus scrapes, and
readable — never writable — by the devcontainer identity.

## Key Decisions Made

| Decision | Choice | Why | Source |
| --- | --- | --- | --- |
| Scaffold location | Add Go 1.26 + kubebuilder v4.15.0 to the devcontainer | `create api` is repeated as CRDs evolve, not run once | this planning |
| Build location | Tekton in-cluster on tachiko | The target architecture: config in git, engine reconciles | this planning |
| Builder | BuildKit rootless | kaniko is archived (last release 2025-05-23); BuildKit takes the same Dockerfile without a privileged pod | this planning |
| Registry | Harbor on tachiko, chart 1.19.2 | Self-contained; no dependency on the 2023-era cluster for pod starts | this planning |
| Tekton track | Current `v1.15.0` | Matches the version-currency argument that justified self-hosting | this planning |
| CRD group | `henia.dev` | Product-owned and actually held by the project | this planning |
| Kind | `Herd`, single kind | Declaration and running instance are `spec` and `status` of one object, not two kinds; `Herd` collides with nothing, where `Project` collides with OpenShift and `Repository`/`Source` with Flux and Knative | this planning |
| Operator depth | Scaffold + registered CRD, no reconciliation | Keeps F-01 a prerequisite; S-01 stays a user-visible slice | this planning |
| S-01 | Remains a separate roadmap slice | F-01 delivers the shape only | this planning |
| Trigger | Manual `PipelineRun`, direct deploy | Webhooks and reconciliation are S-03's stated outcome | this planning |
| FR-085 challenge | Closed | Operator decision: the running system is treated as the answer | this planning |
| Platform | Hetzner dedicated + k3s | Bare metal supplies the virtualisation `knest` needs | foundation |
| Storage | `local-path` | Already the recorded decision and the cluster default | foundation |

## Scope

**In:** Go toolchain in the devcontainer; kubebuilder scaffold and the `Herd`
API; Harbor; Tekton Pipelines; a build pipeline using BuildKit rootless; the
operator's CRD, RBAC and Deployment with probes and resource limits; metrics
scraped by the existing Prometheus; the read-only identity extended to the new
type.

**Out:** reconciliation logic (S-01); a second CRD for instances; Tekton Triggers and
webhooks (S-03); a GitOps reconciler (S-03); cert-manager and TLS; fixing the
`infra/tachiko/` copy-not-deployment gap; SSH hardening; off-box backups.

## Architecture / Approach

Toolchain → source → shipping infrastructure → the thing itself. One ordering is
forced: Go before scaffold, scaffold before a pipeline has anything to build.
Harbor precedes Tekton only because the pipeline's last step pushes to it.

Everything on the cluster is a declarative manifest in k3s's auto-deploy
directory, and every manifest is tracked under `infra/tachiko/` **in the same
commit that applies it** — the previous review caught that copy drifting on its
first edit, so the discipline is explicit rather than assumed.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1 · Devcontainer Go toolchain | Go 1.26 + kubebuilder in the image | A control-plane image grows a language toolchain |
| 2 · Operator scaffold | The generated tree and the `Herd` API | `<group>.<domain>` composition producing `henia.henia.dev` — permanent if missed |
| 3 · Harbor | A registry on the same machine | Weight: database, Redis and several services on a contention-limited box |
| 4 · Tekton Pipelines | The build engine, current track | Installing the LTS line by accident |
| 5 · Build pipeline | Image built in-cluster from git | Credential handling; unprivileged build actually staying unprivileged |
| 6 · Deploy the operator | Henia running and supervised | Contention — the first phase where limits genuinely matter |
| 7 · Telemetry | FR-270 demonstrated, not prepared | kubebuilder v4 protects metrics by default; scraping needs auth or a deliberate relaxation |
| 8 · Read-back | FR-085 against Henia's own resources | `view` does not cover new CRDs — the read-back silently sees nothing |

**Prerequisites:** none outstanding. `devserver-setup` is archived and its
cluster is healthy.

**Estimated effort:** several days. Phases 3 and 5 dominate; phase 2 is fast but
carries the one permanent mistake in the change.

## Open Risks & Assumptions

- **This change carries three foundations plus a product.** Registry, pipeline
  engine and toolchain would each be a change elsewhere. The infrastructure risk
  register already rates "operational effort displaces product work" High against
  a fixed date, and this is the concentration that risk describes. Recorded
  because it was chosen deliberately, with the alternative (a smaller F-01)
  offered and declined.
- **Resource contention becomes real here.** Harbor, Tekton and build pods land
  on the machine whose pre-mortem names contention as the likeliest failure. The
  operator sets limits from the start; nothing else installed so far does.
- **FR-085's Socratic challenge was closed by decision**, on the grounds that the
  implementation works. Worth stating plainly what that establishes and what it
  does not: it establishes that read-only access is *implementable* and useful;
  it does not establish that read-only is the *right* constraint, which is what
  the challenge would have examined. Roadmap Open Question #4 should be marked
  resolved-by-decision rather than resolved-by-analysis.
- **S-01 inherits a CRD it did not design.** `v1alpha1` exists so the shape can
  change, but a CRD version bump cannot be rolled back by `kubectl rollout undo`
  once resources are stored.
- **Harbor serves HTTP.** cert-manager is out of scope, so registry credentials
  and image pulls cross the network unencrypted inside the perimeter. Same
  residual as the Prometheus credential from the previous change.
- **Assumption:** the private-host module path `git.tobiko.kondi.net/kondi/henia`
  builds without network resolution, since the module is only ever built from
  inside its own repository.

## Success Criteria (Summary)

The devcontainer carries Go 1.26 and kubebuilder v4.15.0. `go build ./...`
succeeds on a generated tree whose CRD reads `henia.dev/v1alpha1`, kind
`Herd`. Harbor reports healthy and serves a pushed image. Tekton runs
`v1.15.0`. A `PipelineRun` builds and pushes the operator with no privileged
pod. The operator Deployment is `Available` with limits set, its pod returns
after deletion, and creating a `Herd` logs a reconcile. Prometheus reports the
operator `up` with `controller_runtime_reconcile_total` queryable. The read-only
identity lists `Herd` resources and is refused every write.
