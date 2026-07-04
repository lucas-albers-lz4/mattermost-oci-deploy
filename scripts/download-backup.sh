#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup-timestamp>" >&2
  exit 64
fi

BACKUP_TS=$1
BACKUP_ROOT=${BACKUP_ROOT:-/opt/mattermost/backups}
BACKUP_DIR="$BACKUP_ROOT/$BACKUP_TS"

cd "$APP_DIR"
load_env
BUCKET_NAME=${BACKUP_BUCKET_NAME:-mattermost-backups}

mkdir -p "$BACKUP_DIR"
namespace=$(oci_namespace)

oci os object bulk-download \
  --auth instance_principal \
  --namespace-name "$namespace" \
  --bucket-name "$BUCKET_NAME" \
  --prefix "daily/$BACKUP_TS/" \
  --download-dir "$BACKUP_DIR" \
  --overwrite

if [ -d "$BACKUP_DIR/daily/$BACKUP_TS" ]; then
  find "$BACKUP_DIR/daily/$BACKUP_TS" -mindepth 1 -maxdepth 1 -exec mv {} "$BACKUP_DIR/" \;
  rm -rf "$BACKUP_DIR/daily"
fi

sha256sum -c "$BACKUP_DIR/SHA256SUMS" --ignore-missing >/dev/null
echo "Downloaded and verified $BACKUP_TS into $BACKUP_DIR"
