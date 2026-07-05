#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

AUDIT_LOG=${AUDIT_LOG:-$APP_DIR/ops/app-audit.log}
MFA_REQUIRED=${MFA_REQUIRED:-false}

require_command docker

cd "$APP_DIR"

failures=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
note() { echo "NOTE: $*"; }

mmctl_cfg() {
  compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local config get "$1" 2>/dev/null | tr -d '\r'
}

expect_bool() {
  label=$1
  key=$2
  expected=$3
  actual=$(mmctl_cfg "$key")
  if [ "$actual" = "$expected" ]; then
    pass "$label=$actual"
  else
    fail "$label expected $expected, got $actual"
  fi
}

expect_string() {
  label=$1
  key=$2
  expected=$3
  actual=$(mmctl_cfg "$key")
  if [ "$actual" = "$expected" ]; then
    pass "$label=$actual"
  else
    fail "$label expected $expected, got $actual"
  fi
}

{
  echo "=== Mattermost app audit $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "Host: $(hostname -f 2>/dev/null || hostname)"
  echo "MFA_REQUIRED=$MFA_REQUIRED"

  expect_bool "EnableUserCreation" "TeamSettings.EnableUserCreation" "false"
  expect_bool "EnableSignUpWithEmail" "EmailSettings.EnableSignUpWithEmail" "false"
  expect_bool "EnableOpenServer" "TeamSettings.EnableOpenServer" "false"
  note "Team creation is controlled via Advanced Permissions (create_team); EnableTeamCreation is deprecated"
  expect_string "PasswordMinimumLength" "PasswordSettings.MinimumLength" "14"
  expect_bool "PasswordLowercase" "PasswordSettings.Lowercase" "true"
  expect_bool "PasswordUppercase" "PasswordSettings.Uppercase" "true"
  expect_bool "PasswordNumber" "PasswordSettings.Number" "true"
  expect_bool "PasswordSymbol" "PasswordSettings.Symbol" "true"

  if [ "$MFA_REQUIRED" = "true" ]; then
    expect_bool "EnableMultifactorAuthentication" "ServiceSettings.EnableMultifactorAuthentication" "true"
    expect_bool "EnforceMultifactorAuthentication" "ServiceSettings.EnforceMultifactorAuthentication" "true"
  else
    note "MFA checks skipped (early trial)"
  fi

  if compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin list 2>/dev/null | grep -q 'com.mattermost.calls: Calls'; then
    pass "Calls plugin installed"
  else
    fail "Calls plugin not installed"
  fi

  if compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local plugin list 2>/dev/null | grep -q 'com.lalbers.community-admin: Community Admin'; then
    pass "Community Admin plugin installed"
  else
    note "Community Admin plugin not installed (optional)"
  fi

  ice_host=$(mmctl_cfg "PluginSettings.Plugins.com.mattermost.calls.icehostoverride" 2>/dev/null || true)
  if [ -z "$ice_host" ] || [ "$ice_host" = "{}" ] || [ "$ice_host" = "null" ]; then
    if compose exec -T mattermost-prod env | grep -q "^MM_CALLS_ICE_HOST_OVERRIDE="; then
      pass "Calls ICE host override via environment"
    else
      fail "Calls ICE host override not set"
    fi
  elif [ "$ice_host" = "${PROD_HOSTNAME:-}" ] || [ "$ice_host" = "${MM_CALLS_ICE_HOST_OVERRIDE:-}" ]; then
    pass "Calls ICE host override=$ice_host"
  else
    note "Calls ICE host override=$ice_host (verify against prod hostname)"
  fi

  expect_bool "SendPushNotifications" "EmailSettings.SendPushNotifications" "true"
  expected_push_server=${MM_PUSH_NOTIFICATION_SERVER:-https://global.push.mattermost.com}
  expect_string "PushNotificationServer" "EmailSettings.PushNotificationServer" "$expected_push_server"

  mention_only=$(compose exec -T postgres psql -U postgres -d mattermost_prod -t -A -c "
    SELECT COUNT(*) FROM users u
    WHERE u.deleteat = 0
      AND u.username <> 'calls'
      AND NOT EXISTS (SELECT 1 FROM bots b WHERE b.userid = u.id)
      AND u.notifyprops->>'push' = 'mention';
  " 2>/dev/null || echo "error")
  if [ "$mention_only" = "0" ]; then
    pass "No human users left on push=mention"
  elif [ "$mention_only" = "error" ]; then
    fail "Could not query user push preferences"
  else
    fail "$mention_only human user(s) still on push=mention (run configure-push-notifications.sh)"
  fi

  if [ "$failures" -eq 0 ]; then
    echo "RESULT: PASS"
  else
    echo "RESULT: FAIL ($failures checks failed)"
  fi
  echo
} | tee -a "$AUDIT_LOG"

exit "$failures"
