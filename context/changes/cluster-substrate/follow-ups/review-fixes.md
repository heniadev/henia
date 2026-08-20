# Follow-up fixes from review

Deferred or blocked fixes from `reviews/impl-review.md`. A deferred fix leaves
an artifact here, not only a Decision note in the report.

## F5 — track Prometheus's metrics-reader ClusterRoleBinding

- **Source**: `context/changes/cluster-substrate/reviews/impl-review.md`, finding F5
- **Fix**: read the live ClusterRoleBinding that authorises Prometheus's
  ServiceAccount against `henia-metrics-reader`, and commit it beside the scrape
  config in `infra/tachiko/var/lib/rancher/k3s/server/manifests/prometheus.yaml`.
- **Blocked on**: cluster access. The devcontainer identity cannot list
  ClusterRoleBindings, so the live shape cannot be read from here. Accepted by
  the operator; not deferred by choice.

## Cluster-side actions the applied fixes still need

The repository is correct; the cluster has not yet been changed to match.

- **F1** — re-apply the CRD so `herds.henia.dev` serves `repositories` instead of
  `foo`: `kustomize build config/default | kubectl apply -f -`. The existing
  `default/sample` Herd was created against the old schema.
- **F2** — create the `harbor-pull` Secret in `henia-system` (a read-scoped Harbor
  robot credential) and re-apply the Deployment. Until then the operator is still
  running only because its image is cached on the node.
- **F3** — run a `PipelineRun` of `devcontainer-verify` so the pipeline stops
  being unexercised code. That was the second half of the F3 decision.
