#!/usr/bin/env bash

set -euo pipefail

CERT_DIR="proxy/certs"

mkdir -p "$CERT_DIR"

if [[ -f "$CERT_DIR/ca.crt" && -f "$CERT_DIR/server.crt" && -f "$CERT_DIR/server.key" ]]; then
  echo "==> TLS certificates already exist"
  exit 0
fi

echo "==> Generating local CA"

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -days 3650 \
  -nodes \
  -keyout "$CERT_DIR/ca.key" \
  -out "$CERT_DIR/ca.crt" \
  -subj "/CN=Fever Challenge Local CA"

echo "==> Generating server key and CSR"

openssl req \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.csr" \
  -subj "/CN=localhost"

cat > "$CERT_DIR/server.ext" <<'EOF'
subjectAltName = DNS:localhost
extendedKeyUsage = serverAuth
EOF

echo "==> Signing server certificate"

openssl x509 \
  -req \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.crt" \
  -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial \
  -out "$CERT_DIR/server.crt" \
  -days 825 \
  -sha256 \
  -extfile "$CERT_DIR/server.ext"

echo "==> TLS certificates generated"

