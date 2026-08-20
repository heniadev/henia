# Follow-up fixes from review

Deferred or blocked fixes from `reviews/impl-review.md`. A deferred fix leaves
an artifact here, not only a Decision note in the report.

## Closed 2026-08-20

All four items originally queued here are done — see `b181ab0` and the
Decision fields in `reviews/impl-review.md`.

- **F5** — the `prometheus-henia-metrics` ClusterRoleBinding was read off the
  cluster, committed, and placed in the auto-deploy directory.
- **F1** — the CRD was re-applied; `herds.henia.dev` serves `repositories` and
  no longer serves `foo`. The sample Herd was recreated against the new schema.
- **F2** — a pull-scoped Harbor robot backs the `harbor-pull` Secret in
  `henia-system`, referenced by the Deployment. Verified: manifest GET 200,
  push attempt 401.
- **F3** — `PipelineRun devcontainer-verify-3` Succeeded; the pipeline is no
  longer unexercised code.

## Open

Nothing from the review. Two items belong to the change as a whole rather than
to any finding:

- **Push `feature/cluster-substrate`.** `origin` is well behind, which is why
  the verification pipeline cloned `81c527e` rather than the current tip. The
  `devcontainer/Dockerfile` it built is byte-identical to the local one, so the
  run is valid — but the next one should build the real tip.
- **Rotate the tachiko SSH key.** It was pasted into a session transcript.
