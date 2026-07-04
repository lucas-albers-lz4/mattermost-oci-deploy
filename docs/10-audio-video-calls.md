# 10 - Audio And Video Calls

This deployment uses integrated Mattermost Calls first. External RTCD is deferred until scale or isolation requirements justify another service.

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

## Mattermost Admin UI

In Mattermost System Console:

1. Go to `Plugins > Calls`.
2. Enable the Calls plugin.
3. Confirm UDP server port is `8443`.
4. Confirm ICE Host Override matches the public production hostname.
5. Save settings.
6. Restart the plugin if Mattermost prompts for it.

## Verification

From the VM:

```sh
sudo ufw status verbose
docker compose --env-file /opt/mattermost/.env -p mattermost -f /opt/mattermost/compose.yml ps
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
