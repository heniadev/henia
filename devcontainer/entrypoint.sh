#!/usr/bin/env bash
# Root-level entrypoint: sets up the network firewall (needs NET_ADMIN/
# NET_RAW, so it has to run before privileges are dropped), then hands off
# to user-entrypoint.sh as the unprivileged target user via gosu. Never runs
# anything from the repo or from Claude Code as root.
set -euo pipefail

# Default-allow internet, default-deny *outbound* private/VPN address space.
# This blocks the agent from *initiating* connections to your LAN/VPN, but
# must not block the container answering connections others initiate to it
# (e.g. your host hitting a dev server published from the container) — those
# replies also traverse OUTPUT, just for a connection someone else started.
# conntrack tells the two apart: ESTABLISHED/RELATED is reply/continuation
# traffic for a connection already tracked (allowed unconditionally, so dev
# servers stay reachable regardless of which private range the client is on)
# and only NEW connections — the container acting as *client* — get filtered
# by destination.
BLOCKED_RANGES=(
  10.0.0.0/8        # RFC1918
  172.16.0.0/12     # RFC1918
  192.168.0.0/16    # RFC1918
  169.254.0.0/16    # link-local
  100.64.0.0/10     # CGNAT / shared address space (Tailscale and similar VPNs)
)

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Explicit, narrow exceptions for specific private-range hosts actually
# needed (e.g. a k3s API server) — set via ALLOWED_HOSTS (run.sh derives
# this from kubeconfig.yaml when present). Format: space-separated "ip" or
# "ip:port" entries. These punch a hole for exactly the named host (and
# port, if given), not the surrounding range — everything else in that
# range stays blocked.
for entry in ${ALLOWED_HOSTS:-}; do
  host="${entry%%:*}"
  if [[ "$entry" == *:* ]]; then
    port="${entry##*:}"
    iptables -A OUTPUT -p tcp -d "${host}/32" --dport "$port" -j ACCEPT
  else
    iptables -A OUTPUT -d "${host}/32" -j ACCEPT
  fi
done

for range in "${BLOCKED_RANGES[@]}"; do
  iptables -A OUTPUT -m conntrack --ctstate NEW -d "$range" -j DROP
done

: "${TARGET_UID:?TARGET_UID must be set by run.sh}"
: "${TARGET_GID:?TARGET_GID must be set by run.sh}"

# gosu looks up the target UID in /etc/passwd to set $HOME the way `su`
# would; when that UID has no entry there (the normal case — it's your host
# UID, not a user baked into the image), it resets HOME to `/` instead of
# leaving the image's HOME alone. Re-assert it explicitly for the process
# gosu execs, so git/npm/claude config all land in the persisted volume.
exec gosu "${TARGET_UID}:${TARGET_GID}" env HOME=/home/agent /usr/local/bin/user-entrypoint.sh "$@"
