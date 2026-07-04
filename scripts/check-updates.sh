#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

LOG_PREFIX="[mattermost-update-check]"

cd "$APP_DIR"
load_env

lines=()
add_line() {
  lines+=("$1")
}

# Host apt upgrades
apt_count=0
if apt list --upgradable 2>/dev/null | grep -qv '^Listing'; then
  apt_count=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
fi
add_line "Host: ${apt_count} apt package(s) upgradable"

if [ -f /var/run/reboot-required ]; then
  add_line "Host: reboot required (/var/run/reboot-required present)"
else
  add_line "Host: no reboot pending"
fi

# Docker Engine packages
docker_pending=
if apt list --upgradable 2>/dev/null | grep -Eiq '^(docker-ce|docker-ce-cli|containerd\.io|docker-compose-plugin)/'; then
  docker_pending=$(apt list --upgradable 2>/dev/null | grep -Ei '^(docker-ce|docker-ce-cli|containerd\.io|docker-compose-plugin)/' | tr '\n' ' ')
  add_line "Docker Engine: updates available — ${docker_pending}"
else
  add_line "Docker Engine: no pending apt upgrades"
fi

# Last Caddy auto-update
if systemctl list-units --type=service --all 2>/dev/null | grep -q mattermost-caddy-update.service; then
  caddy_result=$(systemctl show mattermost-caddy-update.service -p Result --value 2>/dev/null || echo unknown)
  caddy_time=$(systemctl show mattermost-caddy-update.service -p ExecMainStartTimestamp --value 2>/dev/null || echo never)
  add_line "Caddy auto-update: last run ${caddy_time} result=${caddy_result}"
else
  add_line "Caddy auto-update: timer not installed"
fi

# Postgres image vs registry (notify only; does not pull or recreate)
if docker image inspect postgres:16-alpine >/dev/null 2>&1; then
  local_digest=$(docker image inspect postgres:16-alpine --format '{{index .RepoDigests 0}}' 2>/dev/null || true)
  remote_digest=$(docker buildx imagetools inspect postgres:16-alpine --format '{{.Digest}}' 2>/dev/null || true)
  if [ -n "$remote_digest" ] && [ -n "$local_digest" ] && printf '%s' "$local_digest" | grep -qF "$remote_digest"; then
    add_line "Postgres (manual): postgres:16-alpine matches registry"
  elif [ -n "$remote_digest" ]; then
    add_line "Postgres (manual): update may be available (registry ${remote_digest})"
  else
    add_line "Postgres (manual): local image present; registry compare unavailable"
  fi
else
  add_line "Postgres (manual): postgres:16-alpine not present locally"
fi

# Mattermost version
current_mm=${MM_VERSION:-unknown}
latest_mm=$(python3 - <<'PY' 2>/dev/null || echo unknown
import re
import urllib.request

html = urllib.request.urlopen(
    "https://releases.mattermost.com/",
    timeout=20,
).read().decode("utf-8", "replace")
versions = sorted({tuple(map(int, v.split("."))) for v in re.findall(r'href="(\d+\.\d+\.\d+)/"', html)}, reverse=True)
if versions:
    print(".".join(str(x) for x in versions[0]))
PY
)
if [ "$latest_mm" = "unknown" ]; then
  add_line "Mattermost (manual): installed=${current_mm}; could not fetch latest release"
elif [ "$current_mm" = "$latest_mm" ]; then
  add_line "Mattermost (manual): ${current_mm} is current per releases.mattermost.com"
else
  add_line "Mattermost (manual): installed=${current_mm}; latest=${latest_mm} — see docs/07-upgrades.md"
fi

summary=$(printf '%s; ' "${lines[@]}")
echo "$LOG_PREFIX report:"
printf '%s\n' "${lines[@]}"

if printf '%s\n' "${lines[@]}" | grep -Eiq 'update may be available|updates available|latest=[0-9]|reboot required'; then
  notify_webhook "Mattermost update check: ${summary}"
fi

echo "$LOG_PREFIX done"
