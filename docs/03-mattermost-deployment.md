# 03 - Mattermost Deployment

## Why A Custom Image

OCI Free Tier A1 runs ARM64. The deployment uses a local ARM64 Mattermost image built from official Mattermost Server ARM64 release tarballs.

Image tag pattern:

```text
local/mattermost-arm64:<version>
```

Release tarball pattern:

```text
https://releases.mattermost.com/<version>/mattermost-<version>-linux-arm64.tar.gz
```

## Host Layout

On the VM:

```text
/opt/mattermost/
├── .env
├── compose.yml
├── caddy/
│   └── Caddyfile
├── mattermost-arm64/
│   ├── Dockerfile
│   └── entrypoint.sh
├── postgres/
│   └── init/
│       └── 001-create-mattermost-dbs.sh
└── ops/
```

The live `.env` file must never be committed.

## Environment Variables

Create `/opt/mattermost/.env` from `templates/env.example`, or prefer `scripts/render-env.sh` when using the OpenTofu-driven workflow.

Required values:

- `MM_VERSION`
- `PROD_HOSTNAME`
- `TEST_HOSTNAME`
- `TEST_ALLOWED_CIDR`
- `POSTGRES_SUPER_PASSWORD`
- `MM_PROD_DB_NAME`
- `MM_PROD_DB_USER`
- `MM_PROD_DB_PASSWORD`
- `MM_TEST_DB_NAME`
- `MM_TEST_DB_USER`
- `MM_TEST_DB_PASSWORD`

Generate passwords on the VM:

```sh
openssl rand -hex 24
```

## Build And Start

```sh
cd /opt/mattermost
/opt/mattermost/ops/build-mattermost-image.sh
docker compose --env-file .env -p mattermost -f compose.yml up -d
```

Only production, Postgres, and Caddy start by default. The test Mattermost container uses the `upgrade-test` Compose profile and stays stopped to save RAM on the free-tier VM.

After first deploy, validate test once then return to idle:

```sh
/opt/mattermost/ops/manage-test-instance.sh start
/opt/mattermost/ops/health-check.sh
/opt/mattermost/ops/manage-test-instance.sh stop
```

`deploy-from-zero.sh` runs this sequence automatically. See [`docs/14-performance.md`](14-performance.md).

Verify:

```sh
docker compose --env-file .env -p mattermost -f compose.yml ps
curl -I "https://${PROD_HOSTNAME}/"
curl -I "https://${TEST_HOSTNAME}/"
```

## Initial Security Settings

After creating the first admin account, apply the account controls in `docs/09-security-hardening.md`:

- Disable open account creation.
- Disable email signup unless intentionally needed.
- Restrict team creation to admins.
- Enable a strong password policy.
- Enable MFA, then enforce it after admins have enrolled.

## Production And Test Isolation

Shared:

- VM
- Docker host
- Caddy
- PostgreSQL container
- Backup framework

Partitioned:

- Mattermost containers
- Site URLs
- PostgreSQL databases and users
- Config volumes
- Upload/data volumes
- Plugin volumes
- Logs
- Bleve indexes

## Email Mode

SMTP is intentionally disabled.

Implications:

- Password reset email does not work.
- Email invitations do not work.
- Admins must help with account recovery.
- User onboarding should be manual.

Do not enable email until a real SMTP provider and sender identity are chosen.

## Mobile Push Notifications

Production uses Mattermost Hosted Push Notification Service (HPNS) at `https://global.push.mattermost.com`. Compose sets this via `MM_PUSH_NOTIFICATION_SERVER` in `.env` and `MM_EMAILSETTINGS_PUSHNOTIFICATIONSERVER` on the container.

After deploy or upgrade, run:

```sh
/opt/mattermost/ops/configure-push-notifications.sh
```

This enables push, points at HPNS, and sets existing human users to `push=all` (not mentions-only).

Troubleshooting:

```sh
/opt/mattermost/ops/diagnose-push-notifications.sh
```

See [`docs/06-operations.md`](06-operations.md#mobile-app-notifications) for parent-facing mobile setup.

## Community Admin plugin (optional)

This stack supports invite-only communities where **organizers** (coaches, team leads) create accounts and reset passwords without System Console access.

Install the plugin from the separate repository after production Mattermost is healthy:

- **Repository:** [lucas-albers-lz4/mattermost-plugin-community-admin](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin)
- **Plugin ID:** `com.lalbers.community-admin`
- **Install on VM:** `/opt/mattermost/ops/install-community-admin-plugin.sh` (see [06-operations.md § Community Admin](06-operations.md#community-admin-plugin-delegated-organizers))

Build the tarball on your workstation (`make dist` in the plugin repo) or download a [GitHub release](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin/releases) asset, then run the install script on the VM with `PLUGIN_TARBALL_LOCAL` or `PLUGIN_URL`.

Configure organizers in **System Console → Plugins → Community Admin** (site URL, team/channel scope). Production Compose already enables `EnableLocalMode` for password reset.
