#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/home/chaewoon/dev/capstone/hivewiki-infra}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/tg-force-unlock.sh <relative-state-dir> <lock-id>

Examples:
  bash scripts/tg-force-unlock.sh live/cluster/tenants/dev/cache b5af4326-df0b-2185-1e7d-87fe8121a736
  bash scripts/tg-force-unlock.sh live/cluster/edge 9f63cf29-4652-ee1d-2c4b-786bfb29eaeb
EOF
}

if [ $# -ne 2 ]; then
  usage
  exit 1
fi

TARGET_DIR_INPUT="$1"
LOCK_ID="$2"

if [[ "$TARGET_DIR_INPUT" = /* ]]; then
  TARGET_DIR="$TARGET_DIR_INPUT"
else
  TARGET_DIR="$REPO_ROOT/$TARGET_DIR_INPUT"
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "[ERROR] Directory not found: $TARGET_DIR" >&2
  exit 1
fi

echo "[INFO] Unlocking $TARGET_DIR"
echo "[INFO] Lock ID: $LOCK_ID"

cd "$TARGET_DIR"
terragrunt force-unlock "$LOCK_ID"
