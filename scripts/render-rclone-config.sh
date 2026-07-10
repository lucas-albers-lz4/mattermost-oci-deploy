#!/usr/bin/env bash
# Render rclone.conf for the on-VM S3 proxy (instance principal → mattermost-files).
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/mattermost}
ENV_FILE=${ENV_FILE:-$APP_DIR/.env}
OUT=${OUT:-$APP_DIR/rclone/rclone.conf}
TEMPLATE=${TEMPLATE:-$APP_DIR/rclone/rclone.conf.tpl}

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE" >&2
  exit 64
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "Missing $TEMPLATE" >&2
  exit 64
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${OBJECT_STORAGE_NAMESPACE:?OBJECT_STORAGE_NAMESPACE missing in $ENV_FILE}"
: "${COMPARTMENT_OCID:?COMPARTMENT_OCID missing in $ENV_FILE}"
: "${MM_FILESETTINGS_AMAZONS3REGION:?MM_FILESETTINGS_AMAZONS3REGION missing in $ENV_FILE}"

mkdir -p "$(dirname "$OUT")"
umask 077
# shellcheck disable=SC2016
sed \
  -e "s|\${OBJECT_STORAGE_NAMESPACE}|${OBJECT_STORAGE_NAMESPACE}|g" \
  -e "s|\${COMPARTMENT_OCID}|${COMPARTMENT_OCID}|g" \
  -e "s|\${MM_FILESETTINGS_AMAZONS3REGION}|${MM_FILESETTINGS_AMAZONS3REGION}|g" \
  "$TEMPLATE" > "$OUT"
chmod 0600 "$OUT"
echo "Rendered $OUT"
