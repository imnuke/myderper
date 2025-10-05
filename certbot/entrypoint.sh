#!/bin/sh
set -e

# generate credentials file dynamically
mkdir -p /secrets
echo "dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}" > /secrets/cloudflare.ini
chmod 600 /secrets/cloudflare.ini

# issue certificate
certbot certonly --non-interactive --agree-tos \
  --dns-cloudflare \
  --dns-cloudflare-credentials /secrets/cloudflare.ini \
  --cert-name mycert \
  -d "${DOMAIN}"

# paths required by derper
cd /etc/letsencrypt/live/mycert
ln -sf fullchain.pem "${DOMAIN}.crt"
ln -sf privkey.pem "${DOMAIN}.key"
cd -

# try to renew certificate every 12 hours
while :; do
  certbot renew -q \
    --dns-cloudflare \
    --dns-cloudflare-credentials /secrets/cloudflare.ini
  sleep 12h
done