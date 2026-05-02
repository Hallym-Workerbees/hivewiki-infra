#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/environments/dev/infra"
VPC_DIR="$ROOT_DIR/environments/dev/vpc"
WORK_DIR="${WORK_DIR:-/tmp/hivewiki-dev-vpc-state-migration}"

INFRA_STATE_BACKUP="$WORK_DIR/dev-infra.current.tfstate"
VPC_STATE_BACKUP="$WORK_DIR/dev-vpc.current.tfstate"
INFRA_STATE_NEXT="$WORK_DIR/dev-infra.after-move.tfstate"
VPC_STATE_NEXT="$WORK_DIR/dev-vpc.after-move.tfstate"
MOVE_LIST_FILE="$WORK_DIR/dev-vpc-move.txt"

ADDRESSES=(
  'aws_security_group.vpce'
  'aws_vpc_security_group_ingress_rule.allow_vpc'
  'module.vpc.aws_eip.regional_nat["ap-northeast-2a"]'
  'module.vpc.aws_internet_gateway.igw'
  'module.vpc.aws_route_table.db_rtb'
  'module.vpc.aws_route_table.private_rtb'
  'module.vpc.aws_route_table.public_rtb'
  'module.vpc.aws_route_table_association.db_rtb["a"]'
  'module.vpc.aws_route_table_association.db_rtb["c"]'
  'module.vpc.aws_route_table_association.private_rtb["a"]'
  'module.vpc.aws_route_table_association.private_rtb["c"]'
  'module.vpc.aws_route_table_association.public_rtb["a"]'
  'module.vpc.aws_route_table_association.public_rtb["c"]'
  'module.vpc.aws_subnet.db["a"]'
  'module.vpc.aws_subnet.db["c"]'
  'module.vpc.aws_subnet.private["a"]'
  'module.vpc.aws_subnet.private["c"]'
  'module.vpc.aws_subnet.public["a"]'
  'module.vpc.aws_subnet.public["c"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["cloudwatch_logs"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["ec2"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["ecr_api"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["ecr_dkr"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["eks"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["eks_auth"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["s3"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["sqs"]'
  'module.vpc_endpoints.aws_vpc_endpoint.this["sts"]'
)

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

state_list_filter() {
  local state_cmd=("$@")
  "${state_cmd[@]}" | rg \
    -e '^module\.vpc' \
    -e '^aws_security_group\.vpce' \
    -e '^aws_vpc_security_group_ingress_rule\.allow_vpc' \
    -e '^module\.vpc_endpoints' || true
}

ensure_dirs() {
  mkdir -p "$WORK_DIR"
}

write_move_list() {
  : > "$MOVE_LIST_FILE"
  printf '%s\n' "${ADDRESSES[@]}" >> "$MOVE_LIST_FILE"
}

verify_prereqs() {
  require_cmd tofu
  require_cmd rg

  [[ -d "$INFRA_DIR" ]] || fail "infra dir not found: $INFRA_DIR"
  [[ -d "$VPC_DIR" ]] || fail "vpc dir not found: $VPC_DIR"
}

backup_states() {
  log "pulling current remote states"
  tofu -chdir="$INFRA_DIR" state pull > "$INFRA_STATE_BACKUP"
  tofu -chdir="$VPC_DIR" state pull > "$VPC_STATE_BACKUP"

  cp "$INFRA_STATE_BACKUP" "$INFRA_STATE_NEXT"
  cp "$VPC_STATE_BACKUP" "$VPC_STATE_NEXT"
}

show_current_state() {
  log "current VPC-related resources in infra state"
  state_list_filter tofu -chdir="$INFRA_DIR" state list

  log "current VPC-related resources in vpc state"
  state_list_filter tofu -chdir="$VPC_DIR" state list
}

move_addresses() {
  local addr

  log "moving remaining VPC resources from infra state file to vpc state file"
  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    log "moving $addr"
    tofu state mv \
      -state="$INFRA_STATE_NEXT" \
      -state-out="$VPC_STATE_NEXT" \
      "$addr" "$addr" >/dev/null
  done < "$MOVE_LIST_FILE"
}

verify_local_files() {
  local infra_remaining
  local vpc_present

  log "verifying local post-move state files"
  infra_remaining="$(state_list_filter tofu state list -state="$INFRA_STATE_NEXT")"
  vpc_present="$(state_list_filter tofu state list -state="$VPC_STATE_NEXT")"

  if [[ -n "$infra_remaining" ]]; then
    printf '%s\n' "$infra_remaining" >&2
    fail "infra local state still contains VPC resources"
  fi

  if [[ -z "$vpc_present" ]]; then
    fail "vpc local state is empty after move"
  fi

  log "local verification passed"
}

push_states() {
  log "pushing updated states to remote backends"
  tofu -chdir="$VPC_DIR" state push "$VPC_STATE_NEXT"
  tofu -chdir="$INFRA_DIR" state push "$INFRA_STATE_NEXT"
}

show_next_steps() {
  cat <<EOF

State migration completed.

Backups:
  $INFRA_STATE_BACKUP
  $VPC_STATE_BACKUP

Updated local copies:
  $INFRA_STATE_NEXT
  $VPC_STATE_NEXT

Recommended next commands:
  tofu -chdir=environments/dev/vpc state list | rg \\
    -e '^module\\.vpc' \\
    -e '^aws_security_group\\.vpce' \\
    -e '^aws_vpc_security_group_ingress_rule\\.allow_vpc' \\
    -e '^module\\.vpc_endpoints'

  tofu -chdir=environments/dev/vpc plan
  tofu -chdir=environments/dev/vpc apply
  tofu -chdir=environments/dev/infra plan
  tofu -chdir=environments/dev/infra apply
EOF
}

main() {
  verify_prereqs
  ensure_dirs
  write_move_list
  show_current_state
  backup_states
  move_addresses
  verify_local_files
  push_states
  show_next_steps
}

main "$@"
