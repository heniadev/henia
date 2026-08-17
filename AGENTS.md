# Repository Guidelines

str8t ("str-AI-tjacket") is a harness that confines an agent to read-only
Kubernetes access, making a Git commit reconciled by Argo CD the only write
path to a cluster. Today the repo holds the harness — devcontainer, RBAC,
the 101 skill toolkit — not an application.

## Ground Rules

- **`kubectl` is read-only by design.** Never run or propose `apply`,
  `edit`, `patch`, `delete`, or `create` against a cluster. The bound
  identity is `view` plus three get/list/watch-only ClusterRoles in
  `devcontainer/k8s/rbac.yaml`. Cluster changes go through a commit.
- **Never `git add -A` or `git add .`. Stage by name.**
  `devcontainer/creds.yaml` (git password, API key) and
  `devcontainer/kubeconfig.yaml` (ServiceAccount token, 10-year default
  validity) are live credentials in the working tree, ignored only since
  `.gitignore` was added 2026-08-17.
- **Append to `JOURNEY.md` whenever a decision, friction point, or dead end
  occurs** — the same day, not at phase end. Append only; never edit or
  delete a past entry. Entry format is in that file.
- **`devcontainer/README.md` is inherited from another project.** It cites
  `deploy/`, `scripts/`, `.pre-commit-config.yaml`, `.mcp.json`, `.githooks/`
  and a Prisma/Vite app — none exist here. Verify any path it names.
- Never write under `context/archive/`; open a change with `/101-new`.

## Project Structure

- `devcontainer/` — the container the agent runs in; `k8s/` holds RBAC and
  the kubeconfig generator.
- `context/` — 101 toolkit state: `foundation/` (outlives changes),
  `changes/<change-id>/` (in flight), `archive/` (read-only).
- `content/CFP.md` — the talk this project exists to produce.
- `docs/reference/contract-surfaces.md` — registry of load-bearing names;
  `/101-plan-review` scans plans against its `##` headings.
- `.claude/skills/` — the 101 skills; `HOWTO.md` is the pipeline map.

## Commands

- `devcontainer/run.sh` — start the agent container; args forward to
  `claude`. `CLAUDE_SAFE_MODE=1` restores permission prompts,
  `DEVCONTAINER_INSTANCE=<name>` runs a concurrent instance.
- `devcontainer/cleanup.sh` — list or remove named instances.
- `devcontainer/k8s/generate-kubeconfig.sh` — mint the read-only kubeconfig;
  needs `API_SERVER` and your own admin access to the cluster.

## Conventions

- Foundation documents are edited in place, never copied to a dated
  filename (`context/foundation/README.md`).
- No build, test, or lint tooling exists in this repo yet. Do not invoke
  commands that assume it.
