#!/usr/bin/env bash

# Validate host -> QEMU port forwarding -> Gateway REST/WebSocket.
# State-changing parking/retrieval checks require an explicit --write-flow flag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

write_flow=0

usage() {
  cat <<'EOF'
사용법: tools/qemu/verify.sh [--write-flow]

기본 검증은 health, 주차장 snapshot, WebSocket 최초 snapshot을 읽기 전용으로 확인합니다.
--write-flow는 pi-simulator 계열 모드에서만 차량 2대 등록 -> 연속 입차 -> 독립 출차까지 검증합니다.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --write-flow) write_flow=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "지원하지 않는 인자입니다: $1" ;;
  esac
  shift
done

require_command curl
require_command node
validate_configuration
qemu_is_running || die "VM이 실행 중이 아닙니다. 먼저 start.sh를 실행하세요."

gateway_forward_host="$(current_gateway_forward_host)"
base_url="http://${gateway_forward_host}:${SNAP_QEMU_GATEWAY_PORT}"
ws_url="ws://${gateway_forward_host}:${SNAP_QEMU_GATEWAY_PORT}/v1/events"
verifier="${REPO_ROOT}/web-mock/scripts/verify-pi-gateway.mjs"
[ -f "${verifier}" ] || die "Web Mock Gateway 검증기를 찾지 못했습니다: ${verifier}"

info "Gateway health를 확인합니다."
curl --fail --silent --show-error --max-time 5 "${base_url}/health"
printf '\n'

args=(
  "${verifier}"
  --base-url "${base_url}"
  --ws-url "${ws_url}"
  --lot-id demo-01
)
if [ "${write_flow}" -ne 1 ]; then
  args+=(--read-only)
fi

info "REST와 WebSocket 계약을 검증합니다."
node "${args[@]}"

if [ "${write_flow}" -eq 1 ]; then
  info "상태 변경을 포함한 전체 통신 검증을 통과했습니다."
else
  info "읽기 전용 통신 검증을 통과했습니다. 전체 흐름은 --write-flow로 실행하세요."
fi
