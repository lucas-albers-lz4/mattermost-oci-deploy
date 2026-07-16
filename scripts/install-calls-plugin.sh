#!/usr/bin/env bash
# Install or upgrade Mattermost Calls into production.
# Filestore-first; FORCE=true overwrites an existing install.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CALLS_VERSION=${CALLS_VERSION:-1.12.1}
ARCH=${ARCH:-linux-arm64}
PLUGIN_ID=com.mattermost.calls
PLUGIN_URL=${PLUGIN_URL:-https://github.com/mattermost/mattermost-plugin-calls/releases/download/v${CALLS_VERSION}/mattermost-plugin-calls-v${CALLS_VERSION}-${ARCH}.tar.gz}
PLUGIN_TARBALL=${PLUGIN_TARBALL:-/mattermost/data/mattermost-plugin-calls-v${CALLS_VERSION}-${ARCH}.tar.gz}
PLUGIN_TARBALL_LOCAL=${PLUGIN_TARBALL_LOCAL:-}
SIZE_HEADROOM=${SIZE_HEADROOM:-1048576}
FORCE=${FORCE:-false}

require_command curl
require_command docker

cd "$APP_DIR"
load_env

while [ $# -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: install-calls-plugin.sh [--force]

  install-calls-plugin.sh
  PLUGIN_TARBALL_LOCAL=/path/to/calls.tar.gz FORCE=true install-calls-plugin.sh
EOF
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ "$FORCE" != "true" ] && plugin_is_enabled "$PLUGIN_ID"; then
  echo "[install-calls] ${PLUGIN_ID} already enabled (set FORCE=true to upgrade)"
  if [ -n "$PLUGIN_TARBALL_LOCAL" ] && [ -f "$PLUGIN_TARBALL_LOCAL" ]; then
    ensure_filestore_plugin_bundle "$PLUGIN_ID" "$PLUGIN_TARBALL_LOCAL"
  fi
  exit 0
fi

host_tar=
cleanup_host_tar=false
if [ -n "$PLUGIN_TARBALL_LOCAL" ]; then
  [ -f "$PLUGIN_TARBALL_LOCAL" ] || die "local plugin tarball not found: $PLUGIN_TARBALL_LOCAL"
  host_tar=$PLUGIN_TARBALL_LOCAL
else
  host_tar=$(mktemp /tmp/mattermost-calls-plugin.XXXXXX.tar.gz)
  cleanup_host_tar=true
  echo "[install-calls] downloading ${PLUGIN_URL}"
  curl -fsSL "$PLUGIN_URL" -o "$host_tar"
fi

tar_bytes=$(stat -c%s "$host_tar")
needed_max=$((tar_bytes + SIZE_HEADROOM))
echo "[install-calls] tarball ${tar_bytes} bytes; MaxFileSize floor ${needed_max}"

with_plugin_install_env "$needed_max"

if [ "$FORCE" = "true" ] && plugin_is_installed "$PLUGIN_ID"; then
  echo "[install-calls] FORCE=true: removing existing ${PLUGIN_ID}"
  mmctl_plugin_delete "$PLUGIN_ID"
fi

FORCE_UPLOAD=true ensure_filestore_plugin_bundle "$PLUGIN_ID" "$host_tar"

echo "[install-calls] copying tarball into mattermost-prod"
compose cp "$host_tar" "mattermost-prod:$PLUGIN_TARBALL"

echo "[install-calls] installing plugin"
mmctl_plugin_add_tolerant "$PLUGIN_ID" "$PLUGIN_TARBALL"
mmctl_local plugin enable "$PLUGIN_ID" || true
verify_plugin_survives_restart "$PLUGIN_ID"

mmctl_local plugin list

if [ "$cleanup_host_tar" = "true" ]; then
  rm -f "$host_tar"
fi

echo "[install-calls] completed (filestore-backed; survives restart)"
