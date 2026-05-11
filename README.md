# myderper

A Docker-based Tailscale DERP server with automatic SSL certificate management via Caddy (Let's Encrypt + Cloudflare DNS-01). Supports both IPv4 and IPv6.

## Prerequisites

- Docker and Docker Compose
- A domain name with Cloudflare DNS
- Cloudflare API token with DNS edit permissions (Zone.DNS.Edit + Zone.Zone.Read)
- Tailscale auth key

## Setup

1. Clone this repository
2. Configure your environment variables in `.env`:
   ```bash
   DOMAIN=<Your Domain Name>
   CLOUDFLARE_API_TOKEN=<Your Cloudflare API Token>
   TS_AUTHKEY=<Your Tailscale Auth Key>
   ```

   Optional: pin the Caddy image version with `CADDY_VERSION=2.11.2`.

## Running

Start the services:
```bash
docker compose up -d
```

This will start:
- **caddy**: Obtains and auto-renews the Let's Encrypt certificate via Cloudflare DNS-01 (cert-only, no exposed ports)
- **tailscaled**: Tailscale daemon (userspace mode), used by derper for `--verify-clients`
- **derper**: Tailscale DERP relay server, reads the cert directly from Caddy's data volume

The `derper` container waits for Caddy to issue the certificate (via healthcheck) before starting.

## Ports

- `443/tcp`: HTTPS DERP server
- `9443/tcp`: Alternative HTTPS port
- `3478/udp`: STUN server

## Stopping

```bash
docker compose down
```

## Notes on certificate renewal

Caddy renews certificates automatically (~30 days before expiry). The derper process reads cert files from a read-only mount of Caddy's data volume, so renewed certs are picked up on the next derper restart. For zero-downtime pickup, restart `derper` after renewal (e.g. monthly cron: `docker compose restart derper`).
