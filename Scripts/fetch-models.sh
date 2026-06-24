#!/bin/bash
# Downloads candidate MLX models into ./models/<name> for local (offline) use.
# Requires the Hugging Face CLI. If missing, install into a venv, e.g.:
#   python3 -m venv ~/.cache/hf-venv && ~/.cache/hf-venv/bin/pip install -U "huggingface_hub[cli]"
#   export PATH="$HOME/.cache/hf-venv/bin:$PATH"
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p models

models=(
  "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
  "mlx-community/Llama-3.2-1B-Instruct-4bit"
  "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
)
for repo in "${models[@]}"; do
  name="${repo##*/}"
  echo "=== $repo -> models/$name ==="
  hf download "$repo" --local-dir "models/$name"
done
echo "Done. Models in ./models/"
