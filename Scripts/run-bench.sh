#!/bin/bash
# Runs InklingBench (the confidence-threshold tuning harness) with MLX's Metal
# shaders available. `swift run` CANNOT compile the metallib — only xcodebuild can
# (same reason Scripts/bundle.sh exists for the app). Building the bench via
# xcodebuild produces mlx-swift_Cmlx.bundle next to the executable, so the metallib
# is found at runtime.
#
# Usage: Scripts/run-bench.sh [model-dir]
#   default model-dir: models/gemma-4-e4b-it-4bit
# One-time prereq: the Metal Toolchain (xcodebuild -downloadComponent MetalToolchain).
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:-models/gemma-4-e4b-it-4bit}"

xcodebuild -scheme InklingBench -destination 'platform=macOS' \
  -skipMacroValidation -configuration Debug -derivedDataPath .xcbuild build

BIN=".xcbuild/Build/Products/Debug/InklingBench"
echo "running $BIN $MODEL"
"$BIN" "$MODEL"
