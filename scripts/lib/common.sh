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

notify_webhook() {
  message=$1

  if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
    host=$(hostname)
    curl -fsS --max-time 10 \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"${message} on ${host}\"}" \
      "$ALERT_WEBHOOK_URL" >/dev/null || true
  fi
}

notify_maintenance() {
  message=$1

  if [ "${ALERT_WEBHOOK_MAINTENANCE:-false}" = "true" ]; then
    notify_webhook "$message"
  fi
}

oci_namespace() {
  oci os ns get --auth instance_principal --query data --raw-output
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Temporarily set MM_PLUGINSETTINGS_ENABLEUPLOADS=true in .env and recreate prod
# (Compose env overrides config.json). Restores the previous value on EXIT via trap.
# Usage: with_plugin_uploads_enabled; ... install ...;  (trap restores automatically)
with_plugin_uploads_enabled() {
  _mm_uploads_prev=$(grep -E '^MM_PLUGINSETTINGS_ENABLEUPLOADS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  _mm_restore_uploads() {
    if [ -n "${_mm_uploads_prev}" ]; then
      if grep -qE '^MM_PLUGINSETTINGS_ENABLEUPLOADS=' "$ENV_FILE"; then
        sed -i.bak "s/^MM_PLUGINSETTINGS_ENABLEUPLOADS=.*/MM_PLUGINSETTINGS_ENABLEUPLOADS=${_mm_uploads_prev}/" "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
      fi
    else
      sed -i.bak '/^MM_PLUGINSETTINGS_ENABLEUPLOADS=/d' "$ENV_FILE" 2>/dev/null || true
      rm -f "$ENV_FILE.bak"
    fi
    compose up -d mattermost-prod >/dev/null
  }
  trap _mm_restore_uploads EXIT
  if grep -qE '^MM_PLUGINSETTINGS_ENABLEUPLOADS=' "$ENV_FILE"; then
    sed -i.bak 's/^MM_PLUGINSETTINGS_ENABLEUPLOADS=.*/MM_PLUGINSETTINGS_ENABLEUPLOADS=true/' "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    printf '\nMM_PLUGINSETTINGS_ENABLEUPLOADS=true\n' >> "$ENV_FILE"
  fi
  compose up -d mattermost-prod >/dev/null
  sleep 8
}
