# 07 - Upgrades

## Upgrade Rule

Always upgrade test first.

Always back up before changing Mattermost versions.

## Pre-Upgrade

```sh
ssh ubuntu@<vm-public-ip>
cd /opt/mattermost
/opt/mattermost/ops/health-check.sh
/opt/mattermost/ops/backup-mattermost.sh
```

If `/var/run/reboot-required` exists, reboot first (or wait for Sunday 04:00 UTC) before a long Mattermost upgrade — a mid-upgrade host reboot causes extra downtime.

Avoid scheduling Mattermost upgrades during the automated Sunday **04:00–06:00 UTC** window unless you disable `mattermost-reboot.timer` and `mattermost-caddy-update.timer` first. See [`15-unattended-updates.md`](15-unattended-updates.md).

## Choose Version

Edit:

```text
/opt/mattermost/.env
```

Update:

```env
MM_VERSION=<target-version>
```

Confirm the official ARM64 release tarball exists:

```text
https://releases.mattermost.com/<target-version>/mattermost-<target-version>-linux-arm64.tar.gz
```

## Build Image

```sh
cd /opt/mattermost
/opt/mattermost/ops/build-mattermost-image.sh
```

The resulting image tag is shared:

```text
local/mattermost-arm64:${MM_VERSION}
```

## Deploy Test

Start the test instance (idle by default; see [`14-performance.md`](14-performance.md)):

```sh
cd /opt/mattermost
/opt/mattermost/ops/manage-test-instance.sh start
```

The helper activates the `upgrade-test` Compose profile and waits for internal HTTP. The test service has no dependency on production.

Validate:

```sh
curl -I https://<test-hostname>/
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 mattermost-test
/opt/mattermost/ops/health-check.sh
```

Also validate in the browser:

- Login
- Channel load
- Message send
- File upload/download
- Plugins or integrations, if used

## Deploy Production

Only after test passes:

```sh
cd /opt/mattermost
docker compose --env-file .env -p mattermost -f compose.yml up -d mattermost-prod caddy
/opt/mattermost/ops/manage-test-instance.sh stop
```

Stopping test after production deploy returns the VM to the normal idle state (~2 GB RAM freed).

Validate:

```sh
curl -I https://<prod-hostname>/
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 mattermost-prod
/opt/mattermost/ops/health-check.sh
```

## Rollback

If Mattermost has not run migrations, a simple image version rollback may work.

If migrations have run, rollback should be a restore:

1. Stop the affected app.
2. Restore the database dump from the pre-upgrade backup.
3. Restore matching volumes from the same backup.
4. Reset `MM_VERSION`.
5. Rebuild/restart.
6. Validate health and logs.

Use the test restore script as the model:

```sh
/opt/mattermost/ops/restore-test-from-backup.sh <backup-timestamp>
```

Do not restore production without confirming the backup timestamp and checksums.
