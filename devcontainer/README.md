# devcontainer

> [!WARNING]
> **Inherited document — verify before acting on it.** This file arrived with
> the devcontainer tree, grafted from another project, and describes
> infrastructure that does not exist in this repository: `deploy/`,
> `scripts/`, `.pre-commit-config.yaml`, `.githooks/`, a
> Prisma/Vite/React Router application, `course/` lesson references, and
> issue links to `kondi/shirabe.studio`. The sections on the container
> itself, the network firewall, and Kubernetes access do match the scripts
> here. Reconciliation is tracked as its own change; until then, check that
> any path this file names actually exists. See `JOURNEY.md`, 2026-08-17.

Runs Claude Code inside an isolated Docker container with only this repo
mounted in, so `--dangerously-skip-permissions` (YOLO mode) is a bounded
choice instead of handing the agent your whole machine. Background: see
`course/1/ai-powered-bootstrap-boilerplate-i-bezpieczna-praca-z-agentem.md`
("Dev container w praktyce").

## Usage

```bash
devcontainer/run.sh
```

Any arguments are forwarded to `claude` (e.g. `devcontainer/run.sh -p "..."`
for a headless run).

Set `ANTHROPIC_API_KEY` on the host to pass it through; otherwise Claude Code
prompts you to log in on first run inside the container, and that session is
kept in a named Docker volume (`henia-devcontainer-home`) so you
don't have to log in again next time.

Set `CLAUDE_SAFE_MODE=1` to start with normal permission prompts instead of
`--dangerously-skip-permissions`:

```bash
CLAUDE_SAFE_MODE=1 devcontainer/run.sh
```

## Reaching a dev server running inside the container

`run.sh` publishes `5173` (Vite's default, matching `npm run dev`) to the
same port on the host, so `localhost:5173` works from your Mac once the dev
server is running inside the container. Override with `DEVCONTAINER_PORTS`
(space-separated) if you need a different port or more than one:

```bash
DEVCONTAINER_PORTS="5173 3000" devcontainer/run.sh
```

If you're running a [named instance](#running-concurrent-instances)
alongside another one, the *host* port may not be `5173` — `run.sh` auto-
detects a free one and prints the mapping it picked. An agent working
inside the container can discover its own effective host port(s) by reading
`$DEVCONTAINER_PORT_MAP` (space-separated `container:host` pairs, e.g.
`5173:5174`), since a Docker `-p` mapping can't otherwise be introspected
from inside the container's own network namespace.

Two things that trip people up here:

- **The dev server has to bind `0.0.0.0`, not just `localhost`.** `-p` maps
  the host port to the container's own network interface — a server bound
  to `127.0.0.1` *inside* the container is only reachable via `docker exec
  ... curl localhost:5173`, never from outside it. For Vite, that's `--host`
  on the CLI (or `server.host: true` in `vite.config.ts` if you want it to
  default that way always).
- **The container's bridge IP (e.g. `172.18.0.2:5173`) is not reachable
  from the host directly, with or without our firewall.** This is a
  Rancher-Desktop/Docker-Desktop-on-macOS thing: the host isn't on the same
  network as the container's bridge — only the VM is. `docker exec` and
  other *containers* on the same Docker network can reach that bridge IP
  fine; your Mac can't, and `-p` is the standard way around that, not a
  workaround specific to this setup.

## Local database

`run.sh` brings up a local Postgres (`devcontainer/docker-compose.yml`) before
starting the devcontainer itself, so the app has something to develop and run
tests against without touching staging/production data. It's on the same
user-defined network (`henia-devcontainer-net`) the devcontainer
already joins, reachable at `postgres:5432` — `DATABASE_URL` is set to that
automatically. Credentials are fixed, non-secret local-dev defaults
(`app`/`app`), not sourced from `creds.yaml`: this is a throwaway local
database with no real data in it, so there's nothing to protect.

Two things worth knowing:

- **The devcontainer's own outbound firewall would otherwise block this.**
  entrypoint.sh's default-deny-private-ranges firewall (see
  [Network firewall](#network-firewall) below) doesn't distinguish "your
  LAN/VPN" from "a sidecar container on our own network" by default — both
  are RFC1918 destinations. `run.sh` resolves the Postgres container's actual
  IP after starting it and punches a narrow exception through
  `ALLOWED_HOSTS` for exactly that IP on port `5432`, the same mechanism used
  for the k3s API server below. This is re-resolved every run, not cached,
  since the IP can change if the container gets recreated.
- **To reset it**, `docker compose -f devcontainer/docker-compose.yml down -v`
  drops the named volume (`henia-devcontainer-pgdata`) — the next
  `run.sh` starts a fresh, empty database.

Also copy `.env.example` to `.env` (gitignored) and fill in `SESSION_SECRET`
before running `npm run dev` — `DATABASE_URL` alone isn't enough, the app's
`app/.server/config.server.ts` validates the full set at boot and exits with
a clear error otherwise. After `npm install`, run `npx prisma generate` once
(and again after any `prisma/schema.prisma` change) — Prisma's generated
client lands in `app/generated/prisma/` (gitignored, not committed) and
isn't produced automatically on install.

A [named instance](#running-concurrent-instances) gets its own logical
database on this same Postgres server/container/volume instead of the
default `henia_dev` — nothing extra to configure, `run.sh` creates
it automatically the first time that instance name is used.

## Running concurrent instances

By default, `devcontainer/run.sh` behaves exactly as described above —
one instance, fixed port/database/volume names, no extra ceremony. Set
`DEVCONTAINER_INSTANCE=<name>` to opt into a second (or third, ...) instance
that can run **concurrently** alongside it, against the same shared
workspace (every instance mounts the main repo checkout, not whichever
worktree happened to invoke `run.sh` — the agent decides which worktree
under `.worktrees/` to actually work in once inside the container):

```bash
DEVCONTAINER_INSTANCE=feature-x devcontainer/run.sh
```

`<name>` must be lowercase letters, digits, and hyphens (starting with a
letter) — it's reused as a Docker volume name, a container `--name`, and a
Postgres database name. A named instance gets:

- its own auto-detected host port (see [above](#reaching-a-dev-server-running-inside-the-container))
- its own Postgres logical database (see [above](#local-database))
- its own `$HOME` volume, so its Claude Code login/session is independent of
  any other instance's

Every named instance is tracked in a small registry (`.instances/<name>/` at
the main repo root, gitignored) so `devcontainer/cleanup.sh` can find it
later. The default/bare instance (no `DEVCONTAINER_INSTANCE` set) is never
registered — there's nothing to list or clean up for it.

```bash
devcontainer/cleanup.sh                # list registered named instances
devcontainer/cleanup.sh feature-x       # remove one (prompts for confirmation)
devcontainer/cleanup.sh feature-x --yes # remove one, skip confirmation
```

Removing an instance drops its Postgres database, removes its `$HOME`
volume, and removes its registry entry. It's safe to run at any time for an
instance whose container has already stopped.

## Git credentials

The container gets no access to your host's SSH keys or git credential
helper — that's the point of the isolation. To let the agent `git push`/
`git pull` against the repo's remote anyway, drop a **dedicated** account
(not your own) in `devcontainer/creds.yaml` (gitignored):

```yaml
git:
  remote: https://your-git-host/org/repo.git
  username: claude
  password: <token or password for that dedicated account>
```

`run.sh` reads this file and passes the values through as environment
variables at `docker run` time (never baked into the image). The container's
entrypoint (`entrypoint.sh`) registers them with git's own credential
subsystem (`git credential approve`) before starting Claude Code, and sets
`user.name`/`user.email` from the same account. If the file is absent, git
push/pull inside the container simply isn't authenticated — everything else
still works.

The same account also logs `tea` (Gitea's CLI, for issues/PRs/releases
beyond plain git push/pull) in as its default login, via `tea login add
--user --password` — deliberately *not* `--git-credentials`, since that
would register a second, redundant git-credential entry for the same host
on top of the one set up above.

## External research MCP

Before planning a slice with a real, unobvious domain/library decision to
make (e.g. `S-08`'s choice of a design-token/color-scale library, or which
image-processing package to adopt), the project's course workflow
(`course/2/research-i-implementacja-trudniejszy-stream-z-ai.md`) calls for
external research *before* `/10x-plan` — grounding the plan in verifiable,
current sources instead of the model's training-data memory. Two MCP
servers back that: **Exa** (agentic web search, tuned for technical-docs
queries) and **Context7** (live library docs — `resolve-library-id` →
`query-docs`, so a plan can cite "uses `createEmptyCard` and
`fsrs().next(card, rating)`" instead of a hallucinated API).

Both are registered project-wide in the repo's own `.mcp.json` (committed —
it holds no secrets, only `${EXA_API_KEY}`/`${CONTEXT7_API_KEY}` references
that Claude Code expands at runtime). That file was one of the absences this
document's warning named; it was created on 2026-08-20, so the Exa and
Context7 entries above are now true of this repository. The Sentry entry
described below is **not** registered — there is no Sentry-instrumented
application here to query. To use your own key instead of the
shared anonymous/rate-limited tier, add it to `creds.yaml` (gitignored,
same file as the git credentials above):

```yaml
mcp:
  exa_api_key: <key from dashboard.exa.ai/api-keys>
  context7_api_key: <key from context7.com/dashboard>
```

`run.sh` reads these the same way it reads the git credentials and passes
them through as `EXA_API_KEY`/`CONTEXT7_API_KEY` env vars at `docker run`
time — never baked into the image, never written to a config file. Either
key can be left blank; each service just falls back to its shared,
rate-limited anonymous tier.

No firewall changes are needed for this — `mcp.exa.ai` and
`mcp.context7.com` are ordinary public HTTPS endpoints, not private/VPN
address space, so the [firewall](#network-firewall) below already allows
them by default. Verify both are connected inside a session with `/mcp`.

## Sentry MCP

For the diagnostic workflow in
`course/3/debugowanie-z-ai-od-stack-trace.md` ("Sentry MCP — szczegóły
procesu diagnostycznego"): once the app has Sentry configured (see that
lesson's Deep Dive, adapted to this repo's React Router + Express stack —
`instrument.server.mjs`/`app/entry.client.tsx`/`app/entry.server.tsx`), the
`@sentry/mcp-server` package lets the agent query issues, stack traces, and
breadcrumbs (`search_issues` → `get_sentry_resource`) without leaving the
terminal, instead of clicking around the Sentry dashboard by hand.

Registered project-wide in `.mcp.json` (committed — holds no secret, only a
`${SENTRY_ACCESS_TOKEN}` reference) as a stdio server (`npx
@sentry/mcp-server@latest`), unlike Exa/Context7's `http` entries above.
Needs a real Sentry **User Auth Token** (created at
`sentry.io/settings/account/api/auth-tokens`, not an org-level token) with
at minimum the `org:read`, `project:read`, `team:read`, `event:read`
scopes — the read-only set `search_issues`/`get_sentry_resource` need.
There's no anonymous tier here, so add it to `creds.yaml` (gitignored, same
file as the credentials above) to use it at all:

```yaml
mcp:
  sentry_access_token: <token from sentry.io/settings/account/api/auth-tokens>
```

`run.sh` reads this the same way as the Exa/Context7 keys and passes it
through as a `SENTRY_ACCESS_TOKEN` env var at `docker run` time — never
baked into the image, never written to a config file. Left blank, the
server still starts but every tool call fails auth (same "absent means
unauthenticated, everything else still works" shape as the git credentials
above) — not a hard requirement to use the rest of the devcontainer.

No firewall changes are needed here either — `sentry.io` (and
`*.ingest.<region>.sentry.io`) are ordinary public HTTPS endpoints, not
private/VPN address space. Verify it's connected inside a session with
`/mcp`.

## Network firewall

*Outbound* traffic the container itself initiates toward private/VPN address
space is blocked; normal internet access stays open, and so does anything
*answering* a connection someone else started (e.g. a browser hitting a dev
server published from the container — see the section above). This is a
*different shape* of firewall than Anthropic's own reference (which
default-denies everything and allowlists specific domains) — it's
default-allow, deny-listing only new outbound connections toward the ranges
that would let the agent reach your LAN or VPN:

- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` — RFC1918 private ranges
- `169.254.0.0/16` — link-local
- `100.64.0.0/10` — CGNAT / shared address space (this is what Tailscale and
  similar VPNs commonly use — it's *not* RFC1918, easy to miss)

Specific private-range hosts that are actually needed (currently: the k3s
API server, see [Kubernetes access](#kubernetes-access) below) get a narrow
exception via `ALLOWED_HOSTS` — the exact `host` or `host:port`, not the
surrounding range.

Three implementation notes worth knowing if you touch this:

- **Direction matters, and destination address alone can't tell you
  direction.** The first version of this blocked *all* `OUTPUT` packets to
  those ranges — which also silently ate reply traffic for connections
  *others* initiated (a peer container, or the host via a published port),
  since replies leave through `OUTPUT` too. The fix uses connection
  tracking: `ESTABLISHED,RELATED` traffic is accepted unconditionally
  (regardless of destination range — it's a reply, not a new outbound
  connection), and only `NEW`-state connections get filtered by destination.
  That's what actually distinguishes "the agent is reaching out to my LAN"
  from "something reached the container and it's replying."
- **DNS still has to work.** The container runs on a dedicated user-defined
  Docker network (`henia-devcontainer-net`) instead of the default
  bridge, so it gets Docker's embedded DNS resolver on loopback (127.0.0.11)
  rather than whatever DNS server the default bridge network would hand it
  — which is sometimes itself a private-range address. Loopback is
  explicitly excluded from the block list for this reason.
- **Root only runs long enough to set the firewall up.** Setting `iptables`
  rules needs `NET_ADMIN`/`NET_RAW`, and dropping privileges cleanly needs
  `SETUID`/`SETGID` — all four are added back on top of `--cap-drop=ALL`.
  `entrypoint.sh` runs as root, configures the firewall, then hands off to
  `user-entrypoint.sh` as your host UID/GID via `gosu` (`--user` at
  `docker run` time can't be used here, since the firewall setup has to
  happen *before* privileges are dropped). Nothing from the repo or from
  Claude Code itself ever runs as root.

## Kubernetes access

Read-only. Deploys happen via git — you push, Argo CD (running in-cluster)
picks it up and applies it — the agent never gets `kubectl apply`/write
access to the cluster itself. What the container gets is `kubectl` (plus
`argocd` and `sops` CLIs, for inspecting Application sync state and
encrypted values respectively), standalone `kustomize` and `helm` CLIs (for
locally build-validating `deploy/` manifests — `kustomize build` and `helm
template` — before commit, beyond what `kubectl kustomize`'s built-in,
plugin-less subset can check), and a **separate, dedicated** identity bound
to the built-in `view` ClusterRole — get/list/watch on cluster objects,
deliberately excluding Secret *contents* — plus one extra grant: `view`
doesn't cover Argo CD's own CRDs (`Application`/`AppProject`/
`ApplicationSet`, in the `argoproj.io` group), since they aren't labeled
`aggregate-to-view`, so `rbac.yaml` adds a second ClusterRole/
ClusterRoleBinding pair with the same get/list/watch-only shape scoped to
just those three resources. That's what lets `kubectl get
applications.argoproj.io -A` (or `argocd app list`, once the CLI is logged
in) show sync/health status directly.

You generate this yourself, against your real cluster (this repo/session has
no cluster access to do it for you):

```bash
cd devcontainer/k8s
API_SERVER=https://<your-k3s-api>:6443 ./generate-kubeconfig.sh
```

Note on `kustomize` + KSOPS: `deploy/db/`, `deploy/storage/`, and
`deploy/app/` use a KSOPS `ksops-generator.yaml` exec plugin to decrypt
SOPS-encrypted Secrets at build time. Running `kustomize build` against
those directories locally requires the operator's own
`--enable-alpha-plugins --enable-exec` flags (deliberately non-default,
security-relevant — Kustomize's plugin system can execute arbitrary
binaries) — this container does not enable them by default, and doing so
requires the real decryption key the operator holds, not something baked
into this image. Without it, local validation is capped at `kubeconform`'s
static schema check over the unexpanded YAML; the real decrypted-and-
rendered build only happens at Argo CD sync time, in-cluster.

This applies `rbac.yaml` (Namespace + ServiceAccount + ClusterRoleBinding to
`view`, plus the ClusterRole/ClusterRoleBinding pair covering the Argo CD
CRDs) if not already applied, mints a ServiceAccount token (default
validity 10 years — long-lived on purpose so this is a set-and-forget step
rather than a recurring chore; override with `TOKEN_DURATION` if you'd
rather rotate more often, and re-run the script before it expires to
refresh), and writes `devcontainer/kubeconfig.yaml` (gitignored) — a
standalone kubeconfig scoped to just that identity, not a copy of your own.

`run.sh` picks it up automatically if the file exists: mounts it read-only
at `$HOME/.kube/config` inside the container, and — since a k3s API server
is typically a private-range address the firewall would otherwise block —
punches a narrow exception for exactly that `host:port` (not the surrounding
`/8`) through to the [network firewall](#network-firewall) above. No
kubeconfig file, no exception, no cluster access — same "absent means
skipped" pattern as `creds.yaml`.

## Anthropic's devcontainer guidance vs. this implementation

Anthropic's own recommendation for when `--dangerously-skip-permissions`
(YOLO mode) is acceptable boils down to three conditions (see
[code.claude.com/docs/en/devcontainer](https://code.claude.com/docs/en/devcontainer),
and the course lesson's paraphrase of it). Here's how this setup maps to
that guidance — matched, partial, or explicitly skipped:

| Anthropic guideline | This implementation | Status |
| --- | --- | --- |
| Agent runs as a non-root user | Container starts as root only to configure the firewall, then `entrypoint.sh` drops to your host UID/GID via `gosu` before running anything else; the script refuses to run at all if the host user is UID 0 | ✅ Met (different mechanism: root-then-drop via `gosu` instead of `--user` at `docker run` time — required so the firewall can be set up first, same end property) |
| Restricted network access (Anthropic's reference container ships an `init-firewall.sh` — default-deny iptables/ipset, allowlisted domains only) | Default-*allow* internet, default-*deny* private/VPN address space (RFC1918, link-local, CGNAT) via `iptables` — see "Network firewall" above | ✅ Met, different shape: deny-list of private ranges rather than allowlist of public domains. Simpler to get right (no domain/CDN churn to track) but doesn't stop the agent reaching arbitrary public hosts, only your LAN/VPN |
| Only the trusted repo + needed files are visible — no `~/.ssh`, no cloud credentials, no production databases | Only the repo root is bind-mounted, plus a dedicated named volume for Claude's own config; nothing else from the host filesystem | ✅ Met |
| Dropped/minimal Linux capabilities | `--cap-drop=ALL` plus exactly four added back: `NET_ADMIN`/`NET_RAW` (firewall setup) and `SETUID`/`SETGID` (`gosu`'s privilege drop) | ✅ Met — same four capabilities Anthropic's own reference needs for the equivalent firewall-then-drop pattern |
| VS Code Dev Containers integration (`devcontainer.json`) | Standalone bash script only, no editor integration | ❌ Out of scope — this was built as "a shell script that launches Claude Code in a rootless container," not an editor-integrated devcontainer |
| Session/config persistence across runs | Named Docker volume (`henia-devcontainer-home`) mounted at the container's `$HOME`, survives across `--rm` runs | ✅ Met |
| Credentials for the agent to act on the repo itself (push/pull) | Not part of Anthropic's baseline guidance. Our addition: a **dedicated** git account's credentials, loaded from a gitignored `devcontainer/creds.yaml`, registered via `git credential approve` inside the container — never your own SSH keys or host git credentials | ➕ Extension beyond the documented guidance |
| Cluster access (read-back state after a GitOps deploy) | Not part of Anthropic's baseline guidance. Our addition: a **read-only**, dedicated Kubernetes identity (`view` ClusterRole, no Secret contents) loaded from a gitignored `devcontainer/kubeconfig.yaml`, plus a narrow per-host firewall exception — see [Kubernetes access](#kubernetes-access). Writes to the cluster stay git-only (Argo CD), never `kubectl apply` from the agent | ➕ Extension beyond the documented guidance |
| `--dangerously-skip-permissions` only inside an isolated environment meeting the above | Default behavior of `run.sh` (opt out with `CLAUDE_SAFE_MODE=1`) | ✅ Met — bounded by filesystem isolation *and* network isolation from local/VPN resources; still not bounded against arbitrary public internet hosts (see the network row above) |

Two things worth internalizing from that table:

- **Not a Docker-rootless-daemon setup.** This doesn't require or configure
  `dockerd-rootless` on the host. "Rootless" here means the *container's own
  user* is non-root, which is the property that actually matters for
  containing an agent.
- **Still shares the kernel with your host**, like any container. It is
  isolation, not a hard security boundary against a determined kernel
  exploit — and the firewall only closes off your LAN/VPN, not the public
  internet, so a compromised agent process can still reach arbitrary public
  hosts. Treat it the same way the lesson treats permission policies: raises
  the cost of a mistake, doesn't zero it out.

## pre-commit hooks

Every commit in **every worktree** runs [pre-commit](https://github.com/pre-commit/pre-commit).
It is baked into the image (Python + a pinned `pre-commit`, installed at build
time because the runtime user is sudo-less) and enforced without any
per-worktree *hook* setup (though a fresh worktree still needs `npm install`
before the Node-based hooks can run — see the fresh-worktree caveat below).

**How enforcement works.** All worktrees share `/workspace/.git`. A committed
shim `.githooks/pre-commit` (which delegates to `pre-commit hook-impl`) is
pointed at by a *relative* `core.hooksPath` that `user-entrypoint.sh` sets
globally at every container start (`git config --global core.hooksPath
.githooks`). Because the path is relative, each worktree resolves it against its
own root and uses its own committed shim — so `main` and every `.worktrees/*`
are covered identically, and a brand-new worktree is protected the moment it's
created.

**Fresh-worktree caveat — Node hooks need `node_modules`.** The enforcement
*wiring* travels with every worktree automatically, but the project (local)
hooks invoke the toolchain via `node node_modules/<tool>` (the FUSE mount blocks
the `.bin` shims), resolved against the worktree root. A freshly
`git worktree add`-ed directory has no `node_modules`, so ESLint / Prettier /
`tsc` / Prisma / Vitest hooks fail with "Cannot find module" on any commit that
stages a matching file until you run `npm install` in that worktree (or share /
symlink one). Hooks are file-filtered, so a commit touching no TS / schema /
Dockerfile files still passes — but treat `npm install` as the one setup step a
new worktree needs before committing code.

**The hooks** (see `.pre-commit-config.yaml`):
- Generic hygiene + secrets: trailing-whitespace, end-of-file-fixer,
  check-yaml/json, merge-conflict/case-conflict, `detect-private-key`,
  large-file guard, a hard block on committing `.env` / `devcontainer/creds.yaml`,
  and `verify-enc-yaml-encrypted` (asserts every staged `*.enc.yaml` file
  actually contains a SOPS `ENC[`/`sops:` block, not just a filename that
  looks encrypted — see `scripts/check-enc-yaml-encrypted.sh`).
- Project (local): Prettier (`--check`), ESLint, `tsc` typecheck, `vitest
  related` (DB-guarded — see below), `prisma format --check` + `prisma
  validate`, `droast` on Dockerfiles, `build-prompt-test` (the promptfoo
  regression harness's own prompt-builder test), `baked-image-freshness`
  (content-hash-compares the pinned `review-runner`/`ci-checks` image tags
  against their baked source files), `prune-test` (the tekton-pruner
  CronJob's fixture-driven regression test), `check-enc-yaml-encrypted-test`
  (per-`---`-document regression test for the `verify-enc-yaml-encrypted`
  hook above), and `finalize-pre-commit-status-test` (fixture-driven test
  for the `ci/pre-commit` status-posting script, covering the
  trust-boundary/JSON-injection/symlink-exfiltration bugs
  `/10x-impl-review` caught across several rounds on kondi/shirabe.studio#63).
- k8s manifests (Tekton/Argo CD, live since kondi/shirabe.studio#63):
  `yamllint` + `kubeconform -ignore-missing-schemas`, scoped to `deploy/`
  and `devcontainer/k8s/`. `shellcheck` (via `shellcheck-py`, no system
  binary baked in) covers every `.sh` file under `deploy/`, `devcontainer/`,
  and `scripts/`.

**The test hook needs Postgres.** `vitest related` runs through
`scripts/precommit-related-tests.sh`, which probes the DB first: if the Postgres
sidecar is up it runs the related tests, otherwise it **skips with a message**
so a commit never fails merely because the DB is down. Run `npm test` before
pushing.

**Bypass.** Failing hooks block the commit. `git commit --no-verify` is the
documented emergency escape — but it is not authoritative: Tekton CI
(`deploy/tekton/pr-ci-pipeline.yaml`'s `ci/pre-commit`, live since
kondi/shirabe.studio#63) re-runs the identical checks on every PR so a
local bypass can't slip past review.

**Cache.** Fetched hook repos are cached under `PRE_COMMIT_HOME`
(`/home/agent/.cache/pre-commit`, inside the persisted volume), so only the
first commit in a brand-new volume pays the fetch.

**Blame.** The one-time baseline reformat (`.git-blame-ignore-revs`) is skipped
by `git blame` automatically inside the container — `user-entrypoint.sh` sets
`git config --global blame.ignoreRevsFile .git-blame-ignore-revs`. Outside the
container, run that command once to keep `blame` pointed at real authorship.
