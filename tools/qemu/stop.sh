#!/usr/bin/env bash

# Ask the guest to power off. TERM is used only with an explicit --force flag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

force=0
wait_seconds=45

usage() {
  cat <<'EOF'
사용법: tools/qemu/stop.sh [--force] [--wait-seconds N]

기본 동작은 SSH와 QEMU monitor로 정상 종료만 요청합니다.
45초 안에 종료되지 않을 때 --force를 지정한 경우에만 QEMU에 TERM을 보냅니다.
강제 종료도 KILL은 사용하지 않습니다.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
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

validate_uint "종료 대기 시간" "${wait_seconds}"

if ! qemu_is_running; then
  cleanup_stale_runtime_files
  info "이미 중지되어 있습니다."
  exit 0
fi

pid="$(read_pid)"
info "VM에 정상 종료를 요청합니다(PID ${pid})."

if ssh_vm 'sudo sh -c "(sleep 1; systemctl poweroff) >/dev/null 2>&1 &"' >/dev/null 2>&1; then
  info "SSH로 poweroff 요청을 전달했습니다."
elif [ -S "${MONITOR_SOCKET}" ] && command -v nc >/dev/null 2>&1; then
  info "SSH가 준비되지 않아 QEMU monitor로 종료를 요청합니다."
  printf 'system_powerdown\n' | nc -w 2 -U "${MONITOR_SOCKET}" >/dev/null 2>&1 || true
fi

elapsed=0
while [ "${elapsed}" -lt "${wait_seconds}" ]; do
  if ! qemu_is_running; then
    cleanup_stale_runtime_files
    info "정상 종료되었습니다."
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "${force}" -ne 1 ]; then
  die "${wait_seconds}초 안에 종료되지 않았습니다. 확인 후 stop.sh --force를 실행하세요."
fi

qemu_is_running || exit 0
info "검증된 QEMU PID ${pid}에 TERM을 보냅니다."
kill -TERM "${pid}"

elapsed=0
while [ "${elapsed}" -lt 10 ]; do
  if ! qemu_is_running; then
    cleanup_stale_runtime_files
    info "TERM으로 종료되었습니다."
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

die "TERM 후에도 실행 중입니다. KILL은 자동 수행하지 않습니다. PID ${pid}를 직접 확인하세요."
