#!/usr/bin/env bash

# Shared, side-effect-free configuration and helpers for the SNAP QEMU scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

: "${SNAP_QEMU_VM_DIR:=${HOME}/VMs/snap-qemu}"
: "${SNAP_QEMU_NAME:=snap-qemu-pi}"
: "${SNAP_QEMU_USER:=snap}"
: "${SNAP_QEMU_SSH_PORT:=2222}"
: "${SNAP_QEMU_GATEWAY_PORT:=8101}"
: "${SNAP_QEMU_GATEWAY_FORWARD_HOST:=auto}"
: "${SNAP_QEMU_WEB_PORT:=3101}"
: "${SNAP_QEMU_CPUS:=2}"
: "${SNAP_QEMU_MEMORY_MB:=2048}"
: "${SNAP_QEMU_DISK_SIZE:=8G}"

VM_DIR="${SNAP_QEMU_VM_DIR}"
BASE_DIR="${VM_DIR}/base"
DISK_DIR="${VM_DIR}/disk"
CLOUD_INIT_DIR="${VM_DIR}/cloud-init"
KEYS_DIR="${VM_DIR}/keys"
RUNTIME_DIR="${VM_DIR}/runtime"
ARTIFACT_DIR="${VM_DIR}/artifacts"

BASE_IMAGE="${BASE_DIR}/debian-13-genericcloud-arm64.qcow2"
BASE_CHECKSUM="${BASE_IMAGE}.sha512"
BASE_MANIFEST="${BASE_DIR}/SHA512SUMS"
BASE_SOURCE_RECORD="${BASE_DIR}/source.txt"
DISK_IMAGE="${DISK_DIR}/snap-debian-arm64.qcow2"
SEED_IMAGE="${CLOUD_INIT_DIR}/seed.iso"
SEED_AUTHORIZED_KEY="${CLOUD_INIT_DIR}/authorized-key"
SSH_KEY="${KEYS_DIR}/id_ed25519"
SSH_PUBLIC_KEY="${SSH_KEY}.pub"
KNOWN_HOSTS="${KEYS_DIR}/known_hosts"
PID_FILE="${RUNTIME_DIR}/qemu.pid"
MONITOR_SOCKET="${RUNTIME_DIR}/qemu-monitor.sock"
SERIAL_LOG="${RUNTIME_DIR}/serial.log"
UEFI_VARS="${RUNTIME_DIR}/efi-vars.fd"
GATEWAY_FORWARD_HOST_FILE="${RUNTIME_DIR}/gateway-forward-host"

die() {
  printf '오류: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[SNAP QEMU] %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "필요한 명령을 찾을 수 없습니다: $1"
}

validate_uint() {
  local label="$1"
  local value="$2"
  case "${value}" in
    ''|*[!0-9]*) die "${label} 값은 양의 정수여야 합니다: ${value}" ;;
  esac
  [ "${value}" -gt 0 ] || die "${label} 값은 0보다 커야 합니다: ${value}"
}

validate_port() {
  local label="$1"
  local value="$2"
  validate_uint "${label}" "${value}"
  [ "${value}" -le 65535 ] || die "${label} 값은 65535 이하여야 합니다: ${value}"
}

is_ipv4() {
  local address="$1"
  local octet
  case "${address}" in
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
  esac

  local IFS=.
  set -- ${address}
  [ "$#" -eq 4 ] || return 1
  for octet in "$@"; do
    case "${octet}" in
      ''|*[!0-9]*) return 1 ;;
    esac
    [ "${octet}" -le 255 ] || return 1
  done
}

is_lan_ipv4() {
  local address="$1"
  is_ipv4 "${address}" || return 1

  local IFS=.
  set -- ${address}
  case "$1" in
    10) return 0 ;;
    172) [ "$2" -ge 16 ] && [ "$2" -le 31 ] ;;
    192) [ "$2" -eq 168 ] ;;
    100) [ "$2" -ge 64 ] && [ "$2" -le 127 ] ;;
    169) [ "$2" -eq 254 ] ;;
    *) return 1 ;;
  esac
}

detect_lan_ipv4() {
  local interface details candidate
  require_command ifconfig
  require_command awk

  for interface in en0 en1 en2 en3 en4 en5 en6 en7 en8 en9 en10 en11 en12 en13 en14 en15; do
    details="$(ifconfig "${interface}" 2>/dev/null || true)"
    case "${details}" in
      *'status: active'*) ;;
      *) continue ;;
    esac
    candidate="$(printf '%s\n' "${details}" | awk '$1 == "inet" { print $2; exit }')"
    if is_lan_ipv4 "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_gateway_forward_host() {
  local configured="${SNAP_QEMU_GATEWAY_FORWARD_HOST}"
  if [ "${configured}" = "auto" ]; then
    detect_lan_ipv4 || die \
      "활성 LAN IPv4를 찾지 못했습니다. SNAP_QEMU_GATEWAY_FORWARD_HOST에 이 Mac의 사설 IP를 지정하세요."
    return
  fi
  printf '%s\n' "${configured}"
}

current_gateway_forward_host() {
  local recorded
  if [ -f "${GATEWAY_FORWARD_HOST_FILE}" ]; then
    recorded="$(sed -n '1p' "${GATEWAY_FORWARD_HOST_FILE}")"
    if is_ipv4 "${recorded}" || [ "${recorded}" = "localhost" ]; then
      printf '%s\n' "${recorded}"
      return 0
    fi
  fi
  resolve_gateway_forward_host
}

validate_configuration() {
  case "${VM_DIR}" in
    /*) ;;
    *) die "SNAP_QEMU_VM_DIR은 절대 경로여야 합니다: ${VM_DIR}" ;;
  esac

  case "/${VM_DIR#/}/" in
    *'/../'*|*'/./'*) die "SNAP_QEMU_VM_DIR에 . 또는 .. 경로 조각을 사용할 수 없습니다: ${VM_DIR}" ;;
  esac

  case "${VM_DIR}" in
    /|"${REPO_ROOT}"|"${REPO_ROOT}"/*)
      die "VM 데이터와 SSH 키는 저장소 밖에 두어야 합니다: ${VM_DIR}"
      ;;
  esac

  case "${VM_DIR}" in
    *','*|*$'\n'*) die "QEMU 인자 안전성을 위해 VM 경로에 쉼표나 줄바꿈을 사용할 수 없습니다." ;;
  esac

  validate_port "SSH 포트" "${SNAP_QEMU_SSH_PORT}"
  validate_port "Gateway 포트" "${SNAP_QEMU_GATEWAY_PORT}"
  validate_port "Web Mock 포트" "${SNAP_QEMU_WEB_PORT}"
  [ "${SNAP_QEMU_SSH_PORT}" -ne "${SNAP_QEMU_GATEWAY_PORT}" ] || \
    die "SSH 포트와 Gateway 포트는 달라야 합니다."
  validate_uint "CPU 개수" "${SNAP_QEMU_CPUS}"
  validate_uint "메모리(MB)" "${SNAP_QEMU_MEMORY_MB}"

  local disk_size_number disk_size_unit
  disk_size_unit="${SNAP_QEMU_DISK_SIZE#${SNAP_QEMU_DISK_SIZE%?}}"
  disk_size_number="${SNAP_QEMU_DISK_SIZE%?}"
  case "${disk_size_unit}" in
    M|G) ;;
    *) die "SNAP_QEMU_DISK_SIZE는 8G 또는 8192M 같은 형식이어야 합니다: ${SNAP_QEMU_DISK_SIZE}" ;;
  esac
  validate_uint "가상 디스크 크기" "${disk_size_number}"

  case "${SNAP_QEMU_NAME}" in
    ''|*[!a-zA-Z0-9.-]*) die "SNAP_QEMU_NAME에는 영문, 숫자, 점, 하이픈만 사용할 수 있습니다." ;;
  esac
  case "${SNAP_QEMU_NAME}" in
    [a-zA-Z0-9]*[a-zA-Z0-9]|[a-zA-Z0-9]) ;;
    *) die "SNAP_QEMU_NAME은 영문 또는 숫자로 시작하고 끝나야 합니다." ;;
  esac
  case "${SNAP_QEMU_USER}" in
    ''|*[!a-z_0-9-]*) die "SNAP_QEMU_USER에는 영문 소문자, 숫자, 밑줄, 하이픈만 사용할 수 있습니다." ;;
  esac
  case "${SNAP_QEMU_USER}" in
    [a-z_]*) ;;
    *) die "SNAP_QEMU_USER는 영문 소문자 또는 밑줄로 시작해야 합니다." ;;
  esac

  case "${SNAP_QEMU_GATEWAY_FORWARD_HOST}" in
    auto|127.0.0.1|localhost) ;;
    *)
      is_lan_ipv4 "${SNAP_QEMU_GATEWAY_FORWARD_HOST}" || \
        die "Gateway 포워딩 주소는 auto, loopback 또는 사설 LAN IPv4여야 합니다: ${SNAP_QEMU_GATEWAY_FORWARD_HOST}"
      ;;
  esac
}

ensure_supported_host() {
  [ "$(uname -s)" = "Darwin" ] || die "이 스크립트는 macOS 전용입니다."
  [ "$(uname -m)" = "arm64" ] || die "Apple Silicon(arm64) Mac이 필요합니다."
}

ensure_vm_dir() {
  mkdir -p "${VM_DIR}"

  local canonical_vm_dir
  canonical_vm_dir="$(cd "${VM_DIR}" && pwd -P)"
  case "${canonical_vm_dir}" in
    "${REPO_ROOT}"|"${REPO_ROOT}"/*)
      die "VM 데이터 경로가 심볼릭 링크를 통해 저장소 내부를 가리킵니다: ${canonical_vm_dir}"
      ;;
  esac
  chmod 700 "${VM_DIR}"

  local data_dir canonical_data_dir
  for data_dir in \
    "${BASE_DIR}" \
    "${DISK_DIR}" \
    "${CLOUD_INIT_DIR}" \
    "${KEYS_DIR}" \
    "${RUNTIME_DIR}" \
    "${ARTIFACT_DIR}"; do
    [ ! -L "${data_dir}" ] || die "VM 하위 데이터 디렉터리는 심볼릭 링크일 수 없습니다: ${data_dir}"
    mkdir -p "${data_dir}"
    canonical_data_dir="$(cd "${data_dir}" && pwd -P)"
    case "${canonical_data_dir}" in
      "${canonical_vm_dir}"/*) ;;
      *) die "VM 하위 데이터 디렉터리가 VM 경로 밖을 가리킵니다: ${canonical_data_dir}" ;;
    esac
    chmod 700 "${data_dir}"
  done
}

reject_symlink() {
  local path="$1"
  [ ! -L "${path}" ] || die "보안상 심볼릭 링크 파일은 사용할 수 없습니다: ${path}"
}

read_pid() {
  [ -f "${PID_FILE}" ] || return 1
  local pid
  pid="$(sed -n '1p' "${PID_FILE}")"
  case "${pid}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "${pid}"
}

qemu_is_running() {
  local pid command_line
  pid="$(read_pid)" || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  command_line="$(ps -ww -p "${pid}" -o command= 2>/dev/null || true)"
  case "${command_line}" in
    *qemu-system-aarch64*"${DISK_IMAGE}"*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_stale_runtime_files() {
  qemu_is_running && return 0
  [ -f "${PID_FILE}" ] && rm -f "${PID_FILE}"
  [ -S "${MONITOR_SOCKET}" ] && rm -f "${MONITOR_SOCKET}"
  [ -f "${GATEWAY_FORWARD_HOST_FILE}" ] && rm -f "${GATEWAY_FORWARD_HOST_FILE}"
  return 0
}

port_is_listening() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t >/dev/null 2>&1
}

assert_port_available() {
  local label="$1"
  local port="$2"
  if port_is_listening "${port}"; then
    die "${label} 포트 ${port}가 이미 사용 중입니다. SNAP_QEMU_${label}_PORT 값을 바꾸세요."
  fi
}

ssh_vm() {
  ssh \
    -i "${SSH_KEY}" \
    -p "${SNAP_QEMU_SSH_PORT}" \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${KNOWN_HOSTS}" \
    "${SNAP_QEMU_USER}@127.0.0.1" "$@"
}

scp_to_vm() {
  local source_file="$1"
  local destination="$2"
  scp \
    -i "${SSH_KEY}" \
    -P "${SNAP_QEMU_SSH_PORT}" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${KNOWN_HOSTS}" \
    "${source_file}" "${SNAP_QEMU_USER}@127.0.0.1:${destination}"
}

resolve_firmware_code() {
  if [ -n "${SNAP_QEMU_FIRMWARE_CODE:-}" ]; then
    [ -f "${SNAP_QEMU_FIRMWARE_CODE}" ] || \
      die "지정한 UEFI code 펌웨어가 없습니다: ${SNAP_QEMU_FIRMWARE_CODE}"
    printf '%s\n' "${SNAP_QEMU_FIRMWARE_CODE}"
    return
  fi

  require_command brew
  local candidate
  candidate="$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd"
  [ -f "${candidate}" ] || die "QEMU ARM64 UEFI 펌웨어가 없습니다: ${candidate}"
  printf '%s\n' "${candidate}"
}

resolve_firmware_vars_template() {
  if [ -n "${SNAP_QEMU_FIRMWARE_VARS_TEMPLATE:-}" ]; then
    [ -f "${SNAP_QEMU_FIRMWARE_VARS_TEMPLATE}" ] || \
      die "지정한 UEFI vars 템플릿이 없습니다: ${SNAP_QEMU_FIRMWARE_VARS_TEMPLATE}"
    printf '%s\n' "${SNAP_QEMU_FIRMWARE_VARS_TEMPLATE}"
    return
  fi

  require_command brew
  local candidate
  candidate="$(brew --prefix qemu)/share/qemu/edk2-arm-vars.fd"
  [ -f "${candidate}" ] || die "QEMU ARM64 UEFI vars 템플릿이 없습니다: ${candidate}"
  printf '%s\n' "${candidate}"
}

validate_configuration
