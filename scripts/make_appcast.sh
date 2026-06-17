#!/bin/bash
# Generates Sparkle appcast metadata for the current release DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist)
DMG="dist/iGhostty-${VERSION}.dmg"
UPDATES_DIR="${SPARKLE_UPDATES_DIR:-dist/sparkle-updates}"
TOOLS_DIR="${SPARKLE_TOOLS_DIR:-.build/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-dev.ighostty.app}"
DOWNLOAD_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/bandoracer/ighostty/releases/download/v${VERSION}/}"
MAXIMUM_VERSIONS="${SPARKLE_MAXIMUM_VERSIONS:-1}"
MAXIMUM_DELTAS="${SPARKLE_MAXIMUM_DELTAS:-1}"
case "$DOWNLOAD_PREFIX" in
  */) ;;
  *) DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX}/" ;;
esac

if [ ! -f "$DMG" ]; then
  echo "error: $DMG does not exist. Run 'make dmg' or 'make release-notarized' first." >&2
  exit 1
fi
if [ ! -x "$TOOLS_DIR/generate_appcast" ]; then
  echo "error: Sparkle generate_appcast not found. Run 'swift package resolve' first." >&2
  exit 1
fi

mkdir -p "$UPDATES_DIR"
cp "$DMG" "$UPDATES_DIR/"

NOTES_SRC="${SPARKLE_RELEASE_NOTES:-}"
if [ -n "$NOTES_SRC" ] && [ -f "$NOTES_SRC" ]; then
  cp "$NOTES_SRC" "$UPDATES_DIR/iGhostty-${VERSION}.md"
elif [ ! -f "$UPDATES_DIR/iGhostty-${VERSION}.md" ]; then
  cat > "$UPDATES_DIR/iGhostty-${VERSION}.md" <<EOF
# iGhostty ${VERSION}

Build ${BUILD}.
EOF
fi

"$TOOLS_DIR/generate_appcast" \
  --account "$ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --release-notes-url-prefix "$DOWNLOAD_PREFIX" \
  --maximum-versions "$MAXIMUM_VERSIONS" \
  --maximum-deltas "$MAXIMUM_DELTAS" \
  "$UPDATES_DIR"

cp "$UPDATES_DIR/appcast.xml" dist/appcast.xml

echo "Built Sparkle appcast: dist/appcast.xml"
echo "Upload $DMG and dist/appcast.xml to GitHub release tag v${VERSION}."
