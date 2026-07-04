# 10 - Audio And Video Calls

This deployment uses integrated Mattermost Calls first. External RTCD is deferred until scale or isolation requirements justify another service.

Production only. The test instance does not publish UDP `8443` or Calls environment variables.

## Network

Calls media uses UDP `8443` directly to the Mattermost host. Do not proxy this UDP traffic through Caddy.

Required ingress:

- OCI NSG: `8443/udp` from clients.
- UFW: `8443/udp` from clients.
- Docker Compose: `8443:8443/udp` on `mattermost-prod`.

DNS updates remain manual. The Calls ICE host should be the production hostname after it points to the VM public IP.

## Environment

Production uses these environment variables:

```env
MM_CALLS_UDP_SERVER_ADDRESS=0.0.0.0
MM_CALLS_UDP_SERVER_PORT=8443
MM_CALLS_ICE_HOST_OVERRIDE=<prod-hostname>
```

`MM_CALLS_ICE_HOST_OVERRIDE` must be reachable by clients. Use the public hostname for internet users, or a private/VPN address for private-only users.

Compose also sets:

```yaml
MM_CALLS_DEFAULT_ENABLED: "true"
```

This disables Calls **Test Mode**. When Test Mode is active (`DefaultEnabled=false`), only system admins can start calls. With `DefaultEnabled=true`, all channel members can start and join calls.

DM webcam video (experimental):

```yaml
MM_CALLS_ENABLE_VIDEO: "true"
```

This enables the camera button in **direct message** calls only. Channel/group calls remain audio and screen share.

Compose also enables local-mode admin tooling used to install the Calls plugin:

```yaml
MM_SERVICESETTINGS_ENABLELOCALMODE: "true"
MM_PLUGINSETTINGS_ENABLEUPLOADS: "false"
```

Local mode allows `mmctl --local` from inside the production container. It does not expose a public admin API. Plugin uploads stay disabled after the Calls plugin is installed.

## Install The Calls Plugin

The Mattermost 11.8 server tarball used by this repo does not ship a `prepackaged_plugins` directory. Enabling Calls in `config.json` alone is not enough; the plugin must be installed once on a fresh deployment.

From the VM after the stack is running:

```sh
/opt/mattermost/ops/install-calls-plugin.sh
```

Or manually:

```sh
cd /opt/mattermost
curl -fsSL -o /tmp/calls.tar.gz \
  https://github.com/mattermost/mattermost-plugin-calls/releases/download/v1.12.1/mattermost-plugin-calls-v1.12.1-linux-arm64.tar.gz
docker cp /tmp/calls.tar.gz mattermost-mattermost-prod-1:/mattermost/data/calls.tar.gz
docker compose --env-file .env -p mattermost -f compose.yml exec -u mattermost mattermost-prod \
  /mattermost/bin/mmctl --local plugin add /mattermost/data/calls.tar.gz
docker compose --env-file .env -p mattermost -f compose.yml exec -u mattermost mattermost-prod \
  /mattermost/bin/mmctl --local plugin enable com.mattermost.calls
```

Expected log line after install:

```text
rtc: server is listening on udp 0.0.0.0:8443
```

## Mattermost Admin UI

After the plugin is installed, confirm settings in System Console:

1. Go to `Plugins > Calls`.
2. Confirm the plugin is enabled.
3. Confirm UDP server port is `8443`.
4. Confirm ICE Host Override matches the public production hostname.
5. Save settings if you change anything.
6. Restart the plugin if Mattermost prompts for it.

## Verification

From the VM:

```sh
grep MM_CALLS /opt/mattermost/.env
sudo ufw status verbose | grep 8443
docker compose --env-file /opt/mattermost/.env -p mattermost -f /opt/mattermost/compose.yml ps
docker compose --env-file /opt/mattermost/.env -p mattermost -f /opt/mattermost/compose.yml exec -u mattermost mattermost-prod \
  /mattermost/bin/mmctl --local plugin list
sudo ss -ulnp | grep 8443
/opt/mattermost/ops/health-check.sh
```

From an external machine, confirm UDP reachability with a real call. UDP port checks are often unreliable because the service may not respond like TCP.

Functional browser test:

1. Log in to production.
2. Join a channel.
3. Start a call.
4. Join from a second network/client if possible.
5. Verify audio both ways.
6. Verify video if enabled and expected.

## TURN/STUN Notes

If users are behind strict NAT/firewalls and direct UDP `8443` fails, add a TURN service later. Do not add TURN until direct integrated Calls has been tested, because TURN introduces credentials, another exposed service, and more operational load.
