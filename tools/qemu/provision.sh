#!/usr/bin/env bash

# Package the local pi-bridge, install it as an immutable release in the VM,
# and run it through a systemd service.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
사용법: tools/qemu/provision.sh

현재 저장소의 pi-bridge를 VM으로 복사하고 Python 가상환경과 systemd 서비스를 구성합니다.
패키지 설치를 위해 VM의 Debian 저장소에 인터넷으로 연결할 수 있어야 합니다.
EOF
  exit 0
fi
[ "$#" -eq 0 ] || die "사용법: tools/qemu/provision.sh"

require_command scp
require_command ssh
require_command tar
validate_configuration
ensure_vm_dir

qemu_is_running || die "VM이 실행 중이 아닙니다. 먼저 start.sh를 실행하세요."
[ -f "${SSH_KEY}" ] || die "SSH 키가 없습니다. 먼저 create.sh를 실행하세요."
ssh_vm true >/dev/null 2>&1 || die "VM SSH가 아직 준비되지 않았습니다. status.sh로 확인하세요."

gateway_forward_host="$(current_gateway_forward_host)"
web_origin_host="${gateway_forward_host}"
cors_origins="${SNAP_QEMU_WEB_ORIGINS:-http://localhost:${SNAP_QEMU_WEB_PORT},http://127.0.0.1:${SNAP_QEMU_WEB_PORT},http://${web_origin_host}:${SNAP_QEMU_WEB_PORT}}"
case "${cors_origins}" in
  ''|*[!a-zA-Z0-9:/.,_-]*) die "SNAP_QEMU_WEB_ORIGINS에 안전하지 않은 문자가 있습니다." ;;
esac

PI_BRIDGE_DIR="${REPO_ROOT}/pi-bridge"
[ -f "${PI_BRIDGE_DIR}/requirements.txt" ] || die "pi-bridge/requirements.txt를 찾지 못했습니다."
[ -f "${PI_BRIDGE_DIR}/app/__main__.py" ] || die "pi-bridge/app/__main__.py를 찾지 못했습니다."

artifact_dir="${ARTIFACT_DIR}"
mkdir -p "${artifact_dir}"
archive="$(mktemp "${artifact_dir}/pi-bridge.XXXXXX")"
remote_archive="/tmp/snap-pi-bridge.tgz"
cleanup_local() {
  rm -f "${archive}"
}
trap cleanup_local EXIT

info "로컬 pi-bridge를 패키징합니다."
tar -czf "${archive}" \
  --exclude='./.venv' \
  --exclude='./__pycache__' \
  --exclude='*/__pycache__' \
  --exclude='./.pytest_cache' \
  --exclude='./.mypy_cache' \
  --exclude='./.ruff_cache' \
  -C "${PI_BRIDGE_DIR}" .

info "패키지를 VM으로 복사합니다."
scp_to_vm "${archive}" "${remote_archive}"

release_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
case "${release_id}" in
  *[!0-9TZ-]*) die "내부 release ID가 안전하지 않습니다." ;;
esac

info "VM에 Python 환경과 systemd 서비스를 구성합니다."
ssh_vm "bash -s -- '${release_id}' '${SNAP_QEMU_GATEWAY_PORT}' '${remote_archive}' '${cors_origins}'" <<'REMOTE_SCRIPT'
set -euo pipefail

release_id="$1"
gateway_port="$2"
remote_archive="$3"
cors_origins="$4"
snap_root="${HOME}/snap"
release_dir="${snap_root}/releases/${release_id}"

case "${release_id}" in
  ''|*[!0-9TZ-]*) printf '안전하지 않은 release ID\n' >&2; exit 1 ;;
esac
case "${gateway_port}" in
  ''|*[!0-9]*) printf '안전하지 않은 Gateway 포트\n' >&2; exit 1 ;;
esac
[ "${gateway_port}" -gt 0 ] && [ "${gateway_port}" -le 65535 ] || exit 1
[ "${remote_archive}" = "/tmp/snap-pi-bridge.tgz" ] || exit 1
case "${cors_origins}" in
  ''|*[!a-zA-Z0-9:/.,_-]*) printf '안전하지 않은 CORS origin 목록\n' >&2; exit 1 ;;
esac

cleanup_remote() {
  rm -f "${remote_archive}"
}
trap cleanup_remote EXIT

sudo -n true
if command -v cloud-init >/dev/null 2>&1; then
  sudo cloud-init status --wait
fi
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv ca-certificates curl

mkdir -p "${snap_root}/releases"
[ ! -e "${release_dir}" ] || { printf 'release가 이미 존재합니다: %s\n' "${release_dir}" >&2; exit 1; }
mkdir "${release_dir}"
tar -xzf "${remote_archive}" -C "${release_dir}"

python3 -m venv "${release_dir}/.venv"
"${release_dir}/.venv/bin/python" -m pip install --upgrade pip
"${release_dir}/.venv/bin/python" -m pip install -r "${release_dir}/requirements.txt"

unit_tmp="$(mktemp)"
cat >"${unit_tmp}" <<UNIT
[Unit]
Description=SNAP Raspberry Pi Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${snap_root}/current
Environment=SNAP_GATEWAY_HOST=0.0.0.0
Environment=SNAP_GATEWAY_PORT=${gateway_port}
Environment=SNAP_CORS_ORIGINS=${cors_origins}
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=${snap_root}/current/.venv/bin/python -m app
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

sudo install -m 0644 "${unit_tmp}" /etc/systemd/system/snap-gateway.service
rm -f "${unit_tmp}"

ln -sfn "${release_dir}" "${snap_root}/current"
sudo systemctl daemon-reload
sudo systemctl enable --now snap-gateway.service
sudo systemctl restart snap-gateway.service

for _ in $(seq 1 30); do
  if curl --fail --silent --max-time 2 "http://127.0.0.1:${gateway_port}/health" >/dev/null; then
    systemctl --no-pager --full status snap-gateway.service | sed -n '1,12p'
    exit 0
  fi
  sleep 1
done

sudo journalctl -u snap-gateway.service -n 50 --no-pager >&2
exit 1
REMOTE_SCRIPT

info "Gateway 배포 완료"
printf '  Health: http://%s:%s/health\n' "${gateway_forward_host}" "${SNAP_QEMU_GATEWAY_PORT}"
printf '  허용 Web Origin: %s\n' "${cors_origins}"
printf '다음 단계: %s/verify.sh\n' "${SCRIPT_DIR}"
