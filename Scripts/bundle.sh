#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="Inkling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Inkling" "$APP/Contents/MacOS/Inkling"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Sign with the stable self-signed "Inkling Dev" identity so TCC keeps the
# Accessibility grant across rebuilds (ad-hoc would change the hash each time).
# Create it once with Scripts/make-signing-cert.sh if it's missing.
codesign --force --sign "Inkling Dev" "$APP"
echo "Built and signed $APP"
