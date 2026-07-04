#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup-timestamp>" >&2
  exit 64
fi

BACKUP_TS="$1"
BACKUP_DIR=${BACKUP_DIR:-/opt/mattermost/backups/$BACKUP_TS}

cd "$APP_DIR"
load_env

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup directory not found: $BACKUP_DIR" >&2
  exit 66
fi

sha256sum -c "$BACKUP_DIR/SHA256SUMS" --ignore-missing >/dev/null

echo "[restore-test] ensuring postgres is running"
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

echo "[restore-test] stopping test app"
compose stop mattermost-test >/dev/null

for volume in test-config test-data test-logs test-plugins test-client-plugins test-bleve; do
  docker run --rm -v "$(volume_name "$volume"):/target" alpine sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
done

echo "[restore-test] restoring test volumes"
docker run --rm \
  -v "$(volume_name test-config):/volumes/test-config" \
  -v "$(volume_name test-data):/volumes/test-data" \
  -v "$(volume_name test-logs):/volumes/test-logs" \
  -v "$(volume_name test-plugins):/volumes/test-plugins" \
  -v "$(volume_name test-client-plugins):/volumes/test-client-plugins" \
  -v "$(volume_name test-bleve):/volumes/test-bleve" \
  -v "$BACKUP_DIR:/backup:ro" \
  alpine tar -xzf /backup/test-volumes.tar.gz -C /volumes

docker run --rm \
  -v "$(volume_name test-config):/volumes/test-config" \
  -v "$(volume_name test-data):/volumes/test-data" \
  -v "$(volume_name test-logs):/volumes/test-logs" \
  -v "$(volume_name test-plugins):/volumes/test-plugins" \
  -v "$(volume_name test-client-plugins):/volumes/test-client-plugins" \
  -v "$(volume_name test-bleve):/volumes/test-bleve" \
  alpine sh -c 'chown -R 2000:2000 /volumes && find /volumes -type d -exec chmod 755 {} + && find /volumes -type f -exec chmod 600 {} +'

echo "[restore-test] restoring test database"
docker cp "$BACKUP_DIR/test-db.dump" "$postgres_id:/tmp/test-db.dump"
compose exec -T -e PGPASSWORD="$POSTGRES_SUPER_PASSWORD" postgres \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${MM_TEST_DB_USER}') THEN
    CREATE ROLE ${MM_TEST_DB_USER} LOGIN PASSWORD '${MM_TEST_DB_PASSWORD}';
  ELSE
    ALTER ROLE ${MM_TEST_DB_USER} WITH LOGIN PASSWORD '${MM_TEST_DB_PASSWORD}';
  END IF;
END
\$\$;
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${MM_TEST_DB_NAME}';
DROP DATABASE IF EXISTS ${MM_TEST_DB_NAME};
CREATE DATABASE ${MM_TEST_DB_NAME} OWNER ${MM_TEST_DB_USER};
SQL
compose exec -T -e PGPASSWORD="$POSTGRES_SUPER_PASSWORD" postgres \
  pg_restore -U postgres -d "$MM_TEST_DB_NAME" --clean --if-exists /tmp/test-db.dump
compose exec -T postgres rm -f /tmp/test-db.dump

echo "[restore-test] starting test app"
compose up -d mattermost-test caddy >/dev/null
echo "[restore-test] completed $BACKUP_TS"
