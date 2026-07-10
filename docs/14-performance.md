# 14 - Performance

This deployment targets OCI Free Tier **2 OCPU / 12 GB RAM** on a single VM. Performance work focuses on resource sharing and predictable operation, not custom binary compiles or alternate search backends.

## Resource budget

| Component | Normal operation | Notes |
| --- | --- | --- |
| `mattermost-prod` | Running | `mem_limit: 4g`, `GOMAXPROCS=2`, `GOMEMLIMIT=3750MiB` |
| `mattermost-test` | **Stopped** | Compose profile `upgrade-test`; frees ~2 GB and CPU |
| `postgres` | Running | `mem_limit: 3g`, tuned `-c` flags in compose |
| `caddy` | Running | Small footprint |

Postgres and Mattermost use **official prebuilt ARM64 binaries**. Recompiling with `-march=native` or building Postgres from source is intentionally out of scope.

## Search: Bleve is intentional

Mattermost uses **Bleve** for search indexing (`MM_BLEVESETTINGS_INDEXDIR`). For a small private community this is adequate.

**Deferred:** Elasticsearch or OpenSearch — adds RAM, ops complexity, and cost without clear benefit at this scale. Revisit only if search latency or index size becomes a measured problem.

## Idle test instance

The test Mattermost container exists for **upgrade and restore validation**, not daily use. It uses the Compose profile `upgrade-test` and is **not started** by default:

```sh
docker compose --env-file .env -p mattermost -f compose.yml up -d
```

Manage the test instance on the VM:

```sh
/opt/mattermost/ops/manage-test-instance.sh start   # before upgrade validation
/opt/mattermost/ops/manage-test-instance.sh stop    # after validation (normal idle state)
/opt/mattermost/ops/manage-test-instance.sh status
```

While test is stopped:

- Production is unaffected.
- The test **database** remains in Postgres (backups still include it).
- The test hostname returns **502** for allowed admin CIDR clients until you start test again.

Fresh deploys and `deploy-from-zero.sh` validate test once, then stop it automatically.

## PostgreSQL tuning

Settings are inline on the `postgres` service in `compose.yml`. Summary:

| Setting | Value |
| --- | --- |
| `mem_limit` | `3g` |
| `shared_buffers` | `512MB` |
| `effective_cache_size` | `2048MB` |
| `maintenance_work_mem` | `128MB` |
| `work_mem` | `8MB` |
| `random_page_cost` | `1.1` |
| `max_connections` | `100` |

Verify on the VM:

```sh
docker compose --env-file .env -p mattermost -f compose.yml exec postgres \
  psql -U postgres -c 'SHOW shared_buffers'
```

See also [`templates/postgres/README.md`](../templates/postgres/README.md).

### Disk I/O

Postgres data, Bleve indexes, and local backup staging share the boot volume. Live Mattermost attachments use the OCI Object Storage `mattermost-files` bucket (S3 driver), so upload growth should not fill the boot volume. If you see sustained slow queries or high I/O wait under normal load, **move `postgres-data` to a dedicated OCI block volume** before chasing CPU optimizations.

## Mattermost production runtime

Production sets conservative Go and SQL pool limits in `compose.yml`:

- `GOMAXPROCS=2` — matches the VM when test is idle
- `GOMEMLIMIT=3750MiB` — headroom below the 4 GB Docker cap
- `MM_SQLSETTINGS_MAXOPENCONNS=25`, `MM_SQLSETTINGS_MAXIDLECONNS=10`

When test is running during upgrades, test uses `GOMAXPROCS=1` and `GOMEMLIMIT=1800MiB` so both instances do not assume full CPU.

## Health checks

`health-check.sh` always validates production. It **skips** test internal HTTP when the test container is absent or stopped and logs `SKIP: mattermost-test idle`.

## Upgrade workflow

See [`07-upgrades.md`](07-upgrades.md): start test at the beginning of an upgrade, validate, deploy production, then stop test.

## Non-goals

- Custom `-march=native` Postgres or Mattermost builds
- Elasticsearch / OpenSearch
- Separate Postgres block volume (documented as a future option when I/O is measured as the bottleneck)
- Horizontal scaling or Kubernetes
