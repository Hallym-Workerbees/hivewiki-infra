#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/home/chaewoon/dev/capstone/hivewiki-infra}"
LIVE_DIR="$REPO_ROOT/live"
LOGGING_DIR="$LIVE_DIR/cluster/logging"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run-dev-only.sh plan
  bash scripts/run-dev-only.sh apply

This runs all shared/dev Terragrunt units while excluding:
  - live/cluster/tenants/prod/**

Then it runs live/cluster/logging separately.
EOF
}

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

COMMAND="$1"

case "$COMMAND" in
  plan|apply)
    ;;
  *)
    echo "Unsupported command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac

echo "[INFO] Running shared/dev units from $LIVE_DIR"
(
  cd "$LIVE_DIR"
  terragrunt run --all \
    --queue-exclude-dir 'cluster/tenants/prod/**' \
    --queue-exclude-dir 'cluster/logging' \
    -- "$COMMAND"
)

echo "[INFO] Running logging separately from $LOGGING_DIR"
(
  cd "$LOGGING_DIR"
  terragrunt "$COMMAND"
)
