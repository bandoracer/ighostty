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

IDENTITY=$(bash scripts/resolve_codesign_identity.sh)
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
elif [ "$IDENTITY" = "-" ]; then
  echo "warning: no stable signing identity found — ad-hoc signing (TCC grants will not survive rebuilds)"
fi
codesign "${SIGN_ARGS[@]}" "$APP"
echo "Built $APP (signed: $IDENTITY)"
