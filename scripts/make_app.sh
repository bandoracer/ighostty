#!/bin/bash
# Builds iGhostty.app into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/iGhostty.app"
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/iGhostty "$APP/Contents/MacOS/iGhostty"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
else
  echo "error: Sparkle.framework was not found at $SPARKLE_FRAMEWORK" >&2
  exit 1
fi

ICON_COMPOSER_SOURCE="Support/AppIcon.icon"
if [ -d "$ICON_COMPOSER_SOURCE" ]; then
  ICON_WORK="$(mktemp -d)"
  NORMALIZED_ICON="$ICON_WORK/AppIcon.icon"
  ICON_BUILD="$ICON_WORK/build"
  ICON_INFO="$ICON_WORK/icon-info.plist"
  mkdir -p "$ICON_BUILD"

  swift scripts/normalize_icon_composer.swift "$ICON_COMPOSER_SOURCE" "$NORMALIZED_ICON"
  xcrun actool "$NORMALIZED_ICON" \
    --compile "$ICON_BUILD" \
    --output-format human-readable-text \
    --notices --warnings --errors \
    --output-partial-info-plist "$ICON_INFO" \
    --app-icon AppIcon \
    --include-all-app-icons \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --platform macosx \
    --skip-app-store-deployment

  cp "$ICON_BUILD/Assets.car" "$APP/Contents/Resources/Assets.car"
  cp "$ICON_BUILD/AppIcon.icns" Support/AppIcon.icns
elif [ ! -f Support/AppIcon.icns ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/gen_icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f README.md ] && cp README.md "$APP/Contents/Resources/README.md"
[ -f LICENSE ] && cp LICENSE "$APP/Contents/Resources/LICENSE"
[ -f THIRD_PARTY_NOTICES.md ] && cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
[ -f GHOSTTY_PARITY.md ] && cp GHOSTTY_PARITY.md "$APP/Contents/Resources/GHOSTTY_PARITY.md"
if [ -d Support/GhosttyResources ]; then
  cp -R Support/GhosttyResources "$APP/Contents/Resources/GhosttyResources"
  chmod +x "$APP/Contents/Resources/GhosttyResources/bin/ghostty"
fi

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

if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
  for nested in \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign "${SIGN_ARGS[@]}" "$nested"
  done
fi
codesign "${SIGN_ARGS[@]}" "$APP"
echo "Built $APP (signed: $IDENTITY)"
