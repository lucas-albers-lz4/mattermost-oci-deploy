# 04 - DNS And TLS

## Hostnames

Use two DNS names that point to the OCI VM public IP:

- Production: `<prod-hostname>`
- Test: `<test-hostname>`

## DNS Process

For each hostname:

1. Create or update the DNS `A` record.
2. Point it at the OCI VM public IP.
3. Wait for DNS to resolve.

Verify from your workstation:

```sh
dig +short <prod-hostname>
dig +short <test-hostname>
```

## TLS

Caddy terminates HTTPS and manages certificates automatically.

Template:

```caddyfile
{$PROD_HOSTNAME} {
  reverse_proxy mattermost-prod:8000
}

{$TEST_HOSTNAME} {
  @allowed remote_ip {$TEST_ALLOWED_CIDR}
  handle @allowed {
    reverse_proxy mattermost-test:8000
  }
  respond "Forbidden" 403
}
```

The deploy flow renders hostnames into `/opt/mattermost/.env`, and Caddy reads them from the Compose environment.

## Test Access Restriction

The test hostname is public DNS, but Caddy restricts access by source IP/CIDR.

If your admin public IP changes, update `TEST_ALLOWED_CIDR` in `/opt/mattermost/.env` or rerender the environment, then recreate Caddy:

```sh
cd /opt/mattermost
docker compose --env-file .env -p mattermost -f compose.yml up -d caddy
```

## Verification

```sh
curl -I https://<prod-hostname>/
curl -I https://<test-hostname>/
```

From outside the allowed test CIDR, test should return `403`.

Mattermost app ports should not respond directly from the public internet:

```sh
curl --connect-timeout 5 http://<vm-public-ip>:8000/
```
