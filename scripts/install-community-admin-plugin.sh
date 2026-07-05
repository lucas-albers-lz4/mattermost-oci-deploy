#!/usr/bin/env bash
# Install com.lalbers.community-admin plugin into production Mattermost.
#
# Plugin repository: https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin
# Set PLUGIN_TARBALL_LOCAL or PLUGIN_URL (see docs/06-operations.md).
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

require_command curl

cd "$APP_DIR"

if compose exec -T mattermost-prod /mattermost/bin/mmctl --local plugin list 2>/dev/null | grep -q "${PLUGIN_ID}: Community Admin"; then
  echo "[install-community-admin] ${PLUGIN_ID} already installed"
  exit 0
fi

if [ -n "$PLUGIN_TARBALL_LOCAL" ]; then
  [ -f "$PLUGIN_TARBALL_LOCAL" ] || die "local plugin tarball not found: $PLUGIN_TARBALL_LOCAL"
  echo "[install-community-admin] using local tarball ${PLUGIN_TARBALL_LOCAL}"
  compose cp "$PLUGIN_TARBALL_LOCAL" "mattermost-prod:$PLUGIN_TARBALL"
elif [ -n "$PLUGIN_URL" ]; then
  echo "[install-community-admin] downloading ${PLUGIN_URL}"
  compose exec -T mattermost-prod curl -fsSL "$PLUGIN_URL" -o "$PLUGIN_TARBALL"
else
  die "set PLUGIN_URL or PLUGIN_TARBALL_LOCAL to install ${PLUGIN_ID}"
fi

if [ -n "$SHA256_FILE" ]; then
  [ -f "$SHA256_FILE" ] || die "SHA256 file not found: $SHA256_FILE"
  expected=$(awk '{print $1}' "$SHA256_FILE")
  actual=$(compose exec -T mattermost-prod sha256sum "$PLUGIN_TARBALL" | awk '{print $1}')
  [ "$expected" = "$actual" ] || die "SHA256 mismatch for plugin tarball (expected $expected got $actual)"
  echo "[install-community-admin] SHA256 verified"
fi

echo "[install-community-admin] installing plugin"
compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin add "$PLUGIN_TARBALL"
compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin enable "$PLUGIN_ID"
compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin list

echo "[install-community-admin] completed"
