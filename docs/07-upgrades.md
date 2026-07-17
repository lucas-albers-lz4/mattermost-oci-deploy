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

Record the backup timestamp printed as `[mattermost-backup] completed <timestamp>` before changing `MM_VERSION`. Keep that timestamp for rollback.

If `/var/run/reboot-required` exists, reboot first (or wait for Sunday 09:00 UTC / ~3:00 AM MDT) before a long Mattermost upgrade — a mid-upgrade host reboot causes extra downtime.

Avoid scheduling Mattermost upgrades during the automated Sunday **09:00–11:00 UTC** window (~3:00–5:00 AM MDT) unless you disable `mattermost-reboot.timer` and `mattermost-caddy-update.timer` first. See [`15-unattended-updates.md`](15-unattended-updates.md).

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

The build script:

- Fetches the official ARM64 `.sha256` sidecar unless `MM_TARBALL_SHA256` is already set in `.env`
- Passes that digest into the image build and fails if the downloaded tarball does not match
- Runs `mattermost version` inside the built image and fails unless it reports the requested `MM_VERSION`

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
# Internal check (authoritative from the VM)
docker compose --env-file .env -p mattermost -f compose.yml --profile upgrade-test \
  exec -T mattermost-test curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 mattermost-test
/opt/mattermost/ops/health-check.sh
```

`curl -I https://<test-hostname>/` from the VM may return **403** because Caddy restricts the test host to `TEST_ALLOWED_CIDR`. That is expected. Confirm the public test URL from an allowed admin network/browser instead.

Also validate in the browser (from the allowed admin network):

- Login
- Channel load
- Message send
- File upload/download (including image preview)
- Plugins or integrations, if used

Do **not** promote production until those checks pass.

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
