#!/usr/bin/env bash

# Download and verify the Debian cloud image, create a copy-on-write VM disk,
# generate a repository-external SSH key, and build a NoCloud seed ISO.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${SNAP_QEMU_IMAGE_NAME:=debian-13-genericcloud-arm64.qcow2}"
: "${SNAP_QEMU_IMAGE_URL:=https://cloud.debian.org/images/cloud/trixie/latest/${SNAP_QEMU_IMAGE_NAME}}"
: "${SNAP_QEMU_CHECKSUMS_URL:=https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS}"

usage() {
  cat <<'EOF'
사용법: tools/qemu/create.sh

환경 변수:
  SNAP_QEMU_VM_DIR       VM 데이터 경로(기본 ~/VMs/snap-qemu)
  SNAP_QEMU_DISK_SIZE    가상 디스크 최대 크기(기본 8G)
  SNAP_QEMU_IMAGE_URL    Debian 13 genericcloud ARM64 이미지 URL
  SNAP_QEMU_CHECKSUMS_URL  Debian SHA512SUMS URL

기존 VM 디스크나 SSH 키는 덮어쓰지 않습니다.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
[ "$#" -eq 0 ] || die "지원하지 않는 인자입니다: $*"

ensure_supported_host
require_command curl
require_command hdiutil
require_command qemu-img
require_command shasum
require_command ssh-keygen
require_command cp
ensure_vm_dir

for managed_file in \
  "${BASE_IMAGE}" \
  "${BASE_CHECKSUM}" \
  "${BASE_MANIFEST}" \
  "${DISK_IMAGE}" \
  "${SEED_IMAGE}" \
  "${SEED_AUTHORIZED_KEY}" \
  "${SSH_KEY}" \
  "${SSH_PUBLIC_KEY}" \
  "${UEFI_VARS}"; do
  reject_symlink "${managed_file}"
done

if qemu_is_running; then
  die "실행 중인 VM에는 create를 적용할 수 없습니다. 먼저 stop.sh를 실행하세요."
fi

if [ ! -f "${SSH_KEY}" ]; then
  info "VM 전용 SSH 키를 생성합니다: ${SSH_KEY}"
  ssh-keygen -q -t ed25519 -N '' -C "${SNAP_QEMU_USER}@${SNAP_QEMU_NAME}" -f "${SSH_KEY}"
  chmod 600 "${SSH_KEY}"
else
  info "기존 SSH 키를 유지합니다: ${SSH_KEY}"
fi

if [ ! -f "${SSH_PUBLIC_KEY}" ]; then
  ssh-keygen -y -f "${SSH_KEY}" >"${SSH_PUBLIC_KEY}"
  chmod 644 "${SSH_PUBLIC_KEY}"
fi

checksum=""
if [ -f "${BASE_CHECKSUM}" ]; then
  checksum="$(sed -n '1p' "${BASE_CHECKSUM}")"
fi

case "${checksum}" in
  ''|*[!0-9a-fA-F]*) checksum='' ;;
esac
[ -z "${checksum}" ] || [ "${#checksum}" -eq 128 ] || checksum=''

if [ -z "${checksum}" ] && [ -f "${BASE_MANIFEST}" ]; then
  checksum="$(awk -v name="${SNAP_QEMU_IMAGE_NAME}" '$2 == name || $2 == "*" name { print $1; exit }' "${BASE_MANIFEST}")"
fi

case "${checksum}" in
  ''|*[!0-9a-fA-F]*) checksum='' ;;
esac
[ -z "${checksum}" ] || [ "${#checksum}" -eq 128 ] || checksum=''

if [ -z "${checksum}" ]; then
  checksums_tmp="${BASE_MANIFEST}.part"
  info "Debian SHA512 체크섬 목록을 받습니다."
  curl --fail --location --retry 3 --output "${checksums_tmp}" "${SNAP_QEMU_CHECKSUMS_URL}"
  checksum="$(awk -v name="${SNAP_QEMU_IMAGE_NAME}" '$2 == name || $2 == "*" name { print $1; exit }' "${checksums_tmp}")"
  case "${checksum}" in
    ''|*[!0-9a-fA-F]*)
      rm -f "${checksums_tmp}"
      die "SHA512SUMS에서 이미지 체크섬을 찾지 못했습니다: ${SNAP_QEMU_IMAGE_NAME}"
      ;;
  esac
  [ "${#checksum}" -eq 128 ] || die "이미지 SHA512 체크섬 형식이 올바르지 않습니다."
  mv "${checksums_tmp}" "${BASE_MANIFEST}"
fi

if [ ! -f "${BASE_IMAGE}" ]; then
  image_tmp="${BASE_IMAGE}.part"
  info "Debian 13 ARM64 cloud 이미지를 받습니다(중단 시 이어받기 가능)."
  curl --fail --location --retry 3 --continue-at - --output "${image_tmp}" "${SNAP_QEMU_IMAGE_URL}"
  actual_checksum="$(shasum -a 512 "${image_tmp}" | awk '{print $1}')"
  if [ "${actual_checksum}" != "${checksum}" ]; then
    rm -f "${image_tmp}"
    die "다운로드한 Debian 이미지의 SHA512 체크섬이 일치하지 않습니다."
  fi
  mv "${image_tmp}" "${BASE_IMAGE}"
else
  info "기존 Debian base 이미지를 검증합니다."
  actual_checksum="$(shasum -a 512 "${BASE_IMAGE}" | awk '{print $1}')"
  [ "${actual_checksum}" = "${checksum}" ] || \
    die "기존 base 이미지의 SHA512 체크섬이 저장된 값과 다릅니다: ${BASE_IMAGE}"
fi
printf '%s\n' "${checksum}" >"${BASE_CHECKSUM}"
chmod 0444 "${BASE_IMAGE}"
cat >"${BASE_SOURCE_RECORD}" <<EOF
image_url=${SNAP_QEMU_IMAGE_URL}
checksums_url=${SNAP_QEMU_CHECKSUMS_URL}
sha512=${checksum}
EOF

if [ ! -f "${DISK_IMAGE}" ]; then
  info "${SNAP_QEMU_DISK_SIZE} copy-on-write VM 디스크를 생성합니다."
  qemu-img create \
    -f qcow2 \
    -F qcow2 \
    -b "${BASE_IMAGE}" \
    "${DISK_IMAGE}" \
    "${SNAP_QEMU_DISK_SIZE}"
else
  info "기존 VM 디스크를 유지합니다: ${DISK_IMAGE}"
fi
qemu-img check -q "${DISK_IMAGE}" || die "VM 디스크 또는 backing chain 검증에 실패했습니다."

if [ ! -f "${UEFI_VARS}" ]; then
  firmware_vars_template="$(resolve_firmware_vars_template)"
  info "VM 전용 writable UEFI vars 파일을 생성합니다."
  cp "${firmware_vars_template}" "${UEFI_VARS}"
  chmod 0600 "${UEFI_VARS}"
else
  info "기존 VM UEFI vars를 유지합니다: ${UEFI_VARS}"
fi

public_key="$(tr -d '\r\n' <"${SSH_PUBLIC_KEY}")"
[ -n "${public_key}" ] || die "SSH 공개 키가 비어 있습니다: ${SSH_PUBLIC_KEY}"

if [ -f "${SEED_IMAGE}" ]; then
  [ -f "${SEED_AUTHORIZED_KEY}" ] || \
    die "기존 seed.iso의 키 기록이 없습니다. seed와 디스크를 임의로 교체하지 마세요."
  recorded_key="$(tr -d '\r\n' <"${SEED_AUTHORIZED_KEY}")"
  [ "${recorded_key}" = "${public_key}" ] || \
    die "현재 SSH 키와 기존 seed.iso의 키가 다릅니다. 기존 VM 파일을 먼저 백업하세요."
  info "기존 cloud-init seed를 유지합니다: ${SEED_IMAGE}"
else
  seed_dir="$(mktemp -d "${CLOUD_INIT_DIR}/.seed.XXXXXX")"
  seed_tmp="${CLOUD_INIT_DIR}/.seed.$$.iso"
  cleanup_seed() {
    rm -rf "${seed_dir}"
    rm -f "${seed_tmp}" "${seed_tmp}.iso"
  }
  trap cleanup_seed EXIT

  instance_id="${SNAP_QEMU_NAME}-$(date -u +%Y%m%dT%H%M%SZ)"
  cat >"${seed_dir}/meta-data" <<EOF
instance-id: ${instance_id}
local-hostname: ${SNAP_QEMU_NAME}
EOF

  cat >"${seed_dir}/user-data" <<EOF
#cloud-config
hostname: ${SNAP_QEMU_NAME}
manage_etc_hosts: true
users:
  - name: ${SNAP_QEMU_USER}
    gecos: SNAP Gateway
    groups: [adm, sudo]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${public_key}
ssh_pwauth: false
disable_root: true
growpart:
  mode: auto
  devices: ["/"]
resize_rootfs: true
EOF

  info "cloud-init NoCloud seed ISO를 생성합니다."
  hdiutil makehybrid \
    -o "${seed_tmp}" \
    "${seed_dir}" \
    -iso \
    -joliet \
    -default-volume-name CIDATA \
    -iso-volume-name CIDATA \
    -joliet-volume-name CIDATA \
    -quiet
  if [ ! -f "${seed_tmp}" ] && [ -f "${seed_tmp}.iso" ]; then
    mv "${seed_tmp}.iso" "${seed_tmp}"
  fi
  [ -f "${seed_tmp}" ] || die "hdiutil이 seed ISO를 생성하지 못했습니다."
  mv "${seed_tmp}" "${SEED_IMAGE}"
  printf '%s\n' "${public_key}" >"${SEED_AUTHORIZED_KEY}"
  trap - EXIT
  rm -rf "${seed_dir}"
fi

info "환경 생성 완료"
printf '  VM 데이터: %s\n' "${VM_DIR}"
printf '  VM 디스크: %s\n' "${DISK_IMAGE}"
printf '  SSH 키:   %s (저장소 밖, Git 비추적)\n' "${SSH_KEY}"
printf '다음 단계: %s/start.sh\n' "${SCRIPT_DIR}"
