#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA_PATH:-$ROOT/.derivedData}"
SPM_DIR="${CLONED_SOURCE_PACKAGES_DIR:-$ROOT/.spm}"
APP="$DERIVED/Build/Products/Release/Kuma.app"

cd "$ROOT"

XCODEBUILD_ARGS=(
  -scheme Kuma
  -configuration Release
  -destination 'platform=macOS'
  -derivedDataPath "$DERIVED"
  -clonedSourcePackagesDirPath "$SPM_DIR"
)

if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  XCODEBUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$MACOS_SIGN_IDENTITY"
    CODE_SIGN_ENTITLEMENTS="$ROOT/Kuma/Kuma.entitlements"
  )
  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
  fi
else
  # Local/CI ad-hoc: avoid Xcode Automatic + team when no Mac Development cert is installed.
  XCODEBUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
  )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" build

if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  chmod +x "$ROOT/Scripts/mac-sign-app.sh"
  "$ROOT/Scripts/mac-sign-app.sh" "$APP"
else
  echo "MACOS_SIGN_IDENTITY not set — ad-hoc signing (Gatekeeper warning for downloads)."
  codesign --force --deep --sign - "$APP"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Kuma-${VERSION}.dmg"
ICON_SRC="$APP/Contents/Resources/AppIcon.icns"

mkdir -p "$ROOT/dist"
STAGING="$(mktemp -d)"
ditto "$APP" "$STAGING/Kuma.app"
ln -s /Applications "$STAGING/Applications"

if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$STAGING/.VolumeIcon.icns"
  SetFile -a C "$STAGING" 2>/dev/null || true
fi

rm -f "$DMG"
hdiutil create -volname "Kuma" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_NOTARIZATION_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  chmod +x "$ROOT/Scripts/mac-notarize-dmg.sh"
  "$ROOT/Scripts/mac-notarize-dmg.sh" "$DMG"
else
  echo "Notarization skipped (set APPLE_ID, APPLE_TEAM_ID, APPLE_NOTARIZATION_PASSWORD to enable)."
fi

hdiutil verify "$DMG"
ls -lh "$DMG"
echo "DMG ready: $DMG"
