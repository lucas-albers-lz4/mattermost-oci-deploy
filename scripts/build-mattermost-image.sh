#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

cd "$APP_DIR"
load_env

: "${MM_VERSION:?MM_VERSION must be set in $ENV_FILE}"

build_args=(--build-arg "MM_VERSION=$MM_VERSION")
if [ -n "${MM_TARBALL_SHA256:-}" ]; then
  build_args+=(--build-arg "MM_TARBALL_SHA256=$MM_TARBALL_SHA256")
fi

compose build "${build_args[@]}" mattermost-prod

image_id=$(docker image inspect "local/mattermost-arm64:$MM_VERSION" --format '{{.Id}}')
mkdir -p "$APP_DIR/build-metadata"
cat > "$APP_DIR/build-metadata/mattermost-$MM_VERSION.txt" <<EOF
MM_VERSION=$MM_VERSION
MM_TARBALL_URL=https://releases.mattermost.com/$MM_VERSION/mattermost-$MM_VERSION-linux-arm64.tar.gz
MM_TARBALL_SHA256=${MM_TARBALL_SHA256:-}
IMAGE=local/mattermost-arm64:$MM_VERSION
IMAGE_ID=$image_id
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Built local/mattermost-arm64:$MM_VERSION"
echo "Metadata: $APP_DIR/build-metadata/mattermost-$MM_VERSION.txt"
