#!/usr/bin/env bash
# Generate a long-lived self-signed cert for the DERP server, and print the
# SHA256 fingerprint to paste into the tailnet policy's derpMap.
#
# Run once. Re-run with --force to rotate.

set -euo pipefail

cd "$(dirname "$0")"

CERT_DIR="${CERT_DIR:-./certs}"
DAYS="${DAYS:-3650}"
FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; fi

if [[ -f .env ]]; then
    set -a; . ./.env; set +a
fi

: "${DOMAIN:?DOMAIN not set. Put it in .env or export it.}"

# derper's manualCertManager loads files named after its --hostname flag.
# We use 127.0.0.1 as a placeholder so derper triggers noHostname mode
# (which is what cert-pinning clients need). The cert's CN/SAN below is
# still set to DOMAIN — clients pin by hash anyway, so the cert subject
# is just informational.
CERT_NAME="127.0.0.1"
CRT="$CERT_DIR/$CERT_NAME.crt"
KEY="$CERT_DIR/$CERT_NAME.key"

print_pin() {
    local hash expiry
    hash=$(openssl x509 -in "$CRT" -outform DER | sha256sum | awk '{print $1}')
    expiry=$(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2)
    cat <<EOF

Cert:        $CRT
Key:         $KEY
Valid until: $expiry
Fingerprint: sha256-raw:$hash

Paste into https://login.tailscale.com/admin/acls under "derpMap"
(adjust RegionID/Name as you wish; DERPPort matches your exposed port):

  "derpMap": {
    "OmitDefaultRegions": false,
    "Regions": {
      "900": {
        "RegionID":   900,
        "RegionCode": "myderp",
        "RegionName": "My DERP",
        "Nodes": [{
          "Name":     "myderp-1",
          "RegionID": 900,
          "HostName": "$DOMAIN",
          "DERPPort": 9443,
          "CertName": "sha256-raw:$hash"
        }]
      }
    }
  }
EOF
}

if [[ -e "$CRT" || -e "$KEY" ]] && [[ "$FORCE" -ne 1 ]]; then
    echo "Cert/key already exist at $CERT_DIR. Pass --force to regenerate." >&2
    print_pin
    exit 0
fi

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# ECDSA P-256: small, fast, broadly supported.
TMP_KEY=$(mktemp)
trap 'rm -f "$TMP_KEY"' EXIT
openssl ecparam -name prime256v1 -genkey -noout -out "$TMP_KEY"
openssl req -x509 -new -key "$TMP_KEY" -out "$CRT" \
    -days "$DAYS" \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,IP:127.0.0.1" \
    >/dev/null 2>&1
mv "$TMP_KEY" "$KEY"
trap - EXIT

chmod 600 "$KEY"
chmod 644 "$CRT"

print_pin
