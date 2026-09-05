#!/bin/sh
# ======================================================================
# Generate self-signed TLS certs for local HTTPS.
#
#   It requires `openssl` on your PATH... OR run it inside the app
#   container which already has it:
#
#     sh docker/nginx/tools/generate-ssl.sh
#     docker compose exec -T app sh docker/nginx/tools/generate-ssl.sh
#
# Output: docker/nginx/certs/{localhost.crt,localhost.key}
# For a browser-trusted cert on macOS/Windows instead, use `mkcert`:
#     mkcert -cert-file docker/nginx/certs/localhost.crt \
#            -key-file  docker/nginx/certs/localhost.key localhost 127.0.0.1
# ======================================================================
set -e

DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/certs"
mkdir -p "$DIR"

openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$DIR/localhost.key" \
    -out "$DIR/localhost.crt" \
    -days 825 \
    -subj "/C=US/ST=Local/L=Local/O=Dev/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

echo "TLS certs written: $DIR/{localhost.crt,localhost.key}"