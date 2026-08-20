# Follow-up fixes from review

Deferred or blocked fixes from `reviews/impl-review.md`. A deferred fix leaves
an artifact here, not only a Decision note in the report.

## Closed

- **Round 1** — nine findings, all fixed and applied to the cluster (`b181ab0`,
  `5893187`).
- **Round 2** — ten findings, all fixed and exercised on the cluster (`7c1d139`,
  `14ba22b`, `d4f7409`).
- **Round 3** — ten findings: eight fixed, two rejected by the operator as
  nitpicking (F1, the year-stamp in a generated header; F3, phase 7 reporting
  FAIL rather than SKIP for an unreachable Prometheus — neither yields a false
  green).

## Open

**One item, not urgent.** The workspace PVCs still hold trees from
`henia-build-1` and `henia-build-2`, which ran as uid 0 before round 2 moved the
clone step to uid 1000. The prune now runs as uid 1000 and cannot delete them.

- **Source**: round 3, finding F5.
- **Fix**: delete `henia-build-1` and `henia-build-2` from
  `henia-build-workspace` by hand, with cluster access.
- **Why it can wait**: the prune only touches trees older than three days and
  these are about a day old. The prune no longer swallows the failure — it now
  reports each directory it could not remove, with the owning uid — so if this
  is forgotten, the next run says so.

Also outstanding for the change as a whole: **rotate the tachiko SSH key.** It
was pasted into a session transcript four times.
