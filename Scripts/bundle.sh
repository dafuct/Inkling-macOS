#!/bin/bash
# Builds Inkling.app. MLX's Metal shaders can only be compiled by xcodebuild
# (not `swift build`), so we build via xcodebuild, then wrap the produced
# executable into a .app and copy the SPM resource bundles (incl. the MLX
# metallib in mlx-swift_Cmlx.bundle) so they're found at runtime.
# One-time prereqs: Scripts/make-signing-cert.sh and the Metal Toolchain
# (xcodebuild -downloadComponent MetalToolchain).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -scheme Inkling -destination 'platform=macOS' \
  -derivedDataPath .xcbuild -skipMacroValidation -configuration Debug build

PRODUCTS=".xcbuild/Build/Products/Debug"
APP="Inkling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/Inkling" "$APP/Contents/MacOS/Inkling"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Resource bundles (MLX metallib, tokenizer assets, …) — needed at runtime.
cp -R "$PRODUCTS"/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true

# Stable self-signed identity so the Accessibility grant persists across rebuilds.
codesign --force --deep --sign "Inkling Dev" "$APP"
echo "Built and signed $APP"
