#!/bin/bash
# Builds iGhostty.app into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/iGhostty.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/iGhostty "$APP/Contents/MacOS/iGhostty"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Support/AppIcon.icns ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/gen_icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f README.md ] && cp README.md "$APP/Contents/Resources/README.md"
[ -f LICENSE ] && cp LICENSE "$APP/Contents/Resources/LICENSE"
[ -f THIRD_PARTY_NOTICES.md ] && cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

# Login-item agent (started by launchd with --background).
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp Support/dev.ighostty.background.plist "$APP/Contents/Library/LaunchAgents/"

# Sign with a stable identity so TCC grants (Accessibility for the
# double-tap hotkey) survive rebuilds. Ad-hoc signatures change every build,
# which makes macOS treat each build as a brand-new app.
IDENTITY="${IGHOSTTY_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development: Ryan/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "warning: no stable signing identity found — ad-hoc signing (TCC grants will not survive rebuilds)"
fi
codesign --force -s "$IDENTITY" "$APP"
echo "Built $APP (signed: $IDENTITY)"
