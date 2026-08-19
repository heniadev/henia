# Deferred review fixes — devserver-setup

Fixes identified during implementation review and deliberately not completed in
that session. Each entry names the finding, the outstanding work, and the report
it came from.

## F3 — make `infra/tachiko/` actually configure the machine

- **Source**: `context/changes/devserver-setup/reviews/impl-review.md`
- **Outstanding**: the directory is a captured copy, not a deployment mechanism.
  Nothing applies it, so the repo and the host will drift as soon as anyone edits
  the box directly. Needs a deploy path — at minimum a script that copies and
  reloads, at most reconciliation from git, which is what Henia itself is for.
- **Also missing from the captured set**: the k3s install invocation (recorded
  only as prose in the phase 3 commit) and the ext4 quota procedure (machine
  state established in a rescue boot, not an applyable file).
- **Why deferred**: choosing between "a copy script" and "real reconciliation"
  is a design decision, and the second overlaps what the product does — that
  belongs in planning, not in a review triage.

## F1 — verify the ingress block from outside AS12912

- **Source**: `context/changes/devserver-setup/reviews/impl-review.md`
- **Outstanding**: the 80/443 restriction is asserted from the rule text, not
  observed. Every vantage point available during review sits inside AS12912.
  Needs one check from elsewhere — `10.242.0.10` served this purpose for the
  6443 rule and timed out correctly.
- **Why deferred**: requires a vantage point the review session does not have.
