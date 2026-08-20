# tachiko — host and cluster configuration

Source of truth for the configuration of `tachiko.kondi.net` (88.99.160.8), the
Henia project cluster: Ubuntu 26.04 on Hetzner dedicated hardware running k3s
`v1.36.3+k3s1`.

Added in response to review finding **F3** of `devserver-setup`. The plan for
that change committed to an explicit architectural decision — *"the cluster's
contents are reproducible from files rather than from a sequence of typed
commands"* — but the files existed only on the machine, so the configuration was
declarative in form and unreproducible in substance. The only record was prose
inside commit messages, on a box whose disk the infrastructure risk register
rates Medium-likelihood of failing inside nine weeks.

Paths below mirror their location on the host, so where a file belongs is
obvious from where it sits here.

## Contents

| Path | Purpose |
| --- | --- |
| `etc/nftables.conf` | The host perimeter. Default-deny input; SSH world-open by decision; ingress ports and the k3s API both restricted to the AS12912 set |
| `etc/systemd/system/as12912-refresh.{service,timer}` | Weekly regeneration of that set |
| `usr/local/sbin/refresh-as12912-set.sh` | Fetches AS12912's announced prefixes from RIPEstat and reloads the set in place |
| `var/lib/rancher/k3s/server/manifests/haproxy-ingress.yaml` | HAProxy ingress via k3s auto-deploy, chart pinned `1.53.0` |
| `var/lib/rancher/k3s/server/manifests/prometheus.yaml` | Prometheus via k3s auto-deploy, chart pinned `29.27.0` |
| `var/lib/rancher/k3s/server/manifests/prometheus-henia-metrics-rbac.yaml` | ClusterRoleBinding letting Prometheus read the operator's protected metrics endpoint |
| `var/lib/rancher/k3s/server/manifests/harbor.yaml` | Harbor registry via k3s auto-deploy, chart pinned `1.19.2`, Trivy disabled |
| `etc/rancher/k3s/registries.yaml` | containerd registry config — points at Harbor's **in-cluster Service**, not the public hostname |
| `var/lib/rancher/k3s/server/manifests/tekton-pipelines.yaml.source` | Tekton Pipelines pin (version, URL, sha256) — the 1.6 MB manifest itself is not vendored |

## Deliberately not tracked here

- **`/etc/nftables.d/as12912.nft`** — generated weekly by the refresh script from
  live BGP data. Tracking it would produce churn that says nothing, and a stale
  committed copy would be actively misleading. The script that produces it *is*
  tracked, which is the part that matters.
- **`/etc/rancher/k3s/k3s.yaml`** and any kubeconfig — they carry credentials.
- **The k3s install invocation itself.** Recorded in the phase 3 commit of
  `devserver-setup`; not yet expressed as a file. See the caveat below.
- **Filesystem quota setup** (ext4 `project`/`quota` features, `prjquota` in
  `/etc/fstab`, project 1000 on the local-path directory). This is machine state
  established in a Hetzner rescue boot, not a file that can be applied. The
  procedure lives in phase 1 of the plan.
- **The `/etc/hosts` entry mapping `harbor-core.harbor.svc` to Harbor's
  ClusterIP.** containerd runs on the host and does not use cluster DNS, so the
  in-cluster registry name needs resolving there. Not tracked because the
  ClusterIP is environment state, not configuration — but note it is **not**
  stable across a Harbor reinstall, so if the Service is recreated the entry must
  be updated or every image pull fails.
- **Harbor's admin password and the `robot$henia+pipeline` credential** — held in
  Kubernetes Secrets and in root-only files on the host (`/root/harbor-admin.txt`,
  `/root/harbor-robot.txt`).

## Caveat — this is a copy, not a deployment mechanism

Nothing yet deploys *from* this directory. The files were captured off the
running host, so the two will drift the moment someone edits the box directly.
That is a real weakness, and a half-adopted version of this is worse than none,
because a stale directory looks authoritative.

Until a deployment path exists, treat the rule as: **edit here, copy to the
host, reload.** Reload commands, for reference:

```
nftables    sudo nft -f /etc/nftables.conf          # verify with: nft -c -f first
systemd     sudo systemctl daemon-reload
k3s         auto-deploy watches the manifests directory; no action needed
```

Closing that gap — making this directory the thing that actually configures the
machine — is not covered by any current change.
