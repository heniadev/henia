#!/usr/bin/env bash
# Launch Claude Code inside an isolated Docker container with this repo
# mounted as the workspace. See devcontainer/README.md for the security
# properties and limitations of this setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="str8t-devcontainer"
NETWORK_NAME="str8t-devcontainer-net"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not found on PATH." >&2
  exit 1
fi

# Always resolve to the *main* repo checkout, never whichever worktree this
# script happens to be invoked from — every concurrent instance mounts the
# same shared workspace; the agent decides which worktree (under
# .worktrees/) to actually work in once inside the container. Anchored on
# --git-common-dir (shared across all linked worktrees of one repo), not
# --show-toplevel (which returns the *invoking* worktree's own path).
GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -z "$GIT_COMMON_DIR" ]; then
  # git predates 2.31 (no --path-format flag) — a relative result from
  # `git -C "$SCRIPT_DIR" ...` is relative to $SCRIPT_DIR, not the caller's
  # cwd, so resolve it manually from there.
  RAW_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$RAW_COMMON_DIR" ]; then
    GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && cd "$RAW_COMMON_DIR" && pwd)"
  fi
fi

if [ -n "$GIT_COMMON_DIR" ]; then
  REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Concurrent-instance support (Gitea issue #10) is strictly opt-in — a bare
# invocation with DEVCONTAINER_INSTANCE unset must behave exactly as it did
# before this existed (see issue #10, comment #54): literal resource names,
# no registry entry, no extra ceremony. Setting DEVCONTAINER_INSTANCE=<name>
# opts into a distinct, independently addressable instance instead (its own
# port/database/$HOME volume — see later phases), registered here so
# devcontainer/cleanup.sh can list/remove it later. The registry lives under
# the shared REPO_ROOT resolved above, not $SCRIPT_DIR, so it's the same
# location regardless of which worktree's copy of this script is invoked.
INSTANCE_NAME="${DEVCONTAINER_INSTANCE:-}"
if [ -n "$INSTANCE_NAME" ]; then
  # Reused as a Docker volume name, a `docker run --name`, and a
  # double-quoted Postgres identifier — keep it simple and safe for all three.
  # SAFETY INVARIANT: this pattern is the *only* thing preventing SQL
  # injection into the psql calls below (no quotes/semicolons allowed) — if
  # this regex is ever loosened, the SELECT/CREATE DATABASE/DROP DATABASE
  # calls that interpolate INSTANCE_NAME (this file and cleanup.sh) need a
  # second look, since they have no other defense-in-depth.
  if ! [[ "$INSTANCE_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "DEVCONTAINER_INSTANCE must match ^[a-z][a-z0-9-]*\$ (lowercase letters, digits, hyphens, starting with a letter) — got '${INSTANCE_NAME}'." >&2
    exit 1
  fi

  INSTANCE_DIR="${REPO_ROOT}/.instances/${INSTANCE_NAME}"
  mkdir -p "$INSTANCE_DIR"
  [ -f "${INSTANCE_DIR}/created-at" ] || date -u +"%Y-%m-%dT%H:%M:%SZ" > "${INSTANCE_DIR}/created-at"
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "${INSTANCE_DIR}/last-used"
  echo "Instance mode: '${INSTANCE_NAME}' (registry: ${INSTANCE_DIR})" >&2
fi

# Per-instance $HOME volume, so a named instance's Claude Code session/
# config/caches persist independently of the legacy/bare instance's. The
# legacy/bare path keeps the literal volume name unchanged.
if [ -n "$INSTANCE_NAME" ]; then
  HOME_VOLUME="str8t-devcontainer-home-${INSTANCE_NAME}"
else
  HOME_VOLUME="str8t-devcontainer-home"
fi

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

if [ "$HOST_UID" -eq 0 ]; then
  echo "Refusing to run as host root — that defeats the point of a rootless devcontainer." >&2
  exit 1
fi

echo "Building devcontainer image..." >&2
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" >&2

# A user-defined network gives the container Docker's embedded DNS resolver
# (127.0.0.11, i.e. loopback) instead of whatever DNS server the default
# bridge network would hand it — which is sometimes a private-range address.
# That matters here specifically because the firewall below blocks private
# ranges as destinations; DNS needs to keep working regardless.
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME" >&2

# Local Postgres for testing/dev before commits (devcontainer/docker-compose.yml).
# Joins the network created above (declared `external: true` in the compose
# file) so the devcontainer can reach it by service name via Docker's
# embedded DNS. `--wait` blocks until its healthcheck passes, so nothing
# downstream races against a not-yet-ready database.
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required but not found." >&2
  exit 1
fi
echo "Starting local Postgres (devcontainer/docker-compose.yml)..." >&2
docker compose -f "$COMPOSE_FILE" up -d --wait postgres >&2

# In instance mode, each named instance gets its own logical database inside
# this one shared Postgres server/container/volume — Postgres has no native
# `CREATE DATABASE IF NOT EXISTS`, so existence has to be checked first. The
# legacy/bare path keeps using the default database docker-compose.yml
# already creates via POSTGRES_DB (str8t_dev), unchanged.
if [ -n "$INSTANCE_NAME" ]; then
  DATABASE_NAME="$INSTANCE_NAME"
  # SQL-safety here depends entirely on INSTANCE_NAME already having passed
  # the ^[a-z][a-z0-9-]*$ check above (no quotes/semicolons possible) — see
  # the SAFETY INVARIANT note at that validation site.
  DB_EXISTS="$(docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U app -d str8t_dev -tAc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}'")"
  if [ "$DB_EXISTS" != "1" ]; then
    echo "Creating Postgres database '${DATABASE_NAME}' for this instance..." >&2
    docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U app -d str8t_dev -c "CREATE DATABASE \"${DATABASE_NAME}\"" >&2
  fi
else
  DATABASE_NAME="str8t_dev"
fi

# The devcontainer's own outbound firewall (entrypoint.sh) blocks *new*
# connections to RFC1918 address space by default — which includes this
# sidecar's IP, since it lives on the same user-defined bridge network as
# the devcontainer. Punch a narrow /32 exception for it, the same mechanism
# already used for the k3s API server below (see ALLOWED_HOSTS_LIST).
# Resolved fresh every run rather than hardcoded, since compose can
# reassign the container's IP on recreation (e.g. after `down -v`).
POSTGRES_CONTAINER_ID="$(docker compose -f "$COMPOSE_FILE" ps -q postgres)"
POSTGRES_IP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${NETWORK_NAME}\").IPAddress}}" "$POSTGRES_CONTAINER_ID")"
ALLOWED_HOSTS_LIST=("${POSTGRES_IP}:5432")

RUN_ARGS=(
  --rm -it
  --network "$NETWORK_NAME"
  --cap-drop=ALL
  --cap-add=NET_ADMIN
  --cap-add=NET_RAW
  --cap-add=SETUID
  --cap-add=SETGID
  --security-opt no-new-privileges
  --pids-limit 512
  -e "TARGET_UID=${HOST_UID}"
  -e "TARGET_GID=${HOST_GID}"
  -e "DATABASE_URL=postgresql://app:app@postgres:5432/${DATABASE_NAME}"
  -v "${REPO_ROOT}:/workspace"
  -v "${HOME_VOLUME}:/home/agent"
  -w /workspace
)

# Named instances get an explicit container name (this is also what makes
# the name known *before* `docker run`, needed for the -v/-e args above —
# see Critical Implementation Details in the plan). The legacy/bare path
# passes no --name at all, identical to today (Docker auto-assigns one;
# irrelevant since --rm removes the container on exit).
if [ -n "$INSTANCE_NAME" ]; then
  RUN_ARGS+=(--name "str8t-devcontainer-${INSTANCE_NAME}")
fi

# Publish dev-server ports to the host. Needed regardless of the firewall —
# even with zero iptables rules, this Docker setup doesn't route the host
# directly into the container's bridge network (common for Docker Desktop /
# Rancher Desktop VM-backed setups on macOS); `-p` is what makes
# `localhost:<port>` on the host work. Space-separated; override with
# DEVCONTAINER_PORTS (default matches `npm run dev`'s Vite port).
#
# In instance mode, the *host* port may need to differ from the app's real
# listening port inside the container (another instance could already hold
# the default) — probe for a free one starting at the same number. The
# legacy/bare path keeps today's exact 1:1 host:container mapping.
find_free_host_port() {
  local candidate="$1"
  # Success means something's already listening there (connection succeeds);
  # failure (e.g. connection refused) means the port is free to publish on.
  while (echo >"/dev/tcp/127.0.0.1/${candidate}") 2>/dev/null; do
    candidate=$((candidate + 1))
  done
  echo "$candidate"
}

# Recorded as we go and passed into the container below (DEVCONTAINER_PORT_MAP)
# so an agent running *inside* the container — which has no way to introspect
# a `-p host:container` mapping from its own network namespace — can still
# answer "which host port am I actually reachable on" by reading one env var,
# in either mode.
PORT_MAP=""

if [ -n "$INSTANCE_NAME" ]; then
  for container_port in ${DEVCONTAINER_PORTS:-5173}; do
    host_port="$(find_free_host_port "$container_port")"
    RUN_ARGS+=(-p "${host_port}:${container_port}")
    echo "Publishing container port ${container_port} on host port ${host_port}." >&2
    PORT_MAP="${PORT_MAP}${PORT_MAP:+ }${container_port}:${host_port}"
  done
else
  for port in ${DEVCONTAINER_PORTS:-5173}; do
    RUN_ARGS+=(-p "${port}:${port}")
    PORT_MAP="${PORT_MAP}${PORT_MAP:+ }${port}:${port}"
  done
fi

RUN_ARGS+=(-e "DEVCONTAINER_PORT_MAP=${PORT_MAP}")

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  RUN_ARGS+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
else
  echo "Heads-up: ANTHROPIC_API_KEY is not set on the host." >&2
  echo "Claude Code will prompt you to log in inside the container instead" >&2
  echo "(that session persists in the '${HOME_VOLUME}' volume for next time)." >&2
fi

# Git credentials for working with the repo's remote from inside the
# container (a dedicated account, not the host user's own SSH keys/tokens).
# Sourced from devcontainer/creds.yaml (gitignored, never baked into the
# image — only passed as env vars at `docker run` time). Simple line-based
# parsing on purpose: the schema is fixed and flat (git.remote/username/password).
CREDS_FILE="$SCRIPT_DIR/creds.yaml"
if [ -f "$CREDS_FILE" ]; then
  GIT_REMOTE="$(sed -n 's/^[[:space:]]*remote:[[:space:]]*//p' "$CREDS_FILE" | head -n1)"
  GIT_USERNAME="$(sed -n 's/^[[:space:]]*username:[[:space:]]*//p' "$CREDS_FILE" | head -n1)"
  GIT_PASSWORD="$(sed -n 's/^[[:space:]]*password:[[:space:]]*//p' "$CREDS_FILE" | head -n1)"

  if [ -n "$GIT_REMOTE" ] && [ -n "$GIT_USERNAME" ] && [ -n "$GIT_PASSWORD" ]; then
    RUN_ARGS+=(
      -e "GIT_REMOTE=${GIT_REMOTE}"
      -e "GIT_USERNAME=${GIT_USERNAME}"
      -e "GIT_PASSWORD=${GIT_PASSWORD}"
    )
    echo "Git credentials loaded from creds.yaml for ${GIT_REMOTE} (user: ${GIT_USERNAME})." >&2
  else
    echo "creds.yaml found but missing remote/username/password — skipping git credential setup." >&2
  fi

  # External research MCP servers (see devcontainer/README.md "External
  # research MCP"). Both are optional and independent of each other — each
  # service works anonymously/rate-limited without a key. .mcp.json (repo
  # root) references these by name via Claude Code's ${VAR} expansion, so
  # nothing here ever touches a config file with the key inline.
  EXA_API_KEY="$(sed -n 's/^[[:space:]]*exa_api_key:[[:space:]]*//p' "$CREDS_FILE" | head -n1)"
  CONTEXT7_API_KEY="$(sed -n 's/^[[:space:]]*context7_api_key:[[:space:]]*//p' "$CREDS_FILE" | head -n1)"

  if [ -n "$EXA_API_KEY" ]; then
    RUN_ARGS+=(-e "EXA_API_KEY=${EXA_API_KEY}")
    echo "Exa API key loaded from creds.yaml." >&2
  fi
  if [ -n "$CONTEXT7_API_KEY" ]; then
    RUN_ARGS+=(-e "CONTEXT7_API_KEY=${CONTEXT7_API_KEY}")
    echo "Context7 API key loaded from creds.yaml." >&2
  fi

  # Sentry MCP server (see devcontainer/README.md "Sentry MCP"), for
  # diagnostic-workflow lookups (search_issues / get_sentry_resource)
  # against this project's Sentry org. Unlike Exa/Context7 there's no
  # anonymous fallback tier — without a token the server starts but every
  # tool call fails auth, same "absent means unauthenticated, everything
  # else still works" shape as the git credentials above.
  SENTRY_ACCESS_TOKEN="$(sed -n 's/^[[:space:]]*sentry_access_token:[[:space:]]*//p' "$CREDS_FILE" | head -n1)"
  if [ -n "$SENTRY_ACCESS_TOKEN" ]; then
    RUN_ARGS+=(-e "SENTRY_ACCESS_TOKEN=${SENTRY_ACCESS_TOKEN}")
    echo "Sentry access token loaded from creds.yaml." >&2
  fi
fi

# Read-only Kubernetes access, if devcontainer/kubeconfig.yaml exists (see
# devcontainer/k8s/generate-kubeconfig.sh — generated from your real
# cluster, gitignored, never baked into the image). Mounted read-only at
# $HOME/.kube/config. Its `server:` host:port is also punched through the
# firewall as a narrow exception (see entrypoint.sh's ALLOWED_HOSTS) since
# it's typically a private-range address the agent otherwise couldn't reach.
KUBECONFIG_FILE="$SCRIPT_DIR/kubeconfig.yaml"
if [ -f "$KUBECONFIG_FILE" ]; then
  K8S_SERVER="$(sed -n 's/^[[:space:]]*server:[[:space:]]*//p' "$KUBECONFIG_FILE" | head -n1)"
  K8S_HOSTPORT="${K8S_SERVER#*://}"
  K8S_HOSTPORT="${K8S_HOSTPORT%%/*}"

  RUN_ARGS+=(
    -v "${KUBECONFIG_FILE}:/home/agent/.kube/config:ro"
  )
  ALLOWED_HOSTS_LIST+=("$K8S_HOSTPORT")
  echo "Read-only Kubernetes access loaded from kubeconfig.yaml (${K8S_SERVER})." >&2
fi

# Consolidated firewall exception list (see ALLOWED_HOSTS_LIST above) —
# always includes the Postgres sidecar, plus the k3s API server when
# kubeconfig.yaml is present. Space-separated, matching entrypoint.sh's
# `for entry in ${ALLOWED_HOSTS:-}` word-splitting parse.
RUN_ARGS+=(-e "ALLOWED_HOSTS=${ALLOWED_HOSTS_LIST[*]}")

CLAUDE_ARGS=()
if [ -n "${CLAUDE_SAFE_MODE:-}" ]; then
  echo "CLAUDE_SAFE_MODE set — starting with normal permission prompts (no --dangerously-skip-permissions)." >&2
else
  echo "Starting in YOLO mode (--dangerously-skip-permissions). Considered safe here because:" >&2
  echo "  - non-root target user (${HOST_UID}:${HOST_GID}) inside the container (root only runs the firewall setup, then drops privileges via gosu)" >&2
  echo "  - only this repo is mounted — nothing from ~/.ssh, cloud credentials, or other projects" >&2
  echo "  - outbound traffic to private/VPN address space is firewalled off (RFC1918, link-local, CGNAT) — internet access stays open" >&2
  echo "  - set CLAUDE_SAFE_MODE=1 to fall back to normal permission prompts instead" >&2
  CLAUDE_ARGS+=(--dangerously-skip-permissions)
fi

exec docker run "${RUN_ARGS[@]}" "$IMAGE_NAME" "${CLAUDE_ARGS[@]}" "$@"
