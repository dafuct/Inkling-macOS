#!/bin/bash
# Compares candidate models on the technical-conversation suite (how this user
# actually types) — latency, gate coverage, and side-by-side continuations.
# Built via xcodebuild for the same reason as run-bench.sh: only xcodebuild
# compiles MLX's metallib, so the Metal shaders are found at runtime.
#
# Usage: Scripts/compare-models.sh [model-dir …]
#   no args: compares every model folder under models/
#   args:    compares just those dirs, in order
# One-time prereq: the Metal Toolchain (xcodebuild -downloadComponent MetalToolchain).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -scheme InklingBench -destination 'platform=macOS' \
  -skipMacroValidation -configuration Debug -derivedDataPath .xcbuild build

BIN=".xcbuild/Build/Products/Debug/InklingBench"
echo "running $BIN compare $*"
"$BIN" compare "$@"
