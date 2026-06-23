#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="Inkling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Inkling" "$APP/Contents/MacOS/Inkling"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature so TCC can pin permissions to a stable identity.
codesign --force --sign - "$APP"
echo "Built and signed $APP"
