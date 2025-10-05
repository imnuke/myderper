# myderper

A Docker-based Tailscale DERP server with automatic SSL certificate management via Let's Encrypt and Cloudflare DNS. Supports both IPv4 and IPv6.

## Prerequisites

- Docker and Docker Compose
- A domain name with Cloudflare DNS
- Cloudflare API token with DNS edit permissions
- Tailscale auth key

## Setup

1. Clone this repository
2. Configure your environment variables in .env:
   ```bash
   DOMAIN=<Your Domain Name>
   CLOUDFLARE_API_TOKEN=<Your Cloudflare API Token>
   TS_AUTHKEY=<Your Tailscale Auth Key>
   ```

## Running

Start the services:
```bash
docker compose up -d
```

This will start:
- **tailscaled**: Tailscale daemon
- **certbot**: Automatic SSL certificate issuance and renewal via Let's Encrypt (Cloudflare DNS challenge)
- **derper**: Tailscale DERP relay server

## Ports

- `443/tcp`: HTTPS DERP server
- `9443/tcp`: Alternative HTTPS port
- `3478/udp`: STUN server

## Stopping

```bash
docker compose down
```
