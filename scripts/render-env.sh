#!/usr/bin/env bash
set -euo pipefail

TOFU_DIR=${TOFU_DIR:-infra/opentofu}
OUTPUT_FILE=${OUTPUT_FILE:-}
SECRETS_FILE=${SECRETS_FILE:-.mattermost-secrets.env}
ENV_OUT=${ENV_OUT:-generated.env}
MM_VERSION=${MM_VERSION:-11.8.2}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-mattermost}
LOCAL_BACKUP_RETENTION_DAYS=${LOCAL_BACKUP_RETENTION_DAYS:-7}

json_get() {
  key=$1
  file=$2
  python3 - "$key" "$file" <<'PY'
import json
import sys

key, path = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get(key, {}).get("value", "")
print(value if value is not None else "")
PY
}

random_hex() {
  openssl rand -hex 24
}

if [ -z "$OUTPUT_FILE" ] && command -v tofu >/dev/null 2>&1 && [ -d "$TOFU_DIR" ]; then
  OUTPUT_FILE=$(mktemp)
  tofu -chdir="$TOFU_DIR" output -json > "$OUTPUT_FILE"
fi

if [ -n "$OUTPUT_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
  PROD_HOSTNAME=${PROD_HOSTNAME:-$(json_get prod_hostname "$OUTPUT_FILE")}
  TEST_HOSTNAME=${TEST_HOSTNAME:-$(json_get test_hostname "$OUTPUT_FILE")}
  BACKUP_BUCKET_NAME=${BACKUP_BUCKET_NAME:-$(json_get backup_bucket_name "$OUTPUT_FILE")}
  CALLS_ICE_HOST_OVERRIDE=${CALLS_ICE_HOST_OVERRIDE:-$(json_get prod_hostname "$OUTPUT_FILE")}
fi

if [ -f "$SECRETS_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
  set +a
fi

POSTGRES_SUPER_PASSWORD=${POSTGRES_SUPER_PASSWORD:-$(random_hex)}
MM_PROD_DB_PASSWORD=${MM_PROD_DB_PASSWORD:-$(random_hex)}
MM_TEST_DB_PASSWORD=${MM_TEST_DB_PASSWORD:-$(random_hex)}

if [ ! -f "$SECRETS_FILE" ]; then
  umask 077
  cat > "$SECRETS_FILE" <<EOF
POSTGRES_SUPER_PASSWORD=$POSTGRES_SUPER_PASSWORD
MM_PROD_DB_PASSWORD=$MM_PROD_DB_PASSWORD
MM_TEST_DB_PASSWORD=$MM_TEST_DB_PASSWORD
EOF
fi

: "${PROD_HOSTNAME:?Set PROD_HOSTNAME or provide OpenTofu outputs.}"
: "${TEST_HOSTNAME:?Set TEST_HOSTNAME or provide OpenTofu outputs.}"
: "${TEST_ALLOWED_CIDR:?Set TEST_ALLOWED_CIDR to the admin public IP/CIDR.}"

BACKUP_BUCKET_NAME=${BACKUP_BUCKET_NAME:-mattermost-backups}
MM_PROD_DB_NAME=${MM_PROD_DB_NAME:-mattermost_prod}
MM_PROD_DB_USER=${MM_PROD_DB_USER:-mattermost_prod}
MM_TEST_DB_NAME=${MM_TEST_DB_NAME:-mattermost_test}
MM_TEST_DB_USER=${MM_TEST_DB_USER:-mattermost_test}
CALLS_ICE_HOST_OVERRIDE=${CALLS_ICE_HOST_OVERRIDE:-$PROD_HOSTNAME}

umask 077
cat > "$ENV_OUT" <<EOF
MM_VERSION=$MM_VERSION
MM_TARBALL_SHA256=${MM_TARBALL_SHA256:-}
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME

PROD_HOSTNAME=$PROD_HOSTNAME
TEST_HOSTNAME=$TEST_HOSTNAME
TEST_ALLOWED_CIDR=$TEST_ALLOWED_CIDR

POSTGRES_SUPER_PASSWORD=$POSTGRES_SUPER_PASSWORD

MM_PROD_DB_NAME=$MM_PROD_DB_NAME
MM_PROD_DB_USER=$MM_PROD_DB_USER
MM_PROD_DB_PASSWORD=$MM_PROD_DB_PASSWORD

MM_TEST_DB_NAME=$MM_TEST_DB_NAME
MM_TEST_DB_USER=$MM_TEST_DB_USER
MM_TEST_DB_PASSWORD=$MM_TEST_DB_PASSWORD

BACKUP_BUCKET_NAME=$BACKUP_BUCKET_NAME
LOCAL_BACKUP_RETENTION_DAYS=$LOCAL_BACKUP_RETENTION_DAYS

MM_CALLS_UDP_SERVER_ADDRESS=0.0.0.0
MM_CALLS_UDP_SERVER_PORT=8443
MM_CALLS_ICE_HOST_OVERRIDE=$CALLS_ICE_HOST_OVERRIDE
EOF

if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
  printf 'ALERT_WEBHOOK_URL=%s\n' "$ALERT_WEBHOOK_URL" >> "$ENV_OUT"
fi

echo "Rendered $ENV_OUT"
echo "Stored generated secrets in $SECRETS_FILE"
