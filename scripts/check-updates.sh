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

security_count=0
other_count=0
while IFS= read -r apt_line; do
  [[ "$apt_line" == Listing* ]] && continue
  [[ -z "$apt_line" ]] && continue
  if [[ "$apt_line" == *-security* ]]; then
    security_count=$((security_count + 1))
  else
    other_count=$((other_count + 1))
  fi
done < <(apt list --upgradable 2>/dev/null)
add_line "Host security: ${security_count} apt package(s) upgradable"
add_line "Host other: ${other_count} apt package(s) upgradable (not auto-installed)"

if [ -f /var/run/reboot-required ]; then
  reboot_pkg=$(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null || cat /var/run/reboot-required 2>/dev/null || true)
  add_line "Host: reboot required (${reboot_pkg:-/var/run/reboot-required present})"
else
  add_line "Host: no reboot pending"
fi

docker_pending=
if apt list --upgradable 2>/dev/null | grep -Eiq '^(docker-ce|docker-ce-cli|containerd\.io|docker-compose-plugin)/'; then
  docker_pending=$(apt list --upgradable 2>/dev/null | grep -Ei '^(docker-ce|docker-ce-cli|containerd\.io|docker-compose-plugin)/' | tr '\n' ' ')
  add_line "Docker Engine: updates available — ${docker_pending}"
else
  add_line "Docker Engine: no pending apt upgrades"
fi

if systemctl is-enabled mattermost-caddy-update.timer &>/dev/null; then
  caddy_result=$(systemctl show mattermost-caddy-update.service -p Result --value 2>/dev/null || echo unknown)
  caddy_time=$(systemctl show mattermost-caddy-update.service -p ExecMainStartTimestamp --value 2>/dev/null || echo never)
  add_line "Caddy auto-update: last run ${caddy_time} result=${caddy_result}"
else
  add_line "Caddy auto-update: timer not installed"
fi

postgres_remote_digest() {
  local digest manifest_file
  manifest_file=$(mktemp)
  digest=$(docker buildx imagetools inspect postgres:16-alpine --format '{{.Digest}}' 2>/dev/null || true)
  if [ -n "$digest" ]; then
    rm -f "$manifest_file"
    printf '%s' "$digest"
    return 0
  fi
  if docker manifest inspect postgres:16-alpine >"$manifest_file" 2>/dev/null; then
    digest=$(python3 - "$manifest_file" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
if "config" in data:
    print(data.get("Descriptor", {}).get("digest", ""))
elif "manifests" in data and data["manifests"]:
    print(data["manifests"][0].get("digest", ""))
PY
)
  fi
  rm -f "$manifest_file"
  if [ -n "$digest" ]; then
    printf '%s' "$digest"
  fi
}

if docker image inspect postgres:16-alpine >/dev/null 2>&1; then
  local_digest=$(docker image inspect postgres:16-alpine --format '{{index .RepoDigests 0}}' 2>/dev/null || true)
  remote_digest=$(postgres_remote_digest)
  if [ -n "$remote_digest" ] && [ -n "$local_digest" ] && printf '%s' "$local_digest" | grep -qF "$remote_digest"; then
    add_line "Postgres (manual): postgres:16-alpine matches registry"
  elif [ -n "$remote_digest" ]; then
    add_line "Postgres (manual): update may be available (registry ${remote_digest})"
  else
    echo "$LOG_PREFIX WARN: postgres registry compare failed (buildx and manifest inspect)" >&2
    add_line "Postgres (manual): local image present; registry compare unavailable"
  fi
else
  add_line "Postgres (manual): postgres:16-alpine not present locally"
fi

current_mm=${MM_VERSION:-unknown}
latest_mm=$(python3 - <<'PY' 2>/dev/null || echo unknown
import json
import re
import urllib.request

USER_AGENT = "mattermost-oci-deploy-check-updates/1.0"
versions = set()


def add_version(value):
    if re.fullmatch(r"\d+\.\d+\.\d+", value):
        versions.add(value)


def fetch_releases_page():
    req = urllib.request.Request(
        "https://releases.mattermost.com/",
        headers={"User-Agent": USER_AGENT},
    )
    html = urllib.request.urlopen(req, timeout=20).read().decode("utf-8", "replace")
    for match in re.findall(r'href="(\d+\.\d+\.\d+)/"', html):
        add_version(match)


def fetch_github_releases():
    req = urllib.request.Request(
        "https://api.github.com/repos/mattermost/mattermost/releases?per_page=30",
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": USER_AGENT,
        },
    )
    releases = json.loads(urllib.request.urlopen(req, timeout=20).read().decode("utf-8", "replace"))
    for release in releases:
        if release.get("prerelease"):
            continue
        add_version(release.get("tag_name", "").lstrip("v"))


for fetch in (fetch_releases_page, fetch_github_releases):
    try:
        fetch()
    except Exception:
        continue

if versions:
    latest = sorted(versions, key=lambda v: tuple(map(int, v.split("."))), reverse=True)[0]
    print(latest)
else:
    print("unknown")
PY
)

if [ -z "$latest_mm" ]; then
  add_line "Mattermost (manual): installed=${current_mm}; could not parse latest release"
elif [ "$latest_mm" = "unknown" ]; then
  add_line "Mattermost (manual): installed=${current_mm}; could not fetch latest release"
elif [ "$current_mm" = "$latest_mm" ]; then
  add_line "Mattermost (manual): ${current_mm} is current per releases.mattermost.com"
else
  mm_newer=$(python3 - "$current_mm" "$latest_mm" <<'PY'
import sys

def parse(value):
    return tuple(map(int, value.split(".")))

current = parse(sys.argv[1])
latest = parse(sys.argv[2])
print("yes" if latest > current else "no")
PY
)
  if [ "$mm_newer" = "yes" ]; then
    add_line "Mattermost (manual): installed=${current_mm}; latest=${latest_mm} — see docs/07-upgrades.md"
  else
    add_line "Mattermost (manual): installed=${current_mm}; catalog=${latest_mm} (installed is newer or same)"
  fi
fi

summary=$(printf '%s; ' "${lines[@]}")
echo "$LOG_PREFIX report:"
printf '%s\n' "${lines[@]}"

should_notify=false
for line in "${lines[@]}"; do
  case "$line" in
    *"update may be available"*|*"updates available"*|*"reboot required"*)
      should_notify=true
      ;;
  esac
  if [[ "$line" =~ latest=[0-9]+\.[0-9]+\.[0-9]+ ]] && [[ "$line" != *"latest=${current_mm}"* ]]; then
    should_notify=true
  fi
done

if [ "$should_notify" = true ]; then
  notify_webhook "Mattermost update check: ${summary}"
fi

echo "$LOG_PREFIX done"
