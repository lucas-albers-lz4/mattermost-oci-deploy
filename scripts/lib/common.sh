#!/usr/bin/env bash

APP_DIR=${APP_DIR:-/opt/mattermost}
COMPOSE_FILE=${COMPOSE_FILE:-$APP_DIR/compose.yml}
ENV_FILE=${ENV_FILE:-$APP_DIR/.env}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-mattermost}
LOG_PREFIX=${LOG_PREFIX:-[mattermost]}

die() {
  echo "$LOG_PREFIX ERROR: $*" >&2
  exit 1
}

load_env() {
  [ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

compose() {
  docker compose --env-file "$ENV_FILE" -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

container_id() {
  service=$1
  id=$(compose ps -q "$service")
  [ -n "$id" ] || die "container missing for service: $service"
  echo "$id"
}

volume_name() {
  echo "${COMPOSE_PROJECT_NAME}_$1"
}

notify_failure() {
  status=$1
  message=$2

  if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
    host=$(hostname)
    curl -fsS --max-time 10 \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"${message} on ${host} with exit ${status}\"}" \
      "$ALERT_WEBHOOK_URL" >/dev/null || true
  fi
}

oci_namespace() {
  oci os ns get --auth instance_principal --query data --raw-output
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}
