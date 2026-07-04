#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

BACKUP_ROOT=${BACKUP_ROOT:-/opt/mattermost/backups}
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
LOG_PREFIX="[mattermost-backup]"
TEST_PROFILE=upgrade-test

cd "$APP_DIR"
load_env
BUCKET_NAME=${BACKUP_BUCKET_NAME:-mattermost-backups}
LOCAL_RETENTION_DAYS=${LOCAL_BACKUP_RETENTION_DAYS:-7}
mkdir -p "$BACKUP_DIR"

prod_was_running=0
test_was_running=0
apps_stopped=0

service_running() {
  service=$1
  profile=${2:-}
  if [ -n "$profile" ]; then
    id=$(compose --profile "$profile" ps -q "$service" 2>/dev/null || true)
  else
    id=$(compose ps -q "$service" 2>/dev/null || true)
  fi
  [ -n "$id" ] || return 1
  [ "$(docker inspect -f '{{.State.Status}}' "$id")" = "running" ]
}

restart_apps() {
  if [ "$apps_stopped" = "0" ]; then
    return 0
  fi
  if [ "$prod_was_running" = "1" ]; then
    compose up -d mattermost-prod >/dev/null || true
  fi
  if [ "$test_was_running" = "1" ]; then
    compose --profile "$TEST_PROFILE" up -d mattermost-test >/dev/null || true
  fi
  if [ "$prod_was_running" = "1" ] || [ "$test_was_running" = "1" ]; then
    compose up -d caddy >/dev/null || true
  fi
}

finish() {
  status=$?
  trap - EXIT
  restart_apps
  if [ "$status" -ne 0 ]; then
    notify_failure "$status" "Mattermost backup failed"
  fi
  exit "$status"
}
trap finish EXIT

echo "$LOG_PREFIX starting $TIMESTAMP"

if service_running mattermost-prod; then
  prod_was_running=1
  compose stop mattermost-prod >/dev/null
  apps_stopped=1
fi
if service_running mattermost-test "$TEST_PROFILE"; then
  test_was_running=1
  compose --profile "$TEST_PROFILE" stop mattermost-test >/dev/null
  apps_stopped=1
fi

compose exec -T -e PGPASSWORD="$POSTGRES_SUPER_PASSWORD" postgres \
  pg_dump -U postgres -d "$MM_PROD_DB_NAME" --format=custom --file=/tmp/prod.dump
compose exec -T -e PGPASSWORD="$POSTGRES_SUPER_PASSWORD" postgres \
  pg_dump -U postgres -d "$MM_TEST_DB_NAME" --format=custom --file=/tmp/test.dump
postgres_id=$(container_id postgres)
docker cp "$postgres_id:/tmp/prod.dump" "$BACKUP_DIR/prod-db.dump"
docker cp "$postgres_id:/tmp/test.dump" "$BACKUP_DIR/test-db.dump"
compose exec -T postgres rm -f /tmp/prod.dump /tmp/test.dump

docker run --rm \
  -v "$(volume_name prod-config):/volumes/prod-config:ro" \
  -v "$(volume_name prod-data):/volumes/prod-data:ro" \
  -v "$(volume_name prod-logs):/volumes/prod-logs:ro" \
  -v "$(volume_name prod-plugins):/volumes/prod-plugins:ro" \
  -v "$(volume_name prod-client-plugins):/volumes/prod-client-plugins:ro" \
  -v "$(volume_name prod-bleve):/volumes/prod-bleve:ro" \
  -v "$BACKUP_DIR:/backup" \
  alpine tar -czf /backup/prod-volumes.tar.gz -C /volumes .

docker run --rm \
  -v "$(volume_name test-config):/volumes/test-config:ro" \
  -v "$(volume_name test-data):/volumes/test-data:ro" \
  -v "$(volume_name test-logs):/volumes/test-logs:ro" \
  -v "$(volume_name test-plugins):/volumes/test-plugins:ro" \
  -v "$(volume_name test-client-plugins):/volumes/test-client-plugins:ro" \
  -v "$(volume_name test-bleve):/volumes/test-bleve:ro" \
  -v "$BACKUP_DIR:/backup" \
  alpine tar -czf /backup/test-volumes.tar.gz -C /volumes .

docker run --rm \
  -v "$(volume_name caddy-data):/volumes/caddy-data:ro" \
  -v "$(volume_name caddy-config):/volumes/caddy-config:ro" \
  -v "$BACKUP_DIR:/backup" \
  alpine tar -czf /backup/caddy-volumes.tar.gz -C /volumes .

cp "$APP_DIR/compose.yml" "$BACKUP_DIR/compose.yml"
cp "$APP_DIR/caddy/Caddyfile" "$BACKUP_DIR/Caddyfile"
sha256sum "$BACKUP_DIR"/* > "$BACKUP_DIR/SHA256SUMS"

NAMESPACE=$(oci_namespace)
for file in "$BACKUP_DIR"/*; do
  object_name="daily/$TIMESTAMP/$(basename "$file")"
  oci os object put --auth instance_principal --namespace-name "$NAMESPACE" --bucket-name "$BUCKET_NAME" --name "$object_name" --file "$file" --force >/dev/null
done

find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$LOCAL_RETENTION_DAYS" -exec rm -rf {} +
echo "$LOG_PREFIX completed $TIMESTAMP"
