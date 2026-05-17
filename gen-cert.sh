#!/usr/bin/env bash
# Generate a CA + leaf cert pair for the DERP server, and print the leaf cert's
# SHA256 fingerprint to paste into the tailnet policy's derpMap.
#
# Two-tier structure is required because Go 1.24+ enforces RFC 5280 compliance
# even with InsecureSkipVerify=true. A self-signed leaf cert (Issuer==Subject
# with CA:FALSE) is rejected as "not standards compliant". A CA-signed leaf cert
# (Issuer!=Subject) passes the compliance check.
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

DERP_PORT="${DERP_PORT:-9443}"

# derper's manualCertManager loads files named after its --hostname flag.
# We use 127.0.0.1 as a placeholder so derper triggers noHostname mode
# (which is what cert-pinning clients need). The cert's CN/SAN below is
# still set to DOMAIN — clients pin by hash anyway, so the cert subject
# is just informational.
CERT_NAME="127.0.0.1"
CRT="$CERT_DIR/$CERT_NAME.crt"   # leaf cert only — served by derper
KEY="$CERT_DIR/$CERT_NAME.key"   # leaf private key
CA_CRT="$CERT_DIR/ca.crt"        # CA cert — only used to sign the leaf
CA_KEY="$CERT_DIR/ca.key"        # CA private key

print_pin() {
    local hash expiry
    # openssl dgst is portable across Linux and macOS; sha256sum is Linux-only.
    hash=$(openssl x509 -in "$CRT" -outform DER | openssl dgst -sha256 | awk '{print $NF}')
    expiry=$(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2)
    cat <<EOF

Cert:        $CRT
Key:         $KEY
Valid until: $expiry
Fingerprint: sha256-raw:$hash

Paste into https://login.tailscale.com/admin/acls under "derpMap":

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
          "DERPPort": $DERP_PORT,
          "CertName": "sha256-raw:$hash"
        }]
      }
    }
  }

After updating the ACL, restart derper so it loads the new cert:
  docker compose restart myderp
EOF
}

if [[ -e "$CRT" || -e "$KEY" ]] && [[ "$FORCE" -ne 1 ]]; then
    echo "Cert/key already exist at $CERT_DIR. Pass --force to regenerate." >&2
    print_pin
    exit 0
fi

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

TMP_CA_KEY=$(mktemp)
TMP_LEAF_KEY=$(mktemp)
TMP_LEAF_CRT=$(mktemp)
TMP_CSR=$(mktemp)
trap 'rm -f "$TMP_CA_KEY" "$TMP_LEAF_KEY" "$TMP_LEAF_CRT" "$TMP_CSR" "$CERT_DIR/ca.srl"' EXIT

# --- Step 1: generate the CA key + self-signed CA cert (CA:TRUE) ---
openssl ecparam -name prime256v1 -genkey -noout -out "$TMP_CA_KEY"
openssl req -x509 -new -key "$TMP_CA_KEY" -out "$CA_CRT" \
    -days "$DAYS" \
    -subj "/CN=myderp-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign" \
    >/dev/null 2>&1

# --- Step 2: generate the leaf key + CSR ---
openssl ecparam -name prime256v1 -genkey -noout -out "$TMP_LEAF_KEY"
openssl req -new -key "$TMP_LEAF_KEY" -out "$TMP_CSR" \
    -subj "/CN=$DOMAIN" \
    >/dev/null 2>&1

# --- Step 3: sign the leaf cert with the CA ---
openssl x509 -req -in "$TMP_CSR" -CA "$CA_CRT" -CAkey "$TMP_CA_KEY" \
    -CAcreateserial \
    -out "$TMP_LEAF_CRT" \
    -days "$DAYS" \
    -extfile <(cat <<EXTEOF
subjectAltName = DNS:$DOMAIN,IP:127.0.0.1
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
EXTEOF
    ) >/dev/null 2>&1

# --- Step 4: serve ONLY the leaf cert (no CA chain) ---
# Tailscale's cert-pinning VerifyConnection rejects connections when more than
# one non-derpkey cert is presented. The CA cert must not be included.
cp "$TMP_LEAF_CRT" "$CRT"
rm -f "$TMP_LEAF_CRT" "$TMP_CSR"

mv "$TMP_CA_KEY"   "$CA_KEY"
mv "$TMP_LEAF_KEY" "$KEY"
trap - EXIT

chmod 600 "$KEY" "$CA_KEY"
chmod 644 "$CRT" "$CA_CRT"

print_pin
