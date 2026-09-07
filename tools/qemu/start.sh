#!/usr/bin/env bash

# Start the headless ARM64 VM with localhost-only SSH and LAN Gateway forwarding.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

wait_seconds=120

usage() {
  cat <<'EOF'
사용법: tools/qemu/start.sh [--no-wait] [--wait-seconds N]

기본적으로 VM을 시작한 후 SSH가 준비될 때까지 최대 120초 기다립니다.
--no-wait를 사용하면 QEMU 프로세스 시작 직후 반환합니다.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-wait) wait_seconds=0 ;;
    --wait-seconds)
      shift
      [ "$#" -gt 0 ] || die "--wait-seconds 값이 필요합니다."
      wait_seconds="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "지원하지 않는 인자입니다: $1" ;;
  esac
  shift
done

case "${wait_seconds}" in
  ''|*[!0-9]*) die "SSH 대기 시간은 0 이상의 정수여야 합니다: ${wait_seconds}" ;;
esac
validate_configuration
ensure_supported_host
require_command lsof
require_command qemu-system-aarch64
require_command ssh
ensure_vm_dir

[ -f "${BASE_IMAGE}" ] || die "base 이미지가 없습니다. 먼저 create.sh를 실행하세요."
[ -f "${DISK_IMAGE}" ] || die "VM 디스크가 없습니다. 먼저 create.sh를 실행하세요."
[ -f "${SEED_IMAGE}" ] || die "cloud-init seed가 없습니다. 먼저 create.sh를 실행하세요."
[ -f "${SSH_KEY}" ] || die "VM SSH 키가 없습니다. 먼저 create.sh를 실행하세요."
[ -f "${UEFI_VARS}" ] || die "VM UEFI vars가 없습니다. 먼저 create.sh를 실행하세요."

gateway_forward_host="$(resolve_gateway_forward_host)"

if qemu_is_running; then
  current_forward_host="$(current_gateway_forward_host)"
  [ "${current_forward_host}" = "${gateway_forward_host}" ] || \
    die "VM은 ${current_forward_host}에 바인딩되어 있습니다. 네트워크 변경을 반영하려면 stop.sh 후 start.sh를 실행하세요."
  info "이미 실행 중입니다(PID $(read_pid))."
  exit 0
fi
cleanup_stale_runtime_files

assert_port_available SSH "${SNAP_QEMU_SSH_PORT}"
assert_port_available GATEWAY "${SNAP_QEMU_GATEWAY_PORT}"

[ "${#MONITOR_SOCKET}" -lt 100 ] || \
  die "QEMU monitor 소켓 경로가 너무 깁니다. SNAP_QEMU_VM_DIR을 더 짧게 지정하세요."

firmware_code="$(resolve_firmware_code)"
info "ARM64 VM을 시작합니다."
qemu-system-aarch64 \
  -name "${SNAP_QEMU_NAME}" \
  -machine virt \
  -accel hvf \
  -cpu host \
  -smp "${SNAP_QEMU_CPUS}" \
  -m "${SNAP_QEMU_MEMORY_MB}" \
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=${firmware_code}" \
  -drive "if=pflash,format=raw,unit=1,file=${UEFI_VARS}" \
  -drive "if=none,file=${DISK_IMAGE},format=qcow2,id=system,discard=unmap" \
  -device virtio-blk-pci,drive=system \
  -drive "if=none,file=${SEED_IMAGE},format=raw,readonly=on,id=seed" \
  -device virtio-blk-pci,drive=seed \
  -device virtio-rng-pci \
  -netdev "user,id=net0,ipv6=off,hostfwd=tcp:127.0.0.1:${SNAP_QEMU_SSH_PORT}-:22,hostfwd=tcp:${gateway_forward_host}:${SNAP_QEMU_GATEWAY_PORT}-:${SNAP_QEMU_GATEWAY_PORT}" \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -serial "file:${SERIAL_LOG}" \
  -monitor "unix:${MONITOR_SOCKET},server=on,wait=off" \
  -daemonize \
  -pidfile "${PID_FILE}"

qemu_is_running || die "QEMU가 시작 직후 종료됐습니다. ${SERIAL_LOG}를 확인하세요."
reject_symlink "${GATEWAY_FORWARD_HOST_FILE}"
printf '%s\n' "${gateway_forward_host}" >"${GATEWAY_FORWARD_HOST_FILE}"
chmod 600 "${GATEWAY_FORWARD_HOST_FILE}"
info "시작 완료(PID $(read_pid))"
printf '  SSH:     ssh -i %q -p %s %s@127.0.0.1\n' "${SSH_KEY}" "${SNAP_QEMU_SSH_PORT}" "${SNAP_QEMU_USER}"
printf '  Gateway: http://%s:%s\n' "${gateway_forward_host}" "${SNAP_QEMU_GATEWAY_PORT}"
printf '  Web Mock: http://%s:%s\n' "${gateway_forward_host}" "${SNAP_QEMU_WEB_PORT}"
printf '  부팅 로그: %s\n' "${SERIAL_LOG}"

if [ "${wait_seconds}" -eq 0 ]; then
  exit 0
fi

info "SSH 준비를 최대 ${wait_seconds}초 기다립니다."
elapsed=0
while [ "${elapsed}" -lt "${wait_seconds}" ]; do
  if ssh_vm true >/dev/null 2>&1; then
    info "SSH 연결 준비 완료"
    exit 0
  fi
  if ! qemu_is_running; then
    die "부팅 중 QEMU가 종료됐습니다. ${SERIAL_LOG}를 확인하세요."
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

info "VM은 실행 중이지만 SSH가 아직 준비되지 않았습니다. status.sh로 다시 확인하세요."
exit 2
