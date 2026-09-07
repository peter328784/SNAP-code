#!/usr/bin/env bash

# Report QEMU process, SSH readiness, and Gateway health independently.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  printf '사용법: tools/qemu/status.sh\n'
  exit 0
fi
[ "$#" -eq 0 ] || die "사용법: tools/qemu/status.sh"
validate_configuration
require_command curl
require_command lsof

printf 'SNAP QEMU 상태\n'
printf '  VM 데이터: %s\n' "${VM_DIR}"
printf '  SSH 포워딩: 127.0.0.1:%s -> VM:22\n' "${SNAP_QEMU_SSH_PORT}"

if ! qemu_is_running; then
  printf '  QEMU: STOPPED\n'
  exit 1
fi

gateway_forward_host="$(current_gateway_forward_host)"
printf '  Gateway 포워딩: %s:%s -> VM:%s\n' \
  "${gateway_forward_host}" "${SNAP_QEMU_GATEWAY_PORT}" "${SNAP_QEMU_GATEWAY_PORT}"
printf '  다른 컴퓨터 접속: http://%s:%s\n' \
  "${gateway_forward_host}" "${SNAP_QEMU_WEB_PORT}"
printf '  QEMU: RUNNING (PID %s)\n' "$(read_pid)"

if ssh_vm true >/dev/null 2>&1; then
  printf '  SSH: READY\n'
else
  printf '  SSH: NOT READY\n'
fi

health_url="http://${gateway_forward_host}:${SNAP_QEMU_GATEWAY_PORT}/health"
if health="$(curl --fail --silent --show-error --max-time 3 "${health_url}" 2>/dev/null)"; then
  printf '  Gateway: READY %s\n' "${health}"
else
  printf '  Gateway: NOT READY\n'
fi

printf '  부팅 로그: %s\n' "${SERIAL_LOG}"
