# Building the Henia operator

The operator image is built **inside its own cluster**, from git, and pushed to
the Harbor on the same machine. There is no webhook and no Tekton Trigger:
builds are started by hand. Auto-deploy-on-merge is S-03 `checks-and-reconcile`,
not this change.

`henia-operator-build.yaml` holds everything that can be tracked — the
`tekton-build` ServiceAccount, the workspace PVC, the `Task` and the `Pipeline`.

## Prerequisites (created out-of-band, never committed)

Both Secrets live in `default` and are referenced by name only:

| Secret | Type | Used by | Contents |
| --- | --- | --- | --- |
| `gitea-auth` | `Opaque` | clone step, mounted at `/gitea` | keys `username`, `password` — a Gitea identity with **read** access to `kondi/henia`. The password is stored **percent-encoded**; see below |
| `harbor-push` | `kubernetes.io/dockerconfigjson` | build step, mounted at `/harbor` | the Harbor **robot** credential holding push rights on the `henia` project only |

Neither is admin: the clone identity cannot write to the repository, and the
push identity cannot touch any Harbor project but `henia`.

**The Gitea password is percent-encoded in the Secret.** This is not obvious and
it has already cost one failed pipeline run: the original clone step interpolated
it into `https://user:pass@host`, which worked only because git decodes userinfo.
Handing the stored value to an askpass helper authenticates with the literal
encoded string and fails. The clone step therefore uses git's `store` credential
helper, which parses its file as a URL and decodes identically — so the secret
works as stored, while the credential stays out of argv, out of git's error
output and out of `remote.origin.url` on the shared workspace.

Apply the tracked objects once:

```sh
kubectl apply -f deploy/tekton/henia-operator-build.yaml
```

## Starting a build

Two parameters, both explicit:

- **`revision`** — the git ref to build. It is deliberately **not defaulted**.
  While a change is in flight the operator source lives on its feature branch;
  a clone with no ref would take the repository's default branch and build a
  tree containing no operator, failing as though the Dockerfile were broken.
- **`image`** — the fully qualified reference *including the tag*. The tag is
  the **short commit SHA** of the revision being built, so a running Deployment
  names exactly one build rather than a floating tag that changes underneath it.

The tag is **not** yours to supply. Pass the repository without one; the clone
step derives the tag from the revision it actually cloned and publishes it as a
Pipeline result. A short SHA computed from your own working copy can name a
commit the pipeline never built.

```sh
REV=feature/cluster-substrate                     # or main, once merged

kubectl create -f - <<YAML
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: henia-build-
  namespace: default
spec:
  pipelineRef:
    name: henia-operator
  taskRunTemplate:
    serviceAccountName: tekton-build
  timeouts:
    pipeline: 1h
  params:
    - name: revision
      value: ${REV}
    - name: image
      value: harbor-core.harbor.svc/henia/henia-operator
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: henia-build-workspace
YAML
```

Read back what was built:

```sh
kubectl -n default get pipelinerun <name> \
  -o jsonpath='{.status.results[?(@.name=="image")].value}'
```

Watch it:

```sh
kubectl -n default get pipelinerun -w
kubectl -n default logs -l tekton.dev/pipelineRun=<name> --all-containers -f
```

Each PipelineRun gets its own tree under the shared workspace, named after the
run (`$(context.pipelineRun.name)`, passed by the Pipeline). Trees older than
three days are pruned at the start of each clone, so the PVC does not grow
without bound and a concurrent run is never the one pruned.

The registry hostname is Harbor's **in-cluster Service**
(`harbor-core.harbor.svc`), not the public name — see
`infra/tachiko/etc/rancher/k3s/registries.yaml` for why, and for the insecure
(HTTP) declaration that lets containerd pull it.

## Verifying the devcontainer image (criterion 1.6)

`devcontainer-verify.yaml` builds `devcontainer/Dockerfile` the same way and
then runs the result with the cloned repository on the workspace mount.

The run is **two Tasks**, not one Task with three steps, and the split is
load-bearing: Tekton compiles a Task's steps into a single pod and the kubelet
pulls every step image at pod creation, so a step whose image is the one a later
step builds would deadlock on `ImagePullBackOff` before the build ran. The
`start` Task carries `runAfter: [build]`, so its pod is created only once the
image is in Harbor.

```sh
REV=feature/cluster-substrate

kubectl apply -f deploy/tekton/devcontainer-verify.yaml
kubectl create -f - <<YAML
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: devcontainer-verify-
  namespace: default
spec:
  pipelineRef:
    name: devcontainer-verify
  taskRunTemplate:
    serviceAccountName: tekton-build
  timeouts:
    pipeline: 1h
  params:
    - name: revision
      value: ${REV}
    - name: image
      value: harbor-core.harbor.svc/henia/devcontainer
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: devcontainer-verify-workspace
YAML
```

Two caveats it prints rather than hides:

- **Architecture.** The build runs on tachiko, so it exercises the Dockerfile's
  path for tachiko's architecture. A developer machine of a different
  architecture takes the other branch of every `dpkg --print-architecture` case
  in that file. The `start` step echoes `uname -m` so the run says which one it
  proved.
- **run.sh is not exercised.** The step runs the image with a mount; it does not
  reproduce `docker run` with bind mounts, added capabilities, the in-container
  firewall or the gosu privilege drop. Those are verified by using the
  devcontainer, which happens every session.

## Deploying what was built

The image tag is the one value the deployment consumes. Bump it in the tracked
kustomization so the repository names the build that is actually running:

```sh
kustomize edit set image controller="$(kubectl -n default get pipelinerun <name> \
  -o jsonpath='{.status.results[?(@.name=="image")].value}')"    # in config/manager
kustomize build config/default | kubectl apply -f -
```

Commit that bump with the change that produced the build. A tag in
`config/manager/kustomization.yaml` that disagrees with the running Deployment
is the drift this file exists to prevent.
