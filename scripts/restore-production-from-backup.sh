#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

if [ $# -ne 1 ]; then
  echo "Usage: CONFIRM_PRODUCTION_RESTORE=<backup-timestamp> $0 <backup-timestamp>" >&2
  exit 64
fi

BACKUP_TS="$1"
BACKUP_DIR=${BACKUP_DIR:-/opt/mattermost/backups/$BACKUP_TS}
SKIP_PRE_RESTORE_BACKUP=${SKIP_PRE_RESTORE_BACKUP:-false}

if [ "${CONFIRM_PRODUCTION_RESTORE:-}" != "$BACKUP_TS" ]; then
  echo "Refusing production restore. Set CONFIRM_PRODUCTION_RESTORE=$BACKUP_TS to proceed." >&2
  exit 65
fi

cd "$APP_DIR"
load_env

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup directory not found: $BACKUP_DIR" >&2
  exit 66
fi

sha256sum -c "$BACKUP_DIR/SHA256SUMS" --ignore-missing >/dev/null

if [ "$SKIP_PRE_RESTORE_BACKUP" != "true" ]; then
  echo "[restore-production] taking pre-restore backup"
  "$SCRIPT_DIR/backup-mattermost.sh"
fi

echo "[restore-production] ensuring postgres is running"
compose up -d postgres >/dev/null
postgres_health=
for _ in $(seq 1 60); do
  postgres_id=$(container_id postgres)
  postgres_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$postgres_id")
  [ "$postgres_health" = "healthy" ] && break
  sleep 2
done
[ "$postgres_health" = "healthy" ] || {
  echo "Postgres did not become healthy; last status: $postgres_health" >&2
  exit 67
}

echo "[restore-production] stopping production app"
compose stop mattermost-prod >/dev/null

for volume in prod-config prod-data prod-logs prod-plugins prod-client-plugins prod-bleve; do
  docker run --rm -v "$(volume_name "$volume"):/target" alpine sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
done

echo "[restore-production] restoring production volumes"
docker run --rm \
  -v "$(volume_name prod-config):/volumes/prod-config" \
  -v "$(volume_name prod-data):/volumes/prod-data" \
  -v "$(volume_name prod-logs):/volumes/prod-logs" \
  -v "$(volume_name prod-plugins):/volumes/prod-plugins" \
  -v "$(volume_name prod-client-plugins):/volumes/prod-client-plugins" \
  -v "$(volume_name prod-bleve):/volumes/prod-bleve" \
  -v "$BACKUP_DIR:/backup:ro" \
  alpine tar -xzf /backup/prod-volumes.tar.gz -C /volumes

docker run --rm \
  -v "$(volume_name prod-config):/volumes/prod-config" \
  -v "$(volume_name prod-data):/volumes/prod-data" \
  -v "$(volume_name prod-logs):/volumes/prod-logs" \
  -v "$(volume_name prod-plugins):/volumes/prod-plugins" \
  -v "$(volume_name prod-client-plugins):/volumes/prod-client-plugins" \
  -v "$(volume_name prod-bleve):/volumes/prod-bleve" \
  alpine sh -c 'chown -R 2000:2000 /volumes && find /volumes -type d -exec chmod 755 {} + && find /volumes -type f -exec chmod 600 {} +'

echo "[restore-production] restoring production database"
docker cp "$BACKUP_DIR/prod-db.dump" "$postgres_id:/tmp/prod-db.dump"
compose exec -T -e PGPASSWORD="$POSTGRES_SUPER_PASSWORD" postgres \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${MM_PROD_DB_USER}') THEN
    CREATE ROLE ${MM_PROD_DB_USER} LOGIN PASSWORD '${MM_PROD_DB_PASSWORD}';
  ELSE
    ALTER ROLE ${MM_PROD_DB_USER} WITH LOGIN PASSWORD '${MM_PROD_DB_PASSWORD}';
  END IF;
END
\$\$;
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${MM_PROD_DB_NAME}';
DROP DATABASE IF EXISTS ${MM_PROD_DB_NAME};
CREATE DATABASE ${MM_PROD_DB_NAME} OWNER ${MM_PROD_DB_USER};
SQL
compose exec -T -e PGPASSWORD="$POSTGRES_SUPER_PASSWORD" postgres \
  pg_restore -U postgres -d "$MM_PROD_DB_NAME" --clean --if-exists /tmp/prod-db.dump
compose exec -T postgres rm -f /tmp/prod-db.dump

echo "[restore-production] starting production app"
compose up -d mattermost-prod caddy >/dev/null
echo "[restore-production] completed $BACKUP_TS"
