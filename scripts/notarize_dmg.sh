#!/bin/bash
# Submits the release DMG to Apple's notary service and staples the ticket.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-ighostty-notary}"
TIMEOUT="${NOTARY_TIMEOUT:-30m}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
DMG="dist/iGhostty-${VERSION}.dmg"

if [ ! -f "$DMG" ]; then
  echo "error: $DMG does not exist. Run 'make dmg' first." >&2
  exit 1
fi

echo "Submitting $DMG to Apple notary service with keychain profile '$PROFILE'..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --timeout "$TIMEOUT"

echo "Stapling notarization ticket to $DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "Assessing Gatekeeper status..."
spctl -a -vvv -t open --context context:primary-signature "$DMG"

echo "Notarized and stapled $DMG"
