#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LAMBDA_ROOT="${LAMBDA_ROOT:-$REPO_ROOT/modules/stacks/tenant-dev-ops/lambda}"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/modules/stacks/tenant-dev-ops/build/lambda}"

if [ ! -d "$LAMBDA_ROOT" ]; then
  echo "[ERROR] Lambda root not found: $LAMBDA_ROOT" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "[ERROR] zip command is required" >&2
  exit 1
fi

if ! command -v python >/dev/null 2>&1; then
  echo "[ERROR] python command is required" >&2
  exit 1
fi

build_lambda() {
  local lambda_dir="$1"
  local name
  local zip_path
  local build_dir
  local tmp_dir
  local venv_dir
  local pip_bin

  name="$(basename "$lambda_dir")"
  build_dir="$BUILD_ROOT/$name"
  zip_path="$build_dir/function.zip"
  tmp_dir="$(mktemp -d)"
  venv_dir="$(mktemp -d)"

  echo "[INFO] Building lambda package: $name"

  mkdir -p "$build_dir"
  cp "$lambda_dir/main.py" "$tmp_dir/"

  if [ -f "$lambda_dir/requirements.txt" ]; then
    python -m venv "$venv_dir"
    pip_bin="$venv_dir/bin/pip"

    "$pip_bin" install \
      --requirement "$lambda_dir/requirements.txt" \
      --target "$tmp_dir" \
      --quiet
  fi

  rm -f "$zip_path"
  (
    cd "$tmp_dir"
    zip -qr "$zip_path" .
  )

  rm -rf "$tmp_dir" "$venv_dir"
}

for lambda_dir in "$LAMBDA_ROOT"/*; do
  [ -d "$lambda_dir" ] || continue
  build_lambda "$lambda_dir"
done
