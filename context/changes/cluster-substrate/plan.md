# Cluster Substrate — Operator, Build Path and Registry Implementation Plan

## Overview

Complete roadmap item **F-01 `cluster-substrate`** by putting the framework
itself into the cluster that `devserver-setup` built. F-01's outcome is *"the
framework runs in a cluster, can read the state of that cluster without being
able to change it, and exposes its own operational telemetry for collection"* —
`devserver-setup` delivered the middle clause and prepared the third against the
platform. This change delivers the first, and re-points the other two at real
Henia components.

Getting there requires three pieces of infrastructure that do not exist yet — a
container registry, a pipeline engine, and a Go toolchain — plus the operator
itself. That is a large change, and the concentration is recorded in the brief's
open risks rather than argued away.

## Current State Analysis

Probed directly on 2026-08-19.

**The cluster is running and healthy.** k3s `v1.36.3+k3s1` on
`tachiko.kondi.net` (88.99.160.8), node Ready. HAProxy ingress is the default
IngressClass, `local-path` the default StorageClass, Prometheus scrapes the API
server and kubelet, and `*.tachiko.kondi.net` resolves by wildcard DNS. The
perimeter is nftables default-deny with SSH open, the k3s API and the ingress
ports restricted to AS12912 prefixes, and Prometheus behind HAProxy basic auth.

**There is no product code.** No `go.mod` anywhere in the tree; the baseline
records 25 tracked files, none of them product code. The repository root holds
`context/`, `devcontainer/`, `infra/`, `docs/`, `content/` and `3rd_party/`.

**Nothing in reach can build a container image.** The devcontainer is
`node:22-slim` carrying kubectl, argocd, sops, tea, kubeconform, kustomize and
pre-commit — a control-plane image with no Go, no kubebuilder, no docker,
podman, buildah or make. tachiko has only k3s's embedded containerd.

**No registry and no pipeline engine on tachiko.** Harbor and Tekton both exist
on the *other* cluster at `10.242.0.10` — Harbor as ClusterIP services, Tekton
Pipelines at `v0.44.0` from 2023 — but that cluster is k3s v1.25, shared with
~20 unrelated applications, and out of scope here.

**The read-only identity cannot see custom resources.** `devcontainer/k8s/rbac.yaml`
binds `view` plus explicit cluster-scoped grants. The built-in `view` role only
aggregates CRDs carrying `rbac.authorization.k8s.io/aggregate-to-view: "true"` —
which is precisely why that file already carries an explicit grant block. A new
`Herd` CRD will be invisible to the identity until the same is done for it.

## Desired End State

A Henia operator built by a pipeline running inside its own cluster, from source
in git, pushed to a registry on the same machine, deployed with a `Herd` CRD
registered, supervised by k3s, emitting metrics that the existing Prometheus
scrapes, and readable — but not writable — by the devcontainer's identity.

### Key Discoveries:

- **kubebuilder composes the API group as `<group>.<domain>`.** `--domain
  henia.dev --group henia` would produce `henia.henia.dev`. Reaching
  `henia.dev/v1alpha1` means an empty group at `create api`. This is the single
  easiest thing to get permanently wrong in this change.
- **The declaration and the instance are one object, not two.** FR-460 says the
  framework "creates and configures that project's instance from the
  declaration", and FR-450 describes that instance running a loop over one or
  more repositories. Read as nouns these suggest two kinds; read as Kubernetes
  they are `spec` and `status` of a single resource. Deployment has no
  `DeploymentInstance`; Argo CD has `Application`, not Application plus
  ApplicationRun. A single `Herd` therefore carries the declared repositories in
  `spec` and the running instance's health in `status`, which also dissolves
  FR-450's grouping tension — a herd spans repositories by construction.
- **`Herd` collides with nothing.** Checked before adopting it: Artifact Hub
  (which indexes charts, operators and their CRDs) returns zero packages, and no
  CNCF or Kubernetes project defines the kind. By contrast `Project` collides
  with `project.openshift.io/v1`, verified in the OpenShift API source, and
  `Repository`/`Source` sit in crowded territory around Flux and Knative. The
  only namesake is Laravel Herd, a PHP development environment with no
  Kubernetes surface — search noise, not a clash. This matters because operators
  reach for `kubectl get he<TAB>`, where the API group does not disambiguate.
- **kaniko is archived** — last release v1.24.0 (2025-05-23), repository archived,
  no commits since June 2025. Rejected during planning in favour of BuildKit
  rootless, which consumes the same generated Dockerfile without a privileged
  pod.
- **Tekton has two live tracks**: current `v1.15.0` (2026-07-31) and LTS
  `v1.6.6` (2026-07-30). The infrastructure document names choosing accidentally
  as a risk; current is chosen deliberately.
- **The installed Prometheus is the plain chart, not kube-prometheus-stack**, so
  there are no ServiceMonitor CRDs. Scraping works through the
  `kubernetes-service-endpoints` job, which honours `prometheus.io/scrape`
  annotations on Services.
- **kubebuilder v4 serves metrics protected by authn/authz by default.** A
  scraper needs a token and RBAC, or the protection must be relaxed deliberately.
- **Harbor without TLS requires k3s to be told.** cert-manager is out of scope, so
  the registry serves HTTP; containerd will refuse it until
  `/etc/rancher/k3s/registries.yaml` declares it insecure.
- **Harbor chart 1.19.2 / app 2.15.2** (2026-08-03) is current; **kubebuilder
  v4.15.0** (2026-06-15) matches the stack hand-off, targeting Kubernetes 1.36
  and Go 1.26 with controller-runtime v0.24.1.

## What We're NOT Doing

- **Not implementing reconciliation logic.** The `Herd` controller is
  scaffolded and registers, but does not act on declarations — that behaviour is
  S-01 `project-declaration`, which stays on the roadmap as its own slice.
- **Not scaffolding a second CRD for instances.** Deliberate, and not merely
  deferred: the declaration and the running instance are one object, expressed as
  spec and status. See *Key Discoveries* — reinstating a second kind would be a
  reversal of this decision, not a continuation of it.
- **Not installing Tekton Triggers or a Gitea webhook.** Builds are started by
  hand. Auto-deploy-on-merge is S-03 `checks-and-reconcile`.
- **Not installing a GitOps reconciler** (Argo CD, Flux). Also S-03.
- **Not installing cert-manager or issuing TLS certificates.** Harbor and the
  metrics path stay HTTP inside the perimeter.
- **Not addressing the archived-copy problem in `infra/tachiko/`** — new
  manifests are tracked there, but nothing deploys from it. Queued from the
  previous change's review.
- **Not rotating the SSH key, hardening SSH, or adding off-box backups.**

## Implementation Approach

Build the toolchain, then the source, then the infrastructure that ships it,
then the thing itself. Each layer is verifiable before the next depends on it,
and the two heavyweight installs sit in the middle where a stall blocks least.

One ordering is forced: the Go toolchain must exist before anything can be
scaffolded, and the scaffold must exist before a pipeline has anything to build.
Harbor precedes Tekton only because the pipeline's final step pushes to it.

Everything on the cluster is delivered as declarative manifests in k3s's
auto-deploy directory, consistent with `devserver-setup`, and every manifest is
tracked under `infra/tachiko/` in the same commit that applies it — the previous
change's review found that copy drifting on its first edit, so the discipline is
stated here rather than assumed.

## Critical Implementation Details

- **API group composition.** `kubebuilder init --domain henia.dev`, then `create
  api` with an **empty** `--group`, yielding `henia.dev/v1alpha1` and kind
  `Herd`. Passing `--group henia` produces `henia.henia.dev`, which is a
  permanent, adopter-visible mistake — and it is what the infrastructure
  document's own worked example (`--group henia`) would produce.

  Verified against the pinned version rather than assumed —
  `pkg/model/resource/gvk.go` in kubebuilder v4.15.0:

  ```go
  func (gvk GVK) QualifiedGroup() string {
      switch "" {
      case gvk.Domain: return gvk.Group
      case gvk.Group:  return gvk.Domain   // empty group -> domain alone
      default:         return fmt.Sprintf("%s.%s", gvk.Group, gvk.Domain)
      }
  }
  ```

  So the empty group is a supported path, not a trick: the generated CRD, the
  `PROJECT` file and the RBAC markers all carry `henia.dev`. Phase 2's criterion
  2.4 asserts this on the generated output, because a wrong group is far cheaper
  to catch at scaffold time than after resources are stored.
- **Scaffold into a subdirectory and move up.** The repository root is not empty;
  kubebuilder refuses to scaffold into it. The stack hand-off records
  `subdir-then-move` for exactly this. Verify afterwards that nothing under
  `context/`, `infra/` or `devcontainer/` was overwritten.
- **The module path is a private host**: `git.tobiko.kondi.net/kondi/henia`. Go
  will attempt network resolution for it unless `GOFLAGS=-mod=mod` and the module
  is only ever built from within the repo. Do not add it as a dependency of
  itself.
- **Insecure registry.** `/etc/rancher/k3s/registries.yaml` must declare the
  Harbor endpoint before any pod can pull from it, and k3s must be restarted to
  read that file. Restarting k3s is safe — verified during the previous change —
  but it briefly interrupts the cluster.
- **Do not use `flush ruleset` if the firewall is touched.** The previous change
  found it wipes k3s's `iptables-nft` NAT tables. `infra/tachiko/etc/nftables.conf`
  is already corrected; any new rule must preserve the scoped-flush form.
- **`view` does not cover new CRDs.** The `Herd` CRD needs either the
  `rbac.authorization.k8s.io/aggregate-to-view: "true"` label or an explicit
  grant in `rbac.yaml`, or FR-085's read-back silently fails to see the very type
  this change adds.
- **BuildKit rootless still needs specific security settings** —
  `seccompProfile: Unconfined` or an equivalent, plus a writable state directory.
  It is unprivileged, not unconstrained.

## Phase 1: Devcontainer Go toolchain

### Overview

Give the development container the toolchain it lacks, so the operator can be
scaffolded and regenerated where the code is edited rather than through a
one-off ceremony.

### Changes Required:

#### 1. `devcontainer/Dockerfile`

Intent: add Go and kubebuilder without disturbing the existing tools. Contract:
Go **1.26** and kubebuilder **v4.15.0** on `PATH`, installed in the same
pinned-download style the file already uses for kubectl, sops, tea and
kustomize; `GOPATH`/`GOCACHE` land inside the image or a mounted cache, not in
the repository.

#### 2. `devcontainer/README.md`

Intent: record why a control-plane image now carries a language toolchain.
Contract: one short section naming the change that introduced it.

### Success Criteria:

The split below is deliberate and unusual: **the executor runs inside the very
container this phase rebuilds**, and has no container build tooling, so it cannot
verify anything that requires the rebuilt image. Only checks it can genuinely
perform are Automated; everything needing the rebuild is Manual, run by the
operator afterwards. Writing them the other way round would guarantee they are
closed on evidence that does not match their wording.

#### Automated Verification:

- The repository's Dockerfile linter (`droast`) reports no errors on the edited `devcontainer/Dockerfile`
- The pinned Go 1.26 and kubebuilder v4.15.0 download URLs resolve

#### Manual Verification:

- `go version` reports 1.26.x inside the rebuilt container
- `kubebuilder version` reports v4.15.0
- The previously present tools still resolve: `kubectl`, `tea`, `kustomize`, `sops`
- The rebuilt image builds from a clean context and the container starts with the repository mounted

## Phase 2: Operator scaffold

### Overview

Generate the kubebuilder project and the `Herd` API, and commit the generated
tree as the foundation everything later builds.

### Changes Required:

#### 1. kubebuilder project scaffold

Intent: create the operator skeleton in the idiomatic layout the stack
hand-off chose for its reviewability. Contract: `kubebuilder init --domain
henia.dev --repo git.tobiko.kondi.net/kondi/henia`, scaffolded in a subdirectory
and moved up; produces `PROJECT`, `go.mod`, `cmd/main.go`, `Makefile`,
`Dockerfile` and `config/`.

#### 2. `Herd` API and controller

Intent: register the type a person will declare, per FR-460, without
implementing what happens next. Contract: `kubebuilder create api` with an empty
group, version `v1alpha1`, kind `Herd`, with both resource and controller
generated; API group resolves to `henia.dev`. The reconciler logs and returns
without acting.

`spec` carries the declared repositories — one, several, or a monorepo, per
FR-450 — and `status` represents the running instance. The type is deliberately
singular: there is no companion `Instance` kind, because spec and status already
express that relationship.

#### 3. CRD discoverability

Intent: offset the one real cost of a distinctive name — `Herd` does not explain
itself. Contract: the CRD declares `categories: [henia]` so `kubectl get henia`
lists every Henia type, plus a shortName for typing. Both are set through
kubebuilder markers on the type, not by editing generated YAML.

#### 4. Generated manifests

Intent: keep generated artefacts in step with the types. Contract: `make
manifests generate` produces the CRD and RBAC under `config/`, and re-running it
leaves the tree unchanged.

### Success Criteria:

#### Automated Verification:

- `go build ./...` succeeds
- `go vet ./...` reports nothing
- `make manifests generate` produces no diff on a second run
- The generated CRD declares group `henia.dev`, version `v1alpha1`, kind `Herd`
- The CRD declares `categories: [henia]` and a shortName, and `kubectl get henia` resolves
- `PROJECT` records domain `henia.dev` and the private-host module path

#### Manual Verification:

- Nothing under `context/`, `infra/`, `devcontainer/`, `docs/` or `content/` was
  overwritten by the subdir-then-move step

## Phase 3: Harbor on tachiko

### Overview

Provide the registry the pipeline pushes to and the cluster pulls from, on the
same machine, so image delivery does not depend on the older cluster.

### Changes Required:

#### 1. Harbor HelmChart manifest

Intent: install declaratively through k3s auto-deploy, consistently with the
existing components. Contract: a `HelmChart` resource pinning chart **1.19.2**,
its own namespace, persistence on `local-path`, ingress on the `haproxy` class at
`harbor.tachiko.kondi.net`, HTTP only.

#### 2. Admin credential

Intent: avoid the chart's default password. Contract: a Secret created
out-of-band, referenced by the chart values, never committed.

#### 3. Harbor project and push robot account

Intent: give the pipeline somewhere to push and an identity narrower than admin.
Contract: a Harbor project named for the operator image, plus a robot account
holding push rights on that project only; its credential becomes the Secret
phase 5 references. Harbor does **not** create projects implicitly — a push to a
missing project is rejected, so this must exist before phase 5 runs.

#### 4. `/etc/rancher/k3s/registries.yaml`

Intent: allow containerd to pull from Harbor. Contract: the endpoint is Harbor's
**in-cluster Service** (read the name from the rendered release rather than
assuming it), not the public hostname, with TLS verification disabled; k3s
restarted so the file is read.

Using the public hostname would send every image pull out to the public IP and
back through HAProxy, making pulls depend on ingress routing, DNS and the host
firewall. That path works today only because ingress traffic is DNATed onto the
forward chain and never meets the input chain's AS12912 rule — an incidental
property, not a designed one, and one a future perimeter change would silently
break.

#### 5. Tracked copies under `infra/tachiko/`

Intent: keep the repository the source of truth. Contract: the manifest and
`registries.yaml` land in `infra/tachiko/` in the same commit that applies them.
The project and robot account are **not** tracked — they carry a credential.

### Success Criteria:

#### Automated Verification:

- Harbor pods reach `Ready`
- `/api/v2.0/health` reports all components healthy
- The Harbor project exists and the robot account can authenticate against it
- A test image can be pushed and pulled by digest using the robot credential
- `registries.yaml` names the in-cluster Service, is present on the host, and k3s has restarted since

#### Manual Verification:

- The Harbor UI is reachable at `harbor.tachiko.kondi.net` and the admin
  credential works

## Phase 4: Tekton Pipelines

### Overview

Install the pipeline engine that will build the operator, on the deliberately
chosen release track.

### Changes Required:

#### 1. Tekton Pipelines manifest

Intent: install the current track, pinned, not whatever `latest` resolves to.
Contract: Pipelines **v1.15.0** applied through k3s auto-deploy, in
`tekton-pipelines`.

#### 2. Tracked copy under `infra/tachiko/`

Intent: same source-of-truth discipline. Contract: the pinned manifest reference
is committed.

### Success Criteria:

#### Automated Verification:

- `tekton-pipelines-controller` and `-webhook` reach `Ready`
- The `Task`, `Pipeline`, `TaskRun` and `PipelineRun` CRDs are registered
- The deployed controller image tag is `v1.15.0`

#### Manual Verification:

- The installed track is confirmed as current, not the operator's LTS line

## Phase 5: Build pipeline

### Overview

Build the operator image inside its own cluster, from git, and push it to
Harbor — the first time Henia's own delivery path carries Henia.

### Changes Required:

#### 1. Pipeline and Task definitions

Intent: clone, build and push, unprivileged. Contract: a `Pipeline` with a
git-clone step against `git.tobiko.kondi.net/kondi/henia` and a BuildKit
**rootless** build consuming the kubebuilder-generated `Dockerfile`, pushing to
Harbor; a workspace PVC on `local-path`.

**The revision is an explicit parameter, not a default.** `lessons.md` binds this
work to a branch merged by pull request, so while this change is in flight the
operator source exists on `feature/cluster-substrate` and **not** on `main`. A
clone with no ref would take the default branch and build a tree containing no
operator — failing as though the Dockerfile were broken. The parameter defaults
to the working branch and switches to `main` when the PR merges.

**Images are tagged with the short commit SHA** of the revision built. This is
the value phase 6 consumes, it matches how Progress items already record SHAs,
and it means a deployment names exactly one build rather than a floating tag that
silently changes underneath it.

#### 2. Credentials

Intent: give the pipeline the two identities it needs, no more. Contract: a
Gitea read credential for clone and a Harbor push credential, both as Secrets
created out-of-band, referenced by ServiceAccount, never committed.

#### 3. Manual run procedure

Intent: make the build repeatable without a webhook. Contract: a documented
`PipelineRun` invocation with the image tag as a parameter.

### Success Criteria:

#### Automated Verification:

- A `PipelineRun` completes successfully end to end
- The built image is present in Harbor under the expected repository and tag
- No pod in the pipeline runs with `privileged: true`
- The image runs: `docker run`-equivalent via a throwaway pod prints the
  operator's `--help` or version

#### Manual Verification:

- The pipeline definition is reviewed for credential handling — no secret values
  in the committed YAML

## Phase 6: Deploy the operator

### Overview

Put the built image into the cluster with its CRD and RBAC, and demonstrate that
k3s supervises it — FR-470 against a real Henia component rather than a
throwaway Deployment.

### Changes Required:

#### 1. CRD and RBAC

Intent: register the type and give the controller only what it needs. Contract:
the generated CRD applied; a ServiceAccount, Role and binding from `config/rbac`,
scoped to `herds.henia.dev` and the resources the controller actually touches.

#### 2. Operator Deployment

Intent: run the operator under the supervision convention already recorded.
Contract: a Deployment pulling from Harbor with an image pull secret, liveness
and readiness probes wired to the scaffold's health endpoints, and resource
requests and limits set — the infrastructure risk register rates contention the
top risk on this machine.

The image reference is the **short-SHA tag produced by phase 5**, never `latest`
or a branch name: the Deployment must name one immutable build, so that what is
running can be traced back to a commit.

#### 3. Supervision demonstration

Intent: verify FR-470 against the real component. Contract: deleting the
operator pod produces an automatic replacement; a failing liveness probe
restarts the container.

### Success Criteria:

#### Automated Verification:

- The operator Deployment reports `Available`
- The `Herd` CRD is registered and `kubectl explain herd` resolves
- Creating a `Herd` custom resource succeeds and the controller logs a reconcile
- A deleted operator pod is replaced and reaches `Running`
- The operator has resource requests and limits set

#### Manual Verification:

- `context/foundation/supervision-convention.md` still describes what the cluster
  actually does, now that a real instance is supervised

## Phase 7: Telemetry (FR-270)

### Overview

Make the operator's own metrics visible to the collector that
`devserver-setup` stood up — turning FR-270 from prepared into demonstrated.

### Changes Required:

#### 1. Metrics exposure

Intent: publish the operator's telemetry for an external collector, as FR-270
requires. Contract: the controller-runtime metrics endpoint stays protected by
the scaffold's default authn/authz, and Prometheus is given the credential to
read it — its ServiceAccount is bound to the kubebuilder-generated
metrics-reader ClusterRole, and the scrape carries that token.

The protection is **not** relaxed. The previous change's most severe finding was
an unauthenticated metrics surface; turning authn off here would reopen that
class one change later, inside the cluster instead of outside it. If the
annotation-driven `kubernetes-service-endpoints` job cannot carry a per-target
bearer token, add a static scrape config for this one target rather than
removing the protection.

#### 2. Scrape configuration

Intent: use the mechanism the installed Prometheus actually has. Contract: the
metrics Service carries `prometheus.io/scrape` annotations so the plain chart's
`kubernetes-service-endpoints` job discovers it — there are no ServiceMonitor
CRDs on this cluster.

### Success Criteria:

#### Automated Verification:

- The operator appears as an `up` target in Prometheus
- `controller_runtime_reconcile_total` is queryable and non-empty after a
  `Herd` is created
- Go runtime metrics for the operator process are present

#### Manual Verification:

- The operator's metrics are visible in the Prometheus UI alongside the platform
  targets

## Phase 8: Read-back (FR-085)

### Overview

Close F-01's middle clause against the framework itself: the devcontainer
identity must see the operator and its resources, and must still be unable to
change anything.

### Changes Required:

#### 1. `devcontainer/k8s/rbac.yaml`

Intent: extend the read-only identity to the new type without widening it.
Contract: `get`/`list`/`watch` on `herds.henia.dev` — either by an explicit
grant block, matching the pattern already in that file, or by labelling the CRD
`rbac.authorization.k8s.io/aggregate-to-view: "true"`. No verb outside
`get`/`list`/`watch` appears anywhere in the file.

#### 2. Read-back verification

Intent: prove FR-085 holds for Henia's own resources, not only platform ones.
Contract: the identity reads `Herd` resources and operator state, and is
denied every write.

### Success Criteria:

#### Automated Verification:

- The read-only identity lists `Herd` resources across namespaces
- Creating or deleting a `Herd` as that identity is denied with 403
- The identity reads the operator Deployment and its pod status
- Reading Secret contents is still denied

#### Manual Verification:

- The read-only claim is re-checked end to end and F-01's outcome statement is
  agreed as satisfied

## Testing Strategy

This change introduces the project's first Go code, so testing splits in two.

**Generated code carries generated tests.** kubebuilder scaffolds a controller
test suite using envtest. The commitment made here is narrow and deliberate:
the suite must compile and run, proving the toolchain and the API types are
coherent. Writing meaningful reconciliation tests is not in scope, because there
is no reconciliation logic to test — that belongs with S-01.

**Everything else is verification of live state**, as in `devserver-setup`:
querying the API server, Harbor's health endpoint, Prometheus targets, and RBAC
denials. The negative tests matter most — phase 8's 403s are the only thing that
actually demonstrates FR-085, and a phase that proves only reads would not have
tested it.

Smoke artefacts (test images, throwaway `Herd` resources) are removed after
use.

## Performance Considerations

This change roughly doubles the resident workload on a machine whose top
registered risk is resource contention. Harbor alone brings a database, Redis and
several services; Tekton adds a controller and webhook; each build spawns pods
that consume CPU and disk in bursts.

Three consequences shape the plan: the operator Deployment sets requests and
limits from the start rather than after the first incident; build workspaces land
on `local-path`, inside the 200 GiB project quota already enforced, so a runaway
build cannot fill the root filesystem; and Prometheus retention stays modest
because Harbor's storage now competes for the same spindles.

## Migration Notes

Nothing is migrated. Three forward obligations are created:

**The devcontainer image changes.** Anyone running it must rebuild after phase 1,
or `kubebuilder` and `go` will be missing.

**Images become a dependency.** Once the operator runs from Harbor, a Harbor
outage prevents pod restarts from pulling. On a single node with
`imagePullPolicy: IfNotPresent` the cached image survives, but a node rebuild
does not.

**S-01 inherits a designed CRD.** `project-declaration` will implement behaviour
against a type it did not design. If S-01's requirements demand a different
shape, the CRD is `v1alpha1` precisely so it can change — but stored resources
must then be considered, and the infrastructure document already notes that a
CRD version bump cannot be rolled back by `kubectl rollout undo`.

## References

- `context/archive/2026-08-19-devserver-setup/plan.md` — the substrate this
  builds on
- `context/archive/2026-08-19-devserver-setup/reviews/impl-review.md` — findings
  that shape this plan, especially the tracked-copy drift and the flush hazard
- `context/foundation/roadmap.md` — F-01, and S-01 which stays separate
- `context/foundation/prd.md` — FR-085, FR-270, FR-450, FR-460, FR-470
- `context/foundation/tech-stack.md` — kubebuilder, Go, the subdir-then-move note
- `context/foundation/infrastructure.md` — platform decisions and risk register
- `context/foundation/supervision-convention.md` — FR-470's answer, to be
  re-checked against a real instance
- `context/foundation/lessons.md` — binding rules: conventional branch prefixes,
  Gitea ticket sync at commit time, worktrees for concurrent agents
- `devcontainer/k8s/rbac.yaml` — the read-only identity phase 8 extends

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Devcontainer Go toolchain

#### Automated

- [x] 1.1 `droast` reports no errors on the edited `devcontainer/Dockerfile` — 34f444a
- [x] 1.2 The pinned Go 1.26 and kubebuilder v4.15.0 download URLs resolve — 34f444a

#### Manual

- [ ] 1.3 `go version` reports 1.26.x inside the rebuilt container
- [ ] 1.4 `kubebuilder version` reports v4.15.0
- [ ] 1.5 `kubectl`, `tea`, `kustomize` and `sops` still resolve
- [ ] 1.6 The rebuilt image builds from a clean context and the container starts with the repository mounted

### Phase 2: Operator scaffold

#### Automated

- [x] 2.1 `go build ./...` succeeds — 2604250
- [x] 2.2 `go vet ./...` reports nothing — 2604250
- [x] 2.3 `make manifests generate` produces no diff on a second run — 2604250
- [x] 2.4 The generated CRD declares group `henia.dev`, version `v1alpha1`, kind `Herd` — 2604250
- [ ] 2.5 The CRD declares `categories: [henia]` and a shortName, and `kubectl get henia` resolves
- [x] 2.6 `PROJECT` records domain `henia.dev` and the private-host module path — 2604250

#### Manual

- [ ] 2.7 Nothing under `context/`, `infra/`, `devcontainer/`, `docs/` or `content/` was overwritten

### Phase 3: Harbor on tachiko

#### Automated

- [x] 3.1 Harbor pods reach `Ready` — 9c0f4eb
- [x] 3.2 `/api/v2.0/health` reports all components healthy — 9c0f4eb
- [x] 3.3 The Harbor project exists and the robot account can authenticate against it — 9c0f4eb
- [x] 3.4 A test image can be pushed and pulled by digest using the robot credential — 9c0f4eb
- [x] 3.5 `registries.yaml` names the in-cluster Service, is present on the host, and k3s has restarted since — 9c0f4eb

#### Manual

- [ ] 3.6 The Harbor UI is reachable and the admin credential works

### Phase 4: Tekton Pipelines

#### Automated

- [x] 4.1 `tekton-pipelines-controller` and `-webhook` reach `Ready` — 0e3ee4a
- [x] 4.2 The `Task`, `Pipeline`, `TaskRun` and `PipelineRun` CRDs are registered — 0e3ee4a
- [x] 4.3 The deployed controller image tag is `v1.15.0` — 0e3ee4a

#### Manual

- [ ] 4.4 The installed track is confirmed as current, not the operator's LTS line

### Phase 5: Build pipeline

#### Automated

- [x] 5.1 A `PipelineRun` completes successfully end to end — 6676f58
- [x] 5.2 The built image is present in Harbor under the expected repository and tag — 6676f58
- [x] 5.3 No pipeline pod runs with `privileged: true` — 6676f58
- [x] 5.4 The built image executes in a throwaway pod — 6676f58

#### Manual

- [ ] 5.5 The pipeline definition is reviewed for credential handling

### Phase 6: Deploy the operator

#### Automated

- [ ] 6.1 The operator Deployment reports `Available`
- [ ] 6.2 The `Herd` CRD is registered and `kubectl explain herd` resolves
- [ ] 6.3 Creating a `Herd` resource succeeds and the controller logs a reconcile
- [ ] 6.4 A deleted operator pod is replaced and reaches `Running`
- [ ] 6.5 The operator has resource requests and limits set

#### Manual

- [ ] 6.6 The supervision convention still describes what the cluster actually does

### Phase 7: Telemetry (FR-270)

#### Automated

- [ ] 7.1 The operator appears as an `up` target in Prometheus
- [ ] 7.2 `controller_runtime_reconcile_total` is queryable and non-empty
- [ ] 7.3 Go runtime metrics for the operator process are present

#### Manual

- [ ] 7.4 The operator's metrics are visible in the Prometheus UI

### Phase 8: Read-back (FR-085)

#### Automated

- [ ] 8.1 The read-only identity lists `Herd` resources across namespaces
- [ ] 8.2 Creating or deleting a `Herd` as that identity is denied with 403
- [ ] 8.3 The identity reads the operator Deployment and its pod status
- [ ] 8.4 Reading Secret contents is still denied

#### Manual

- [ ] 8.5 F-01's outcome statement is agreed as satisfied
