# 06 - Operations

## Sync ops scripts from git (day-2)

Do **not** keep a bare `git pull` on the VM as the primary path: the live tree is `/opt/mattermost` (with secrets in `.env`), while checked-in scripts land under `/opt/mattermost/deploy` and are copied into `/opt/mattermost/ops` by bootstrap. Prefer the laptop → rsync → bootstrap flow already used by `deploy-from-zero.sh`.

From your Mac (repo checkout), after commits that change ops/monitoring scripts (for example `c5c6f1a`):

```sh
# Optional: preview file list
scripts/sync-ops-to-host.sh --dry-run matterhost

# Default: refresh /opt/mattermost/ops + apt unattended-upgrades + systemd timers
# Does not overwrite compose.yml / Caddyfile / .env
scripts/sync-ops-to-host.sh matterhost
```

`matterhost` can be an IP, DNS name, SSH config `Host` alias, or `ubuntu@host`. Default user is `ubuntu`.

When templates must also refresh (compose, Caddy, image Dockerfile):

```sh
scripts/sync-ops-to-host.sh --full matterhost
```

Then recreate containers only if those template changes require it.

Verify on the VM:

```sh
ssh matterhost '/opt/mattermost/ops/check-updates.sh'
ssh matterhost '/opt/mattermost/ops/security-audit.sh --host-only'
```

Equivalent manual two-step (same as what the script runs):

```sh
rsync -az --delete \
  -e ssh \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude '*.tfstate*' \
  --exclude '*.tfvars' \
  --exclude 'tfplan' \
  --exclude '.mattermost-secrets.env' \
  --exclude 'generated.env' \
  --exclude '.env' \
  ./ ubuntu@matterhost:/opt/mattermost/deploy/

ssh ubuntu@matterhost \
  'cd /opt/mattermost/deploy && \
   APP_DIR=/opt/mattermost REPO_DIR=/opt/mattermost/deploy \
   INSTALL_PACKAGES=false COPY_ASSETS=true COPY_STACK_TEMPLATES=false \
   INSTALL_KSPLICE=false ./scripts/bootstrap-host.sh'
```

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

### Install notes (filestore + MaxFileSize)

This stack stores attachments and **plugin bundles** in Object Storage via the on-VM rclone S3 proxy (`MM_FILESETTINGS_DRIVERNAME=amazons3`). On every Mattermost start, plugins are removed locally and re-synced from:

`s3://mattermost-files/prod/plugins/<plugin-id>.tar.gz`

If `mmctl plugin add` succeeds but that object is missing, the plugin disappears after the next restart (look for `Failed to sync plugin from file store` / `The specified key does not exist` in prod logs).

Also, `MM_FILESETTINGS_MAXFILESIZE` (default 50 MiB) limits plugin uploads. A ~63 MiB Community Admin build needs a temporary raise (handled by the install script).

Install/upgrade scripts are **filestore-first**: they upload the tarball to Object Storage via AWS CLI against the rclone proxy *before* `mmctl plugin add`, because Mattermost’s own multipart persist often fails with `NoSuchUpload` on large bundles.

### Upgrade / redeploy (laptop)

From this repo on your Mac, after `make dist` in the plugin repo:

```sh
# Push latest ops scripts (needed when install helpers change), then upgrade
scripts/deploy-community-admin-plugin.sh --sync-ops matterhost \
  /path/to/mattermost-plugin-community-admin/dist/com.lalbers.community-admin-*.tar.gz
```

Or in two steps:

```sh
scripts/sync-ops-to-host.sh matterhost
scripts/deploy-community-admin-plugin.sh matterhost /path/to/plugin.tar.gz
```

On the VM alone (tarball already present):

```sh
cd /opt/mattermost
FORCE=true PLUGIN_TARBALL_LOCAL=/tmp/com.lalbers.community-admin.tar.gz \
  /opt/mattermost/ops/install-community-admin-plugin.sh --force
```

`FORCE=true` disables/deletes the existing plugin, overwrites the filestore object, re-adds, enables, and verifies a prod recreate still shows the plugin.

### Install (first time on VM)

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

The install script is copied to the VM by `bootstrap-host.sh` as `/opt/mattermost/ops/install-community-admin-plugin.sh`. After script changes on your laptop, push them with `scripts/sync-ops-to-host.sh` (see [Sync ops scripts](#sync-ops-scripts-from-git-day-2)).

### Troubleshooting plugin deploy

| Symptom | What to do |
|--------|------------|
| `Uploaded plugin size exceeds limit` | Install script should raise MaxFileSize temporarily; ensure ops scripts are synced |
| `Failed to sync` / `key does not exist` after restart | Filestore object missing — re-run with `FORCE=true` and a local tarball |
| `plugin add` → `NoSuchUpload` / Internal Server Error | Expected flake with rclone for large bundles; script pre-seeds S3 and recovers via enable/recreate |
| Plugin version unchanged after deploy | Forgot `FORCE=true`, or old ops script on VM — use `--sync-ops` then redeploy |
| Mattermost crash: `config.json: permission denied` | Config volume file owned by root — `sudo chown 2000:2000` that file; never edit config as root |

### Configure organizers (system admin)

1. System Console → Plugins → Community Admin
2. Set **Site URL** (production hostname, e.g. `https://chat.example.org`)
3. Use the scope editor to add organizers by username and assign teams/channels
4. Save plugin settings

Organizers open **Community Members** from the **channel header** (desktop/web) or use mobile slash commands:

![Community Members panel — delegated organizer view](images/community-admin/02-panel-list.png)

Illustrated organizer guide: [plugin user guide](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin/blob/main/docs/user-guide.md) (screenshots also in this repo under `docs/images/community-admin/`).

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