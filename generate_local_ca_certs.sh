#!/bin/bash
#
# Generate a local Certificate Authority (CA) and a server certificate for
# SODAR signed by that CA.
#
# Why: A self-signed certificate (like the current server.crt) is not trusted
# by any browser. By signing the SODAR certificate with a CA and installing the
# CA into the trusted root store of your machines/browser, HTTPS loads with no
# warnings at all.
#
# What this script produces in config/traefik/tls/:
#   - SODAR_CA.crt   -> the CA certificate (trust this on client machines)
#   - SODAR_CA.key   -> the CA private key (keep safe, used to sign certs)
#   - server.crt     -> SODAR's certificate, signed by the CA
#   - server.key     -> SODAR's private key
#
# Usage:
#   bash scripts/generate_local_ca_certs.sh
#
set -euo pipefail

TLS_DIR="$(cd "$(dirname "$0")/.." && pwd)/config/traefik/tls"
CA_CRT="$TLS_DIR/SODAR_CA.crt"
CA_KEY="$TLS_DIR/SODAR_CA.key"
SERVER_CRT="$TLS_DIR/server.crt"
SERVER_KEY="$TLS_DIR/server.key"
CA_SRL="$TLS_DIR/.ca.srl"

# The hostname / SAN(s) that the certificate must cover.
# Adjust if you reach SODAR at a different name, e.g. "sodar.local", "sodar"
HOST="sodar.local"

mkdir -p "$TLS_DIR"

echo "==> Generating local CA key and certificate ..."
# Self-signed CA, valid for 10 years
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$CA_KEY" \
    -out "$CA_CRT" \
    -subj "/C=DE/O=SODAR Local Development/CN=SODAR Local CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"

echo "==> Generating server key and certificate signing request ..."
openssl req -newkey rsa:2048 -sha256 -nodes \
    -keyout "$SERVER_KEY" \
    -out /tmp/sodar.csr \
    -subj "/C=DE/O=SODAR Local Development/CN=${HOST}"

# Write an extensions file with the SAN (required for modern browsers)
EXTFILE=$(mktemp)
cat > "$EXTFILE" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${HOST},DNS:localhost,IP:127.0.0.1
EOF

echo "==> Signing server certificate with the local CA ..."
openssl x509 -req -in /tmp/sodar.csr \
    -CA "$CA_CRT" -CAkey "$CA_KEY" \
    -CAcreateserial -CAserial "$CA_SRL" \
    -out "$SERVER_CRT" -days 3650 -sha256 \
    -extfile "$EXTFILE"

rm -f "$EXTFILE" /tmp/sodar.csr

echo
echo "Done! The following files were created in $TLS_DIR:"
echo "  SODAR_CA.crt   - CA certificate"
echo "  SODAR_CA.key   - CA private key (keep safe)"
echo "  server.crt     - SODAR server certificate (signed by CA)"
echo "  server.key     - SODAR server private key"
echo
echo "Next steps:"
echo " 1. Restart the SIPROD/Traefik stack so it picks up the new cert:"
echo "      docker compose -f docker-compose.yml -f docker-compose.override.yml.irods \\"
echo "          -f docker-compose.override.yml.davrods -f docker-compose.override.yml.provided-cert restart traefik"
echo " 2. TRUST the CA on every machine/browser that connects to SODAR (see README below)."
echo "    For the VM itself (so VS Code webview is clean) and on your laptop Chrome/Edge."
