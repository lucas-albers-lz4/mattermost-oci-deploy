#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

LOG_PREFIX="[mattermost-caddy-update]"
CADDY_IMAGE=caddy:2-alpine

cd "$APP_DIR"
load_env

finish() {
  status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    notify_failure "$status" "Caddy auto-update failed"
  fi
  exit "$status"
}
trap finish EXIT

old_id=$(docker image inspect "$CADDY_IMAGE" --format '{{.Id}}' 2>/dev/null || true)
echo "$LOG_PREFIX pulling $CADDY_IMAGE (current=${old_id:-none})"
compose pull caddy

new_id=$(docker image inspect "$CADDY_IMAGE" --format '{{.Id}}')
if [ -n "$old_id" ] && [ "$old_id" = "$new_id" ]; then
  echo "$LOG_PREFIX image unchanged ($new_id)"
  exit 0
fi

echo "$LOG_PREFIX image updated ${old_id:-none} -> $new_id"
compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null
compose up -d caddy
compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null

prod_public=$(curl -L -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${PROD_HOSTNAME}/" || true)
[ "$prod_public" = "200" ] || die "production endpoint returned $prod_public after Caddy update"

echo "$LOG_PREFIX OK prod_public=${prod_public} image=$new_id"
