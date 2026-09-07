#!/usr/bin/env bash

# Run the Web Mock on the current private LAN address only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
사용법: tools/qemu/web-lan.sh

현재 활성 사설 LAN IPv4를 감지하고 Web Mock을 그 주소의 3101 포트에만 바인딩합니다.
종료할 때는 이 터미널에서 Ctrl+C를 누릅니다.
EOF
  exit 0
fi
[ "$#" -eq 0 ] || die "사용법: tools/qemu/web-lan.sh"

validate_configuration
require_command npm

web_host="$(resolve_gateway_forward_host)"
is_lan_ipv4 "${web_host}" || die "Web Mock LAN 주소는 사설 IPv4여야 합니다: ${web_host}"

WEB_MOCK_DIR="${REPO_ROOT}/web-mock"
[ -f "${WEB_MOCK_DIR}/package.json" ] || die "web-mock/package.json을 찾지 못했습니다."
[ -x "${WEB_MOCK_DIR}/node_modules/.bin/vinext" ] || \
  die "Web Mock 의존성이 없습니다. 먼저 web-mock에서 npm install을 실행하세요."

info "Web Mock을 사설 LAN 주소에만 바인딩합니다."
printf '  다른 컴퓨터 접속: http://%s:%s\n' "${web_host}" "${SNAP_QEMU_WEB_PORT}"
printf '  종료: Ctrl+C\n'

cd "${WEB_MOCK_DIR}"
exec npm run dev -- --hostname "${web_host}"
