#!/usr/bin/env bash
# Copy Community Admin documentation screenshots from the plugin repo into this deploy repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_REPO="${PLUGIN_REPO:-$(cd "${DEPLOY_ROOT}/../mattermost-plugin-community-admin" 2>/dev/null && pwd || true)}"
SRC="${PLUGIN_REPO}/docs/images/community-admin"
DEST="${DEPLOY_ROOT}/docs/images/community-admin"

if [[ ! -d "${SRC}" ]]; then
  echo "Plugin screenshot directory not found: ${SRC}" >&2
  echo "Set PLUGIN_REPO to the mattermost-plugin-community-admin checkout." >&2
  exit 1
fi

mkdir -p "${DEST}"
cp "${SRC}"/01-channel-header.png \
   "${SRC}"/02-panel-list.png \
   "${SRC}"/04-create-form.png \
   "${SRC}"/05-credentials-create.png \
   "${DEST}/"

echo "Synced screenshots to ${DEST}"
