#!/usr/bin/env bash
# Submits a DMG to Apple notarization and staples the ticket (requires Apple Developer Program).
set -euo pipefail

DMG="${1:?Usage: mac-notarize-dmg.sh /path/to/Kuma.dmg}"

APPLE_ID="${APPLE_ID:?Set APPLE_ID}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
# App-specific password from https://appleid.apple.com (not your Apple ID password)
NOTARY_PASSWORD="${APPLE_NOTARIZATION_PASSWORD:?Set APPLE_NOTARIZATION_PASSWORD}"

echo "Submitting $DMG for notarization..."
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized and stapled: $DMG"
