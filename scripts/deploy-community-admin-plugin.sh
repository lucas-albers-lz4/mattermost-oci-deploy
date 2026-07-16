#!/usr/bin/env bash
# shellcheck disable=SC2029
# Deploy a Community Admin plugin tarball from the laptop to an existing VM.
# scp → remote FORCE install (filestore-first) → print plugin list.
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/mattermost}
REMOTE_USER=${REMOTE_USER:-ubuntu}
SSH_REMOTE_OPTS=${SSH_REMOTE_OPTS:-}
REMOTE_HOST=${REMOTE_HOST:-}
REMOTE_TMP=${REMOTE_TMP:-/tmp/com.lalbers.community-admin.tar.gz}
SYNC_OPS_FIRST=${SYNC_OPS_FIRST:-false}

REPO_DIR=${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy-community-admin-plugin.sh <host> <tarball>
  REMOTE_HOST=matterhost scripts/deploy-community-admin-plugin.sh /path/to/plugin.tar.gz

Copies the tarball to the VM and runs install-community-admin-plugin.sh with FORCE=true
(filestore-first upgrade that survives amazons3 restart sync).

Prerequisite: ops scripts on the VM should include the FORCE/filestore helpers.
If you just pulled this repo, run sync-ops-to-host.sh first (or pass --sync-ops).

Options:
  --sync-ops          run scripts/sync-ops-to-host.sh before deploy
  -h, --help          show this help

Environment:
  REMOTE_HOST / REMOTE_USER / SSH_REMOTE_OPTS / APP_DIR — same as sync-ops-to-host.sh
  REMOTE_TMP            remote tarball path (default: /tmp/com.lalbers.community-admin.tar.gz)

Examples:
  scripts/deploy-community-admin-plugin.sh matterhost \
    ~/gitroot/mattermost-plugin-community-admin/dist/com.lalbers.community-admin-*.tar.gz

  scripts/deploy-community-admin-plugin.sh --sync-ops matterhost ./plugin.tar.gz
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 64
  }
}

TARBALL=
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --sync-ops)
      SYNC_OPS_FIRST=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      exit 64
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Accept: <host> <tarball>  OR  <tarball> with REMOTE_HOST set
case ${#POSITIONAL[@]} in
  0)
    usage >&2
    exit 64
    ;;
  1)
    if [ -z "$REMOTE_HOST" ]; then
      echo "Pass <host> <tarball> or set REMOTE_HOST" >&2
      exit 64
    fi
    TARBALL=${POSITIONAL[0]}
    ;;
  2)
    REMOTE_HOST=${POSITIONAL[0]}
    TARBALL=${POSITIONAL[1]}
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

# Expand a single glob if the shell left it unexpanded
# shellcheck disable=SC2086
if [ ! -f "$TARBALL" ]; then
  # try glob expansion when user passed a literal pattern
  # shellcheck disable=SC2206
  matches=($TARBALL)
  if [ ${#matches[@]} -eq 1 ] && [ -f "${matches[0]}" ]; then
    TARBALL=${matches[0]}
  fi
fi

[ -f "$TARBALL" ] || {
  echo "Tarball not found: $TARBALL" >&2
  exit 64
}

if [[ "$REMOTE_HOST" == *@* ]]; then
  REMOTE_USER=${REMOTE_HOST%%@*}
  REMOTE_HOST=${REMOTE_HOST#*@}
fi

require_command scp
require_command ssh

remote="$REMOTE_USER@$REMOTE_HOST"
tarball_abs=$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")

if [ "$SYNC_OPS_FIRST" = "true" ]; then
  echo "Syncing ops scripts to $remote first..."
  # sync-ops-to-host accepts either REMOTE_HOST env or a positional host, not both.
  REMOTE_HOST="$REMOTE_HOST" REMOTE_USER="$REMOTE_USER" SSH_REMOTE_OPTS="$SSH_REMOTE_OPTS" \
    "$REPO_DIR/scripts/sync-ops-to-host.sh" --no-verify
fi

echo "Deploying $(basename "$tarball_abs") ($(du -h "$tarball_abs" | awk '{print $1}')) -> $remote"
# shellcheck disable=SC2086
scp $SSH_REMOTE_OPTS "$tarball_abs" "$remote:$REMOTE_TMP"

echo "Running FORCE install on host..."
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$remote" \
  "FORCE=true PLUGIN_TARBALL_LOCAL='$REMOTE_TMP' '$APP_DIR/ops/install-community-admin-plugin.sh' --force"

echo
echo "Remote plugin list:"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$remote" \
  "cd '$APP_DIR' && docker compose --env-file .env -p mattermost -f compose.yml exec -T -u mattermost mattermost-prod \
     /mattermost/bin/mmctl --local plugin list" || true

echo
echo "Deploy complete."
