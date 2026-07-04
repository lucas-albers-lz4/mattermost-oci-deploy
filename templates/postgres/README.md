# PostgreSQL tuning

Postgres performance settings for this deployment live in [`../compose.yml`](../compose.yml) as `command:` `-c` flags on the `postgres` service.

They target a **12 GB / 2 OCPU** OCI Free Tier VM shared with Mattermost production, Caddy, and an idle test Mattermost instance (test app stopped by default; test database remains on this server).

## Current values

| Setting | Value | Purpose |
| --- | --- | --- |
| `mem_limit` | `3g` | Cap Postgres so Mattermost retains headroom |
| `shared_buffers` | `512MB` | Page cache inside Postgres |
| `effective_cache_size` | `2048MB` | Query planner hint for OS cache |
| `maintenance_work_mem` | `128MB` | Autovacuum and index maintenance |
| `work_mem` | `8MB` | Per-sort/hash operation budget |
| `random_page_cost` | `1.1` | SSD-like boot volume |
| `max_connections` | `100` | Sufficient for prod + test Mattermost |

## When to revisit

- **Slow queries or high disk wait** under normal load — consider moving `postgres-data` to a dedicated OCI block volume before raising memory further.
- **OOM or swap pressure** — lower `shared_buffers` or Postgres `mem_limit`, or stop the test Mattermost container when not upgrading.
- **Major VM resize** — if you move off free tier to more RAM, scale `shared_buffers` and `effective_cache_size` proportionally.

See [`docs/14-performance.md`](../../docs/14-performance.md) for the full free-tier performance guide.
