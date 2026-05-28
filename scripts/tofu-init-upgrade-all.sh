#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v tofu >/dev/null 2>&1; then
  echo "error: 'tofu' command not found in PATH" >&2
  exit 1
fi

mapfile -t dirs < <(
  cd "$ROOT_DIR"
  find . \
    \( -path '*/.terragrunt-cache/*' -o -path '*/.terraform/*' \) -prune -o \
    -name '.terraform.lock.hcl' -print \
    | sed 's|/\.terraform\.lock\.hcl$||' \
    | sort
)

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No .terraform.lock.hcl files found under $ROOT_DIR"
  exit 0
fi

for dir in "${dirs[@]}"; do
  echo "==> $dir"
  (
    cd "$ROOT_DIR/$dir"
    tofu init -upgrade -backend=false -input=false
  )
done
