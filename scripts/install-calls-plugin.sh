#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CALLS_VERSION=${CALLS_VERSION:-1.12.1}
ARCH=${ARCH:-linux-arm64}
PLUGIN_URL=${PLUGIN_URL:-https://github.com/mattermost/mattermost-plugin-calls/releases/download/v${CALLS_VERSION}/mattermost-plugin-calls-v${CALLS_VERSION}-${ARCH}.tar.gz}
PLUGIN_TARBALL=${PLUGIN_TARBALL:-/mattermost/data/mattermost-plugin-calls-v${CALLS_VERSION}-${ARCH}.tar.gz}

require_command curl

cd "$APP_DIR"

if compose exec -T mattermost-prod /mattermost/bin/mmctl --local plugin list 2>/dev/null | grep -q 'com.mattermost.calls: Calls'; then
  echo "[install-calls] com.mattermost.calls already installed"
  exit 0
fi

echo "[install-calls] downloading ${PLUGIN_URL}"
compose exec -T mattermost-prod curl -fsSL "$PLUGIN_URL" -o "$PLUGIN_TARBALL"

echo "[install-calls] installing plugin"
compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin add "$PLUGIN_TARBALL"
compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin enable com.mattermost.calls
compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin list

echo "[install-calls] completed"
