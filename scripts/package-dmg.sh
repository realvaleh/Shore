#!/usr/bin/env bash
# Package Shore.app into a compressed DMG.
#
# This script MUST run on a Mac with Xcode 15+ installed.
# It cannot run on Linux CI. Notarization is intentionally omitted for v1.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: package-dmg.sh must run on macOS with Xcode 15+." >&2
  echo "This repository is a source scaffold; Linux cannot produce Shore.app or a DMG." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP_NAME="Shore"
SCHEME="Shore"
PROJECT="$ROOT/Shore.xcodeproj"

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD/DerivedData" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64' \
  -allowProvisioningUpdates \
  build

APP="$(find "$BUILD/DerivedData/Build/Products/Release" -name "${APP_NAME}.app" -maxdepth 1 | head -n 1)"
if [[ -z "$APP" ]]; then
  echo "error: Shore.app was not produced. Open Shore.xcodeproj in Xcode and check Signing." >&2
  exit 1
fi

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/${APP_NAME}-1.0.dmg"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

echo
echo "Created $DMG"
echo
echo "Notarization is not part of v1. An unsigned or ad-hoc signed build will be blocked"
echo "by Gatekeeper until the user right-clicks → Open, or until you sign + notarize:"
echo "  xcrun notarytool submit \"$DMG\" --keychain-profile <profile> --wait"
echo "  xcrun stapler staple \"$DMG\""
