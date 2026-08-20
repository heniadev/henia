# Follow-up fixes from review

Deferred or blocked fixes from `reviews/impl-review.md`. A deferred fix leaves
an artifact here, not only a Decision note in the report.

## Closed

**Round 1 (nine findings)** — all fixed and applied to the cluster; see
`b181ab0` and `5893187`.

**Round 2 (ten findings)** — all fixed; see `7c1d139` and `14ba22b`. Every fix
that touches the cluster has been exercised on it:

- `devcontainer-verify-4` proved the non-root clone step can write the
  `local-path` PVC, the read-only workspace holds, the ServiceAccount token is
  absent, and the pull robot fetches the step image.
- `henia-build-3` ran the operator pipeline **as rewritten** and derived its own
  tag (`7c1d139`); the operator was redeployed from it, so the running binary
  embeds the current API types.
- The CEL guard was checked against the live CRD: `secretRef: {}` rejected, a
  named reference accepted, a Herd with no `repositories` rejected.

## Open

Nothing from either review round.

One item belongs to the change as a whole: **rotate the tachiko SSH key.** It
was pasted into a session transcript three times.
