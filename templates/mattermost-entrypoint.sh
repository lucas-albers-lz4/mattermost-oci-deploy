#!/bin/sh
set -eu

: "${MM_CONFIG:=/mattermost/config/config.json}"
export MM_CONFIG

generate_salt() {
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 48
}

if [ ! -f "$MM_CONFIG" ]; then
  mkdir -p "$(dirname "$MM_CONFIG")"
  cp /config.json.save "$MM_CONFIG"
  jq '.ServiceSettings.ListenAddress = ":8000"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq '.LogSettings.EnableConsole = true' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq '.LogSettings.ConsoleLevel = "INFO"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq '.FileSettings.Directory = "/mattermost/data/"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq '.PluginSettings.Directory = "/mattermost/plugins/"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq '.PluginSettings.ClientDirectory = "/mattermost/client/plugins/"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq '.BleveSettings.IndexDir = "/mattermost/bleve-indexes"' "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq ".FileSettings.PublicLinkSalt = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq ".EmailSettings.InviteSalt = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq ".EmailSettings.PasswordResetSalt = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  jq ".SqlSettings.AtRestEncryptKey = \"$(generate_salt)\"" "$MM_CONFIG" > "$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
fi

exec "$@"
