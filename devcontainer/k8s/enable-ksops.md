# Enabling SOPS decryption for Argo CD (KSOPS)

Operator-run, one-time, cluster-wide. Not something this project's own sync
flow owns — `argocd-repo-server` is shared with every other Application on
this cluster (see `context/deployment/deploy-plan.md` §5). Confirmed via the
devcontainer's read-only `kubectl` on 2026-07-10: **not currently applied**
— `argocd-repo-server` has no KSOPS init container/volumes, and `argocd-cm`
has no `kustomize.buildOptions`. Every `secret.enc.yaml` this project commits
will silently fail to decrypt at sync time until these steps are done.

Run all of this from your own kubectl context with cluster-admin (or at
least write access to the `argocd` namespace) — the devcontainer's identity
is read-only by design and cannot apply any of it.

## 1. Generate an age keypair

[age](https://github.com/FiloSottile/age) is the simpler SOPS backend
(vs. GPG) and what KSOPS' own docs lead with.

```bash
age-keygen -o age.agekey
```

Keep `age.agekey` off-repo — same rule as `devcontainer/creds.yaml` and
`devcontainer/kubeconfig.yaml`. Note the `# public key: age1...` comment
`age-keygen` prints; that public key is what goes into this project's
`deploy/.sops.yaml` recipient list later (not part of this cluster-wide
step).

## 2. Store the private key as a Secret in `argocd`

```bash
kubectl create secret generic sops-age \
  --namespace argocd \
  --from-file=keys.txt=age.agekey
```

## 3. Patch `argocd-repo-server` to install KSOPS

Apply `ksops-repo-server-patch.yaml` (next to this file) as a strategic
merge patch:

```bash
kubectl patch deployment argocd-repo-server -n argocd \
  --patch-file devcontainer/k8s/ksops-repo-server-patch.yaml
```

This adds an init container that copies the `ksops`/`kustomize` binaries
from the `viaductoss/ksops` image into a shared `emptyDir`, mounts them onto
`argocd-repo-server`'s `$PATH`, mounts the `sops-age` Secret at
`/.config/sops/age/keys.txt`, and sets `SOPS_AGE_KEY_FILE` so `sops` finds it
without relying on `$HOME`/`$XDG_CONFIG_HOME` defaults.

Verified 2026-07-10 (client-side, read-only — `kubectl patch ... --dry-run
=client`) that this patch merges cleanly against the live
`argocd-repo-server` Deployment: the new init container sits alongside the
existing `copyutil` one, the new volumes/mounts sit alongside the existing
`ssh-known-hosts`/`tls-certs`/etc, nothing gets clobbered. `securityContext.
readOnlyRootFilesystem: true` on that container is not a problem — the
`subPath` mounts land on top of `/usr/local/bin/*`, which is a volume mount,
not a write to the image's own read-only layer.

**Version-sensitive, and this cluster runs an old Argo CD** — the running
`argocd-repo-server` image is `quay.io/argoproj/argocd:v2.5.4` (Nov 2022),
not current. Confirm the KSOPS image tag and mount paths against
[viaductoss/ksops](https://github.com/viaductoss/ksops)'s README for
compatibility with v2.5.4 specifically before trusting the pinned
`v4.3.2` tag in the patch file blindly — KSOPS' Argo CD integration steps
have shifted across both projects' releases since this cluster's Argo CD was
installed.

## 4. Enable exec plugins in `argocd-cm`

KSOPS is a Kustomize exec plugin — Argo CD's repo-server needs both flags on
to load it:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-alpha-plugins --enable-exec"}}'
```

## 5. Restart `argocd-repo-server`

ConfigMap changes aren't picked up by running pods automatically:

```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
```

## 6. Verify

From the devcontainer (read-only, no changes needed here — this now works
because `rbac.yaml` already grants read on `Deployment`/`ConfigMap`):

```bash
kubectl get deployment argocd-repo-server -n argocd -o yaml | grep -i ksops
kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.kustomize\.buildOptions}'
```

The first should show the init container and volume mounts from step 3; the
second should print `--enable-alpha-plugins --enable-exec`. Full end-to-end
proof only comes once this project's own `deploy/db/secret.enc.yaml` (or
any `secret.enc.yaml`) exists and an Application syncs it successfully
instead of erroring on `ksops-generator.yaml` — that's still pending on the
`deploy/` scaffold this repo hasn't built yet.
