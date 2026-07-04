#!/bin/bash
# Builds a SLIM Inkling.dmg — the .app WITHOUT any model bundled inside, so it
# fits well under GitHub's 2 GB release-asset limit (tens of MB). On first run
# the app has no model; the recipient fetches one into the app's models dir (or
# ~/Library/Application Support) — see README / Scripts/fetch-models.sh.
#
# NOT notarized (no paid Apple Developer account): on first launch the recipient
# must clear quarantine — right-click → Open, or:
#   xattr -dr com.apple.quarantine /Applications/Inkling.app
# Then grant Accessibility (System Settings → Privacy & Security → Accessibility).
#
# Usage: Scripts/make-slim-dmg.sh   (output: Inkling-slim.dmg)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Inkling.app"
DMG="Inkling-slim.dmg"

echo "==> 1/3 Building $APP (xcodebuild + assemble + sign)…"
./Scripts/bundle.sh

echo "==> 2/3 Staging with an /Applications symlink (no model bundled)…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> 3/3 Creating compressed DMG…"
rm -f "$DMG"
hdiutil create -volname "Inkling" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Done: $DMG ($(du -sh "$DMG" | cut -f1)) — no model bundled"
