## User Accounts

This deployment is invite-only. Use **`manage-community-users.sh`** on the VM to create accounts, assign teams/channels, and print a one-line text message for parents.

Run from `/opt/mattermost`:

```sh
cd /opt/mattermost
/opt/mattermost/ops/manage-community-users.sh --help
```

### Create a member (single user)

```sh
/opt/mattermost/ops/manage-community-users.sh user create \
  --username alice.parent \
  --firstname Alice \
  --lastname Parent \
  --team parents \
  --channel parents:announcements
```

Output includes:

1. An operator log line with username and generated password.
2. A **`TEXT_TO_PARENT:`** line — copy/paste to SMS (site URL from `PROD_HOSTNAME` in `.env`).

Example:

```text
created user=alice.parent team=parents channels=parents:announcements password=...
TEXT_TO_PARENT: Your community chat login — https://chat.example.com — username: alice.parent — password: ... — save this message; contact the admin if you need a reset.
```

Options:

- `--password '...'` — set password instead of generating one.
- `--system-admin` — create a system administrator.
- `--no-parent-text` — skip the SMS line (e.g. for admin accounts).
- Multiple `--channel team:slug` flags for several channels.

Password must meet server policy (at least 14 characters with complexity). See [`09-security-hardening.md`](09-security-hardening.md).

**Security:** texting passwords is convenient but not ideal. Prefer in-person handoff when possible. Never commit credential exports.

### Reset a password

```sh
/opt/mattermost/ops/manage-community-users.sh user reset-password alice.parent --generate
```

Emits a new `TEXT_TO_PARENT:` line with the updated password. Email reset does not work without SMTP.

### Batch import (parents and children)

Copy [`templates/community-users.example.csv`](../templates/community-users.example.csv) to a local file (e.g. `community-users.csv` — gitignored). Header:

```csv
username,firstname,lastname,team,channels,role
```

- `channels` — semicolon-separated `team:channel` list.
- `role` — `member` (default) or `admin`.

Dry run:

```sh
/opt/mattermost/ops/manage-community-users.sh batch import --file community-users.csv --dry-run
```

Import:

```sh
/opt/mattermost/ops/manage-community-users.sh batch import --file community-users.csv \
  --credentials-out ./onboarding.credentials.csv
```

Existing users are skipped; team/channel membership is still applied. One `TEXT_TO_PARENT:` line per newly created user.

### Teams and channels

```sh
/opt/mattermost/ops/manage-community-users.sh team create --name u12-soccer --display-name "U12 Soccer"
/opt/mattermost/ops/manage-community-users.sh channel create --team u12-soccer --name team-chat \
  --display-name "Team Chat" --private
/opt/mattermost/ops/manage-community-users.sh team add-user u12-soccer alice.parent
/opt/mattermost/ops/manage-community-users.sh channel add-user u12-soccer:team-chat alice.parent
```

For community structure planning, see [`community-channel-policy.md`](community-channel-policy.md).

### Raw mmctl (debugging)

If the helper script is unavailable:

```sh
docker compose --env-file .env -p mattermost -f compose.yml exec -T -u mattermost mattermost-prod \
  /mattermost/bin/mmctl --local user create \
  --email user@example.com \
  --username username \
  --password 'ReplaceWithStrongPassword1!' \
  --firstname First \
  --lastname Last \
  --disable-welcome-email \
  --email-verified
```

See [`docs/10-audio-video-calls.md`](10-audio-video-calls.md) for how `mmctl --local` works.

## Community Admin plugin (delegated organizers)

For coaches and team leads who should manage users **without** System Console or SSH access,
install the separate [Community Admin plugin](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin)
(`com.lalbers.community-admin`). Source, configuration, and user guide live in that repository.

**Requires** `EnableLocalMode: true` on the Mattermost container (already set in this stack’s Compose template) so password reset can use `mmctl --local`.

### Install

From a local tarball built with `make dist` in the plugin repo:

```sh
cd /opt/mattermost
PLUGIN_TARBALL_LOCAL=/path/to/com.lalbers.community-admin-1.0.0.tar.gz \
  /opt/mattermost/ops/install-community-admin-plugin.sh
```

From a GitHub release (after you publish a tag, e.g. `v1.0.0`):

```sh
cd /opt/mattermost
COMMUNITY_ADMIN_VERSION=1.0.0 \
PLUGIN_URL=https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin/releases/download/v1.0.0/com.lalbers.community-admin-1.0.0.tar.gz \
  /opt/mattermost/ops/install-community-admin-plugin.sh
```

Optional checksum verification:

```sh
SHA256_FILE=/path/to/SHA256SUMS \
PLUGIN_URL=... \
  /opt/mattermost/ops/install-community-admin-plugin.sh
```

The install script is copied to the VM by `bootstrap-host.sh` as `/opt/mattermost/ops/install-community-admin-plugin.sh`.

### Configure organizers (system admin)

1. System Console → Plugins → Community Admin
2. Set **Site URL** (production hostname, e.g. `https://chat.example.org`)
3. Use the scope editor to add organizers by username and assign teams/channels
4. Save plugin settings

Organizers open **Community Members** from the **channel header** (desktop/web) or use mobile slash commands:

```text
/community-admin reset-password USERNAME
/community-admin remove-from-team USERNAME TEAM_NAME
```

Break-glass provisioning remains [`manage-community-users.sh`](#create-a-member-single-user) for the operator.

## Mobile app notifications

Mattermost mobile apps need three things to deliver lock-screen notifications:

1. **Server push proxy** — HPNS at `https://global.push.mattermost.com` (configured in Compose and `configure-push-notifications.sh`).
2. **User preference** — `push=all`, not mentions-only. New users created via `manage-community-users.sh` get this automatically; run `configure-push-notifications.sh` after deploy to fix existing accounts.
3. **Device registration** — each phone must log in once, allow notifications when iOS/Android prompts, and keep the official Mattermost app from the App Store / Play Store.

### Operator checklist

```sh
# Apply server + user defaults (idempotent)
/opt/mattermost/ops/configure-push-notifications.sh

# Inspect config, device registrations, and connectivity
/opt/mattermost/ops/diagnose-push-notifications.sh
```

After changing Compose push env vars, recreate the container:

```sh
cd /opt/mattermost
docker compose --env-file .env -p mattermost -f compose.yml up -d mattermost-prod
```

### What to tell parents

Share these steps when onboarding mobile users:

1. Install **Mattermost** from the App Store (iOS) or Google Play (Android) — not a third-party client.
2. Open the app → **Add a server** → enter `https://<PROD_HOSTNAME>` (from `.env`).
3. Log in with the username and password you provided.
4. When prompted, tap **Allow** for notifications.
5. To verify: Settings → **Notifications** → **Send a test notification** (app must be backgrounded to see the lock-screen banner).

**Note:** Notifications are not sent while you are actively viewing the same channel in the app. Background the app or switch channels to test.

If iOS still does not notify, check **Settings → Notifications → Mattermost** on the phone and confirm alerts are enabled.

## No-Email Operating Mode