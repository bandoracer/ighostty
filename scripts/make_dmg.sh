#!/bin/bash
# Builds a drag-to-Applications DMG into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/make_app.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
DMG_ROOT="dist/dmg-root"
DMG="dist/iGhostty-${VERSION}.dmg"

rm -rf "$DMG_ROOT"
rm -f "$DMG"
mkdir -p "$DMG_ROOT"

cp -R "dist/iGhostty.app" "$DMG_ROOT/iGhostty.app"
ln -s /Applications "$DMG_ROOT/Applications"
[ -f README.md ] && cp README.md "$DMG_ROOT/README.md"
[ -f LICENSE ] && cp LICENSE "$DMG_ROOT/LICENSE"
[ -f THIRD_PARTY_NOTICES.md ] && cp THIRD_PARTY_NOTICES.md "$DMG_ROOT/THIRD_PARTY_NOTICES.md"

hdiutil create \
  -volname "iGhostty" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG"

rm -rf "$DMG_ROOT"
echo "Built $DMG"
