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
ALLOW_UNNOTARIZED="${IGHOSTTY_ALLOW_UNNOTARIZED_APPCAST:-0}"
case "$DOWNLOAD_PREFIX" in
  */) ;;
  *) DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX}/" ;;
esac

if [ ! -f "$DMG" ]; then
  echo "error: $DMG does not exist. Run 'make release' first." >&2
  exit 1
fi
if [ ! -x "$TOOLS_DIR/generate_appcast" ]; then
  echo "error: Sparkle generate_appcast not found. Run 'swift package resolve' first." >&2
  exit 1
fi
if [ "$ALLOW_UNNOTARIZED" != "1" ]; then
  if ! assess_output=$(spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1); then
    echo "error: $DMG is not accepted by Gatekeeper." >&2
    echo "$assess_output" >&2
    echo "Run 'make release' so the DMG is notarized and stapled before generating the appcast." >&2
    exit 1
  fi
  if [[ "$assess_output" != *"source=Notarized Developer ID"* ]]; then
    echo "error: $DMG is accepted, but not as a notarized Developer ID artifact." >&2
    echo "$assess_output" >&2
    echo "Run 'make release' so the DMG is notarized and stapled before generating the appcast." >&2
    exit 1
  fi
  if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "error: $DMG does not have a valid stapled notarization ticket." >&2
    echo "Run 'make release' so the DMG is notarized and stapled before generating the appcast." >&2
    exit 1
  fi
else
  echo "warning: allowing unnotarized appcast generation because IGHOSTTY_ALLOW_UNNOTARIZED_APPCAST=1" >&2
fi

mkdir -p "$UPDATES_DIR"
cp "$DMG" "$UPDATES_DIR/"

NOTES_SRC="${SPARKLE_RELEASE_NOTES:-}"
NOTES_DEST="$UPDATES_DIR/iGhostty-${VERSION}.md"
if [ -n "$NOTES_SRC" ]; then
  if [ ! -f "$NOTES_SRC" ]; then
    echo "error: SPARKLE_RELEASE_NOTES points to a missing file: $NOTES_SRC" >&2
    exit 1
  fi
  cp "$NOTES_SRC" "$NOTES_DEST"
else
  NOTES_TMP="$(mktemp)"
  if awk -v version="$VERSION" '
    BEGIN { found = 0; emitted = 0 }
    $0 ~ "^## \\[" version "\\]" {
      found = 1
      print "# iGhostty " version
      print ""
      next
    }
    found && /^## \[/ { exit }
    found {
      print
      if ($0 !~ /^[[:space:]]*$/) { emitted = 1 }
    }
    END {
      if (!found) { exit 2 }
      if (!emitted) { exit 3 }
    }
  ' CHANGELOG.md > "$NOTES_TMP"; then
    mv "$NOTES_TMP" "$NOTES_DEST"
  else
    status=$?
    rm -f "$NOTES_TMP"
    if [ "$status" -eq 2 ]; then
      echo "error: CHANGELOG.md is missing a ## [${VERSION}] release section." >&2
    elif [ "$status" -eq 3 ]; then
      echo "error: CHANGELOG.md release section for ${VERSION} has no notes." >&2
    else
      echo "error: failed to generate release notes for ${VERSION} from CHANGELOG.md." >&2
    fi
    echo "Add proper release notes before running make appcast/release." >&2
    exit 1
  fi
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
echo "Built Sparkle release notes: $NOTES_DEST"
echo "Upload $DMG, dist/appcast.xml, $NOTES_DEST, and any referenced delta files to GitHub release tag v${VERSION}."
