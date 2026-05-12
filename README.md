# myderper

A self-hosted Tailscale DERP relay using a long-lived self-signed certificate, pinned by SHA256 in the tailnet's `derpMap`. No ACME, no renewal, no port 80/443 dependency.

## Why self-signed?

For servers that can't expose 80/443 (ISP blocks, China hosts without ICP filing, etc.), HTTP-01 / TLS-ALPN-01 challenges are unusable. DNS-01 works but means running and renewing an ACME pipeline forever. Self-signed + SHA256 pinning sidesteps all of that:

- DERP traffic is already end-to-end encrypted by WireGuard/Noise; TLS is just transport wrapping. Pinning by hash is cryptographically equivalent to a CA-signed cert for this purpose.
- Tailscale parses `CertName: "sha256-raw:<hex>"` in the derpMap and verifies the leaf cert hash. Mechanism shipped in tailscale **v1.78** ([commit 87546a5](https://github.com/tailscale/tailscale/commit/87546a5edf6b6503a87eeb2d666baba57398a066), Dec 2024). Both derper and clients must be ≥ v1.78.

## Prerequisites

- Docker + Compose
- OpenSSL on the host (for `gen-cert.sh`)
- A Tailscale auth key
- Admin access to https://login.tailscale.com/admin/acls

## Setup

Before first start, configure the tailnet policy and create the auth key — both required by `--advertise-tags=tag:relay` in `docker-compose.yml`. See [Peer relay](#peer-relay) below for the ACL snippet and key creation steps. Then:

```bash
cp example.env .env
$EDITOR .env                       # set DOMAIN and TS_AUTHKEY

./gen-cert.sh                      # 10-year self-signed cert; prints sha256 + derpMap snippet
# → paste the snippet into the tailnet policy at /admin/acls, merging with any existing derpMap

docker compose up -d --build
docker exec tailscaled tailscale set --relay-server-port=40000   # one-time, persists in ts_state
```

Verify on any tailnet client (≥ v1.78):

```bash
tailscale netcheck                 # your custom region should appear with a sensible RTT
tailscale debug derp 900           # replace 900 with your RegionID
```

### Offline / restricted server (build locally, transfer)

If the server can't reach Docker Hub or build from source, build on a workstation and ship a tar:

```bash
# Workstation
docker compose build               # → myderper/derper:v1.96.5
docker pull tailscale/tailscale:v1.96.5
docker save -o images.tar \
    myderper/derper:v1.96.5 \
    tailscale/tailscale:v1.96.5
scp images.tar user@server:/path/to/myderper/

# Server
docker load -i images.tar
docker compose up -d --no-build
```

## Rotation

```bash
./gen-cert.sh --force              # regenerates cert; new SHA256 printed
# → update CertName in the tailnet policy
docker compose restart derper
```

Cert is good for 10 years; rotation is only needed if the key is compromised or you want to bump the curve.

## Ports

- `443/tcp` and `9443/tcp` — both mapped to derper's internal 443; pick whichever your network allows and set it as `DERPPort` in the derpMap.
- `3478/udp` — STUN.
- `40000/udp` (`$PEER_RELAY_PORT`) — peer relay listener (see below).

## Peer relay

This sidecar `tailscaled` doubles as a [peer relay](https://tailscale.com/docs/features/peer-relay) (UDP-based relay tried before DERP, when tailscale clients can't directly reach each other). DERP traffic itself is unaffected — peer relay only handles regular WireGuard peer-to-peer fallback. Requires tailscale ≥ 1.86 on the relay and on clients that want to use it.

**Setup**:

1. In https://login.tailscale.com/admin/acls add:
   ```json
   {
     "tagOwners": {
       "tag:relay": ["autogroup:admin"]
     },
     "grants": [
       {
         "src": ["*"],
         "dst": ["tag:relay"],
         "app": {"tailscale.com/cap/relay": [{}]}
       }
     ]
   }
   ```
2. Create the auth key at https://login.tailscale.com/admin/settings/keys with `tag:relay` pre-authorized. Use it as `TS_AUTHKEY`.
3. Make sure `$PEER_RELAY_PORT` (default 40000/udp) is open in your host firewall and reachable from the public internet for best results.
4. After the first `docker compose up`, apply the relay port (already in the Setup steps above). The pref persists in the `ts_state` volume — only re-run if you wipe the volume.

**Verify** with `tailscale ping <peer>` from a client (≥ v1.86). When peer relay is in use you'll see lines like:

```
pong from peer (100.x.y.z) via peer-relay(<server-ip>:40000:vni:1) in 23ms
```

If you see `via DERP(...)` instead, either direct P2P succeeded (good — no relay needed) or both peer-relay attempts failed (check the host firewall on `$PEER_RELAY_PORT`).

## Design notes

- **`--hostname=127.0.0.1` in `docker-compose.yml`** is intentional. derper's `manualCertManager` only skips SNI validation (allowing the `sha256-raw:...` SNI cert-pinning clients send) when `--hostname` parses as an IP. The user-facing address lives in the derpMap's `HostName` field, decoupled from this internal flag.
- **Cert files are named `certs/127.0.0.1.{crt,key}`** to match the above. The cert's CN/SAN still embed `DOMAIN` for human readability — pinning doesn't care about subject fields.
- **derper is built from upstream `tailscale.com/cmd/derper`** (`derper/Dockerfile`), not a third-party image. Build args: `DERPER_REF`, `GOPROXY`, `GOSUMDB`.

## Files

```
docker-compose.yml      two services: tailscaled (userspace, verify-clients sidecar) + derper
derper/Dockerfile       upstream derper, multi-stage build
gen-cert.sh             cert generator + fingerprint printer
example.env             env template (real .env is gitignored)
certs/                  generated cert/key (gitignored)
```
