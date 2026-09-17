#!/usr/bin/env bash
# Package a Release Shore.app into dist/Shore-<version>.dmg
#
# Must run on a Mac with Xcode 16+ / Swift 6. Linux CI cannot produce Shore.app
# or a DMG. After a successful Mac build, attach the DMG to GitHub Releases:
#   https://github.com/realvaleh/Shore/releases
#
# Notarization is intentionally omitted for v1 (unsigned / ad-hoc).

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: package-dmg.sh must run on macOS with Xcode 16+ / Swift 6." >&2
  echo "This environment cannot compile Shore.app or write a DMG." >&2
  echo "When a Mac-built disk image is published, download it from:" >&2
  echo "  https://github.com/realvaleh/Shore/releases" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build}"
DIST="$ROOT/dist"
APP_NAME="Shore"
SCHEME="Shore"
PROJECT="$ROOT/Shore.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHS="${ARCHS:-arm64}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

VERSION=""
if command -v python3 >/dev/null 2>&1; then
  VERSION="$(
    python3 - "$ROOT/Shore.xcodeproj/project.pbxproj" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"MARKETING_VERSION = ([^;]+);", text)
print(match.group(1).strip().strip('"') if match else "")
PY
  )"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="$(
    grep -m1 "MARKETING_VERSION" "$ROOT/Shore.xcodeproj/project.pbxproj" \
      | sed 's/.*MARKETING_VERSION = //; s/;.*//; s/"//g; s/ //g'
  )"
fi
VERSION="${VERSION:-1.0}"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

echo "Building ${APP_NAME} ${VERSION} (${CONFIGURATION}, ARCHS=${ARCHS})…"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD/DerivedData" \
  -destination 'generic/platform=macOS' \
  ARCHS="$ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGNING_ALLOWED=YES \
  build

PRODUCTS="$BUILD/DerivedData/Build/Products/${CONFIGURATION}"
APP="${PRODUCTS}/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  APP="$(find "$PRODUCTS" -name "${APP_NAME}.app" -maxdepth 2 | head -n 1 || true)"
fi
if [[ -z "${APP}" || ! -d "$APP" ]]; then
  echo "error: Shore.app was not produced. Open Shore.xcodeproj in Xcode and check Signing." >&2
  exit 1
fi

STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

echo
echo "Created $DMG"
echo
echo "Install: open the DMG and drag Shore to Applications."
echo "GitHub Releases: attach this file as a release asset so others can download it."
echo "  https://github.com/realvaleh/Shore/releases"
echo
echo "Gatekeeper (unsigned / ad-hoc v1): right-click Shore.app → Open → Open."
echo "Do not disable Gatekeeper globally."
echo
echo "Notarization is not part of v1. When you have a Developer ID:"
echo "  xcrun notarytool submit \"$DMG\" --keychain-profile <profile> --wait"
echo "  xcrun stapler staple \"$DMG\""
