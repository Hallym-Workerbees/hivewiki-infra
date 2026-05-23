#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LIVE_DIR="$REPO_ROOT/live"
LOGGING_DIR="$LIVE_DIR/cluster/logging"
LAMBDA_BUILD_SCRIPT="$REPO_ROOT/scripts/build-tenant-dev-ops-lambdas.sh"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/run-dev-only.sh plan
  bash scripts/run-dev-only.sh apply

This runs all shared/dev Terragrunt units while excluding:
  - live/cluster/tenants/prod/**

Then it runs live/cluster/logging separately because logging depends on
other stacks and may optionally read prod RDS outputs.
EOF
}

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

COMMAND="$1"

case "$COMMAND" in
plan | apply) ;;
*)
    echo "Unsupported command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac

echo "[INFO] Running shared/dev units from $LIVE_DIR"
echo "[INFO] Building tenant-dev-ops lambda packages"
bash "$LAMBDA_BUILD_SCRIPT"

(
    cd "$LIVE_DIR"
    terragrunt run --all \
        --working-dir "$LIVE_DIR" \
        --queue-exclude-dir 'cluster/tenants/prod/**' \
        --queue-exclude-dir 'cluster/logging' \
        -- "$COMMAND"
)

echo "[INFO] Running logging separately from $LOGGING_DIR"
(
    cd "$LOGGING_DIR"
    terragrunt "$COMMAND"
)
