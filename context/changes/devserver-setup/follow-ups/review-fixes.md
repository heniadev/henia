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

## F6 — verify item 5.6 with an actual devcontainer restart

- **Source**: `context/changes/devserver-setup/reviews/impl-review.md`
- **Outstanding**: Progress item 5.6 reads "A devcontainer **restart** picks up
  the new kubeconfig and its firewall exception". It was checked on evidence
  from an already-running container — a `kubectl` call returning `403 Forbidden`
  on `nodes`, which proves authentication and RBAC but not the cold-start path.
  What remains untested is `run.sh` re-deriving the `ALLOWED_HOSTS` firewall
  exception from the new `server:` value in `kubeconfig.yaml`.
- **How to close it**: restart the devcontainer, then run `kubectl get pods -A`.
  Success there exercises the whole path; the item is then honestly checked.
- **Why deferred**: cannot be done from inside the container being restarted.

## F8 — reboot-test the scoped nftables flush

- **Source**: `context/changes/devserver-setup/reviews/impl-review.md`
- **Outstanding**: the `flush ruleset` → `delete table inet filter` fix was
  proven across a *reload* (KUBE-EXT stayed at 30). It has not been proven
  across a *reboot*, where the outcome depends on service ordering between
  `nftables.service` (sysinit.target) and `k3s.service` (multi-user.target)
  rather than on flush semantics.
- **How to close it**: reboot the host, then check
  `iptables -t nat -S | grep -c KUBE-EXT` is non-zero and the ingress answers.
- **Why deferred**: a reboot is a deliberate act with a demo date approaching,
  not something to slip into a review session.

## F1 — put TLS in front of the Prometheus credential

- **Source**: `context/changes/devserver-setup/reviews/impl-review.md`
- **Status of the parent finding**: closed. Prometheus is behind HAProxy basic
  auth; anonymous access returns 401, verified from off-box. The earlier plan to
  gate 80/443 in nftables was abandoned — DNAT means ingress traffic never
  reaches the `input` chain, and the `prerouting` alternative collided with the
  `flush ruleset` hazard (F8).
- **Outstanding**: there is no TLS, so the basic-auth credential crosses the
  network in clear text on every request. `cert-manager` is a declared exclusion
  of `devserver-setup`, so this was an accepted tradeoff, not an oversight.
- **How to close it**: when cert-manager is installed, add TLS to the Prometheus
  Ingress and rotate the credential — it should be assumed exposed, having
  travelled unencrypted until then.
- **Why deferred**: installing cert-manager is out of this change's scope, and
  the infrastructure research flags a version-ceiling conflict with Virtink
  (documented range v1.0–v1.8) that needs deciding first.
