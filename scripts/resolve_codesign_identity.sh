#!/bin/bash
# Prints the best available signing identity for iGhostty packaging.
set -euo pipefail

if [ -n "${IGHOSTTY_CODESIGN_IDENTITY:-}" ]; then
  echo "$IGHOSTTY_CODESIGN_IDENTITY"
  exit 0
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "$CODESIGN_IDENTITY"
  exit 0
fi

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application: Ryan/ {print $2; exit}')

if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi

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
fi

echo "$IDENTITY"
