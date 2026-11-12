#!/usr/bin/env bash
# Imports a .p12 into a temporary keychain (GitHub Actions or local CI).
set -euo pipefail

: "${BUILD_CERTIFICATE_BASE64:?Set BUILD_CERTIFICATE_BASE64}"
: "${P12_PASSWORD:?Set P12_PASSWORD}"
: "${KEYCHAIN_PASSWORD:?Set KEYCHAIN_PASSWORD}"

KEYCHAIN_PATH="${RUNNER_TEMP:-$TMPDIR}/kuma-signing.keychain-db"
CERT_PATH="${RUNNER_TEMP:-$TMPDIR}/kuma-certificate.p12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH" $(security list-keychain -d user | tr -d '"')
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" 2>/dev/null || true

rm -f "$CERT_PATH"
echo "Keychain ready: $KEYCHAIN_PATH"
