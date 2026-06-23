#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="CotypistDev.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Cotypist" "$APP/Contents/MacOS/Cotypist"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature so TCC can pin permissions to a stable identity.
codesign --force --sign - "$APP"
echo "Built and signed $APP"
