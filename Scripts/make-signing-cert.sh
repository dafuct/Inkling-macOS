#!/bin/bash
# Creates a stable self-signed "Inkling Dev" code-signing identity in the login
# keychain, so dev rebuilds keep their TCC (Accessibility) grant instead of
# getting a new ad-hoc hash every time. Idempotent — safe to re-run.
set -euo pipefail
KC="$HOME/Library/Keychains/login.keychain-db"
OSSL=/usr/bin/openssl   # macOS LibreSSL produces an Apple-importable PKCS#12

if security find-identity -v | grep -q "Inkling Dev"; then
  echo "Identity 'Inkling Dev' already present — nothing to do."
  exit 0
fi

tmp=$(mktemp -d)
cat > "$tmp/cert.cnf" <<'EOF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Inkling Dev
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
"$OSSL" req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" >/dev/null 2>&1
"$OSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "Inkling Dev" -out "$tmp/id.p12" -passout pass:x >/dev/null 2>&1
security import "$tmp/id.p12" -k "$KC" -P x -A
rm -rf "$tmp"
echo "Created 'Inkling Dev' signing identity."
