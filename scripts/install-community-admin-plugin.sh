#!/usr/bin/env bash
# Install or upgrade com.lalbers.community-admin into production Mattermost.
#
# Plugin repository: https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin
# Set PLUGIN_TARBALL_LOCAL or PLUGIN_URL (see docs/06-operations.md).
#
# Filestore-first: always uploads prod/plugins/<id>.tar.gz via the rclone S3 proxy
# before relying on Mattermost's own persist (which can fail with NoSuchUpload).
#
# FORCE=true — disable/delete existing install and overwrite the filestore bundle.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

COMMUNITY_ADMIN_VERSION=${COMMUNITY_ADMIN_VERSION:-1.0.0}
ARCH=${ARCH:-linux-arm64}
PLUGIN_ID=com.lalbers.community-admin
PLUGIN_URL=${PLUGIN_URL:-}
PLUGIN_TARBALL_LOCAL=${PLUGIN_TARBALL_LOCAL:-}
PLUGIN_TARBALL=${PLUGIN_TARBALL:-/mattermost/data/mattermost-plugin-community-admin-v${COMMUNITY_ADMIN_VERSION}-${ARCH}.tar.gz}
SHA256_FILE=${SHA256_FILE:-}
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
Usage: install-community-admin-plugin.sh [--force]

  PLUGIN_TARBALL_LOCAL=/path/to/plugin.tar.gz install-community-admin-plugin.sh
  PLUGIN_URL=https://.../plugin.tar.gz install-community-admin-plugin.sh
  FORCE=true PLUGIN_TARBALL_LOCAL=... install-community-admin-plugin.sh
EOF
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ "$FORCE" != "true" ] && plugin_is_enabled "$PLUGIN_ID"; then
  echo "[install-community-admin] ${PLUGIN_ID} already enabled (set FORCE=true to upgrade)"
  if [ -n "$PLUGIN_TARBALL_LOCAL" ] && [ -f "$PLUGIN_TARBALL_LOCAL" ]; then
    ensure_filestore_plugin_bundle "$PLUGIN_ID" "$PLUGIN_TARBALL_LOCAL"
  elif ! filestore_has_plugin_bundle "$PLUGIN_ID"; then
    echo "[install-community-admin] WARN: plugin enabled locally but filestore bundle missing; re-run with PLUGIN_TARBALL_LOCAL" >&2
  fi
  exit 0
fi

host_tar=
cleanup_host_tar=false
if [ -n "$PLUGIN_TARBALL_LOCAL" ]; then
  [ -f "$PLUGIN_TARBALL_LOCAL" ] || die "local plugin tarball not found: $PLUGIN_TARBALL_LOCAL"
  host_tar=$PLUGIN_TARBALL_LOCAL
elif [ -n "$PLUGIN_URL" ]; then
  host_tar=$(mktemp /tmp/community-admin-plugin.XXXXXX.tar.gz)
  cleanup_host_tar=true
  echo "[install-community-admin] downloading ${PLUGIN_URL}"
  curl -fsSL "$PLUGIN_URL" -o "$host_tar"
else
  die "set PLUGIN_URL or PLUGIN_TARBALL_LOCAL to install ${PLUGIN_ID}"
fi

tar_bytes=$(stat -c%s "$host_tar")
needed_max=$((tar_bytes + SIZE_HEADROOM))
echo "[install-community-admin] tarball ${tar_bytes} bytes; MaxFileSize floor ${needed_max}"

with_plugin_install_env "$needed_max"

if [ "$FORCE" = "true" ] && plugin_is_installed "$PLUGIN_ID"; then
  echo "[install-community-admin] FORCE=true: removing existing ${PLUGIN_ID}"
  mmctl_plugin_delete "$PLUGIN_ID"
fi

# Filestore-first: seed/overwrite S3 before mmctl add (rclone persist is flaky for large bundles).
FORCE_UPLOAD=true ensure_filestore_plugin_bundle "$PLUGIN_ID" "$host_tar"

echo "[install-community-admin] copying tarball into mattermost-prod"
compose cp "$host_tar" "mattermost-prod:$PLUGIN_TARBALL"

if [ -n "$SHA256_FILE" ]; then
  [ -f "$SHA256_FILE" ] || die "SHA256 file not found: $SHA256_FILE"
  expected=$(awk '{print $1}' "$SHA256_FILE")
  actual=$(compose exec -T mattermost-prod sha256sum "$PLUGIN_TARBALL" | awk '{print $1}')
  [ "$expected" = "$actual" ] || die "SHA256 mismatch for plugin tarball (expected $expected got $actual)"
  echo "[install-community-admin] SHA256 verified"
fi

echo "[install-community-admin] installing plugin"
mmctl_plugin_add_tolerant "$PLUGIN_ID" "$PLUGIN_TARBALL"
mmctl_local plugin enable "$PLUGIN_ID" || true
verify_plugin_survives_restart "$PLUGIN_ID"

mmctl_local plugin list

if [ "$cleanup_host_tar" = "true" ]; then
  rm -f "$host_tar"
fi

echo "[install-community-admin] completed (filestore-backed; survives restart)"
