#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain, used only to sign local
# FinderTweaks builds. A stable signature lets macOS keep privacy permissions across rebuilds.
# The private key goes straight into the keychain; nothing is written into the repo.
set -euo pipefail
NAME="FinderTweaks Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "'$NAME' already exists"
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

# /usr/bin/openssl (LibreSSL) writes a PKCS#12 that `security import` understands.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout "pass:$PASS" -out "$TMP/identity.p12"
security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "created '$NAME' in the login keychain"
