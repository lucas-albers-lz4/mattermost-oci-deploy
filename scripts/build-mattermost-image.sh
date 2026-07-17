#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

LOG_PREFIX=${LOG_PREFIX:-[mattermost-build]}
USER_AGENT="mattermost-oci-deploy-build/1.0"

cd "$APP_DIR"
load_env

: "${MM_VERSION:?MM_VERSION must be set in $ENV_FILE}"

if [[ ! "$MM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "MM_VERSION must be x.y.z (got: $MM_VERSION)"
fi

tarball_name="mattermost-${MM_VERSION}-linux-arm64.tar.gz"
tarball_url="https://releases.mattermost.com/${MM_VERSION}/${tarball_name}"
checksum_url="${tarball_url}.sha256"

retry_curl() {
  local attempts=3
  local delay=2
  local i=1
  local out
  while [ "$i" -le "$attempts" ]; do
    if out=$(curl -fsSL --max-time 60 -A "$USER_AGENT" "$@"); then
      printf '%s' "$out"
      return 0
    fi
    echo "$LOG_PREFIX WARN: download failed (attempt ${i}/${attempts}); retry in ${delay}s" >&2
    sleep "$delay"
    i=$((i + 1))
    delay=$((delay * 2))
  done
  return 1
}

parse_sha256() {
  local raw=$1
  local digest
  digest=$(printf '%s\n' "$raw" | awk 'NF >= 1 { print $1; exit }')
  if [[ ! "$digest" =~ ^[0-9a-fA-F]{64}$ ]]; then
    die "malformed Mattermost ARM64 checksum for ${MM_VERSION}: ${raw}"
  fi
  printf '%s' "$(printf '%s' "$digest" | tr 'A-F' 'a-f')"
}

if [ -n "${MM_TARBALL_SHA256:-}" ]; then
  if [[ ! "$MM_TARBALL_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
    die "MM_TARBALL_SHA256 must be a 64-char hex digest"
  fi
  MM_TARBALL_SHA256=$(printf '%s' "$MM_TARBALL_SHA256" | tr 'A-F' 'a-f')
  echo "$LOG_PREFIX using configured MM_TARBALL_SHA256"
else
  echo "$LOG_PREFIX fetching official checksum: $checksum_url"
  checksum_raw=$(retry_curl "$checksum_url") || die "could not fetch official ARM64 checksum for ${MM_VERSION}"
  MM_TARBALL_SHA256=$(parse_sha256 "$checksum_raw")
  echo "$LOG_PREFIX verified checksum metadata: ${MM_TARBALL_SHA256}"
fi

build_args=(
  --build-arg "MM_VERSION=$MM_VERSION"
  --build-arg "MM_TARBALL_SHA256=$MM_TARBALL_SHA256"
)

compose build "${build_args[@]}" mattermost-prod

image_ref="local/mattermost-arm64:$MM_VERSION"
image_id=$(docker image inspect "$image_ref" --format '{{.Id}}')

version_out=$(docker run --rm --entrypoint /mattermost/bin/mattermost "$image_ref" version 2>/dev/null || true)
built_version=$(printf '%s\n' "$version_out" | awk -F': ' '/^Version:/{ print $2; exit }')
if [ "$built_version" != "$MM_VERSION" ]; then
  die "built image reports Version=${built_version:-unknown}, expected ${MM_VERSION}"
fi

mkdir -p "$APP_DIR/build-metadata"
cat > "$APP_DIR/build-metadata/mattermost-$MM_VERSION.txt" <<EOF
MM_VERSION=$MM_VERSION
MM_TARBALL_URL=$tarball_url
MM_TARBALL_SHA256=$MM_TARBALL_SHA256
IMAGE=$image_ref
IMAGE_ID=$image_id
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Built $image_ref"
echo "Metadata: $APP_DIR/build-metadata/mattermost-$MM_VERSION.txt"
