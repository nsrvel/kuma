#!/usr/bin/env bash
# Signs a Release .app for distribution (Developer ID + hardened runtime).
set -euo pipefail

APP="${1:?Usage: mac-sign-app.sh /path/to/Kuma.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="${MACOS_SIGN_ENTITLEMENTS:-$ROOT/Kuma/Kuma.entitlements}"
IDENTITY="${MACOS_SIGN_IDENTITY:?Set MACOS_SIGN_IDENTITY (e.g. \"Developer ID Application: Your Name (TEAMID)\")}"

if [[ ! -d "$APP" ]]; then
  echo "error: not an app bundle: $APP" >&2
  exit 1
fi

sign_item() {
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
}

if [[ -d "$APP/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    sign_item "$item"
  done < <(find "$APP/Contents/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi

if [[ -d "$APP/Contents/PlugIns" ]]; then
  while IFS= read -r -d '' plug; do
    sign_item "$plug"
  done < <(find "$APP/Contents/PlugIns" -depth -type d -name '*.xctest' -print0 2>/dev/null || true)
fi

if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "Signed: $APP"
