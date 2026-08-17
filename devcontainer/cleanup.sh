#!/usr/bin/env bash
# List or remove named devcontainer instances (see devcontainer/run.sh's
# DEVCONTAINER_INSTANCE opt-in, Gitea issue #10). The legacy/bare instance
# is never registered here and this script never touches it.
#
# Usage:
#   devcontainer/cleanup.sh                 # list registered instances
#   devcontainer/cleanup.sh <name>           # remove one, with confirmation
#   devcontainer/cleanup.sh <name> --yes     # remove one, no confirmation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not found on PATH." >&2
  exit 1
fi

# Same shared-root resolution as run.sh, so the registry is found regardless
# of which worktree's copy of this script is invoked.
GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -z "$GIT_COMMON_DIR" ]; then
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

INSTANCES_ROOT="${REPO_ROOT}/.instances"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

list_instances() {
  if [ ! -d "$INSTANCES_ROOT" ] || [ -z "$(ls -A "$INSTANCES_ROOT" 2>/dev/null)" ]; then
    echo "No registered instances." >&2
    return
  fi
  printf "%-24s %-24s %-24s\n" "NAME" "CREATED" "LAST USED"
  for dir in "$INSTANCES_ROOT"/*/; do
    name="$(basename "$dir")"
    created="$(cat "${dir}created-at" 2>/dev/null || echo "?")"
    last_used="$(cat "${dir}last-used" 2>/dev/null || echo "?")"
    printf "%-24s %-24s %-24s\n" "$name" "$created" "$last_used"
  done
}

remove_instance() {
  local name="$1"
  local skip_confirm="$2"

  # Same validation run.sh applies to DEVCONTAINER_INSTANCE before any use —
  # required here too, since name feeds a filesystem path (rm -rf), a Docker
  # volume name, and a double-quoted Postgres identifier below. Without this,
  # a value like ".." or "" passes the existence check on line below (it
  # resolves to a directory that legitimately exists — REPO_ROOT itself, or
  # the registry root) and reaches the destructive operations further down.
  if ! [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "Instance name must match ^[a-z][a-z0-9-]*\$ (lowercase letters, digits, hyphens, starting with a letter) — got '${name}'." >&2
    exit 1
  fi

  if [ ! -d "${INSTANCES_ROOT}/${name}" ]; then
    echo "No registered instance named '${name}'." >&2
    exit 1
  fi

  if [ "$skip_confirm" != "yes" ]; then
    read -r -p "Remove instance '${name}' (volume, database, registry entry)? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Aborted." >&2; exit 1 ;;
    esac
  fi

  local volume="henia-devcontainer-home-${name}"
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume rm "$volume" >&2
    echo "Removed volume '${volume}'." >&2
  else
    echo "No volume '${volume}' to remove." >&2
  fi

  local postgres_id
  postgres_id="$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)"
  if [ -n "$postgres_id" ]; then
    # SQL-safety here depends entirely on name already having passed the
    # ^[a-z][a-z0-9-]*$ check above (no quotes/semicolons possible) — see
    # run.sh's matching validation and its SAFETY INVARIANT note.
    docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U app -d henia_dev \
      -c "DROP DATABASE IF EXISTS \"${name}\"" >&2
    echo "Dropped database '${name}' (if it existed)." >&2
  else
    echo "Postgres isn't running — skipping database drop for '${name}'." >&2
    echo "Start it (devcontainer/run.sh) and re-run cleanup if the database still needs dropping." >&2
  fi

  rm -rf "${INSTANCES_ROOT:?}/${name}"
  echo "Removed registry entry for '${name}'." >&2
}

SKIP_CONFIRM="no"
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --yes) SKIP_CONFIRM="yes" ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [ "${#ARGS[@]}" -eq 0 ]; then
  list_instances
else
  remove_instance "${ARGS[0]}" "$SKIP_CONFIRM"
fi
