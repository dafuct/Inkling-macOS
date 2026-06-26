#!/bin/bash
# Builds a self-contained, self-signed Inkling.dmg with one model bundled inside
# the .app (Contents/Resources/models/<name>), so it runs on any Apple-Silicon
# Mac (macOS 14+) WITHOUT the dev source tree. The portable model-path lookup in
# ModelConfig.modelsRoot finds the bundled model first.
#
# NOT notarized (no paid Apple Developer account): on first launch the recipient
# must clear quarantine — right-click → Open, or:
#   xattr -dr com.apple.quarantine /Applications/Inkling.app
# Then grant Accessibility (System Settings → Privacy & Security → Accessibility).
#
# Usage: Scripts/make-dmg.sh [model-dir-name]   (default: gemma-4-e4b-it-4bit)
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:-gemma-4-e4b-it-4bit}"
SRC_MODEL="models/$MODEL"
APP="Inkling.app"
DMG="Inkling.dmg"
IDENTITY="Inkling Dev"

[ -d "$SRC_MODEL" ] || { echo "ERROR: model not found at $SRC_MODEL"; exit 1; }

echo "==> 1/5 Building $APP (xcodebuild + assemble + sign)…"
./Scripts/bundle.sh

echo "==> 2/5 Bundling model '$MODEL' inside the app…"
DEST="$APP/Contents/Resources/models"
rm -rf "$DEST"; mkdir -p "$DEST"
cp -R "$SRC_MODEL" "$DEST/"

echo "==> 3/5 Re-signing (adding resources invalidated the signature)…"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature OK"

echo "==> 4/5 Staging with an /Applications symlink…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> 5/5 Creating compressed DMG…"
rm -f "$DMG"
hdiutil create -volname "Inkling" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Done: $DMG ($(du -sh "$DMG" | cut -f1)), model: $MODEL"
