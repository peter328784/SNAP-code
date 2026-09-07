# S.N.A.P QEMU ARM64 가상 보드 구축·사용 가이드

이 문서는 Apple Silicon Mac에서 QEMU ARM64 가상 보드를 만들고, 그 안에 S.N.A.P Raspberry Pi Gateway를 배포해 Web Mock과 REST·WebSocket 통신을 검증하는 방법을 기록한다.

## 검증 범위

이 환경은 `Web Mock → Mac 포트 포워딩 → QEMU ARM64 Debian → Pi Gateway`를 검증한다.

- 검증 가능: ARM64 Linux 부팅, Gateway 자동 시작, REST, WebSocket, 주차·출차 상태 전이, 연결 해제와 재연결
- 검증 불가: Raspberry Pi 4의 실제 GPIO, UART, Bluetooth, 라인트레이싱 센서, Arduino, 바퀴·집게 모터
- 화면 경로는 현재 `targetSlot + job.state`로 Web Mock이 그린다. 실제 waypoint 경로 출력은 아직 아니다.

QEMU의 `raspi4b` 모델은 실제 Pi 하드웨어에 더 가깝지만 가상 Ethernet 제약이 있으므로, 네트워크 Gateway 검증에는 공식 범용 ARM64 `virt` 보드를 사용한다.

## 현재 구축 기준

다음 구성을 기준으로 작성했다. 실제 버전과 LAN 주소는 실행 환경에서 다시 확인한다.

| 항목 | 값 |
|---|---|
| 호스트 | Apple Silicon `arm64`, macOS |
| QEMU | Homebrew QEMU 11.1.0 |
| 게스트 | Debian 13 Trixie genericcloud ARM64 |
| VM 데이터 | `~/VMs/snap-qemu` |
| SSH | Mac `127.0.0.1:2222` → VM `22` |
| 호스트 LAN IP | `<HOST-LAN-IP>` (네트워크 변경 시 달라질 수 있음) |
| Gateway | Mac `<LAN-IP>:8101` → VM `8101` |
| Web Mock | `http://<LAN-IP>:3101` |
| 기본 자원 | CPU 2개, RAM 2GB, 최대 디스크 8GB |

VM 이미지, 개인 SSH 키, 로그는 Git 저장소 밖에 저장된다. `tools/qemu/`에는 재현 가능한 스크립트만 둔다.

## 같은 네트워크의 다른 컴퓨터에서 접속

이 Mac과 접속할 컴퓨터를 같은 Wi-Fi 또는 유선 LAN에 연결한 뒤 다음 순서로 실행한다.

```bash
cd /path/to/snap
tools/qemu/start.sh
tools/qemu/provision.sh
tools/qemu/web-lan.sh
```

현재 네트워크에서는 다른 컴퓨터의 브라우저에서 다음 주소를 연다.

```text
http://<HOST-LAN-IP>:3101
```

Web Mock은 자신이 열린 IP를 기준으로 Gateway 주소를 자동 구성한다.

```text
API:       http://<HOST-LAN-IP>:8101
WebSocket: ws://<HOST-LAN-IP>:8101/v1/events
```

정확한 현재 주소는 `tools/qemu/status.sh`의 `다른 컴퓨터 접속` 항목에서 확인한다. 원격 컴퓨터에서 `localhost`와 `127.0.0.1`은 이 Mac이 아니라 원격 컴퓨터 자신을 가리키므로 사용하지 않는다.

QEMU SSH `2222`는 계속 `127.0.0.1`에만 바인딩된다. 외부에는 Web Mock `3101`과 Gateway `8101`만 노출되며, 공유기 포트포워딩은 설정하지 않는다. 이 Gateway에는 아직 사용자 인증과 TLS가 없으므로 신뢰할 수 있는 회의용 사설망에서만 사용한다.

## 처음부터 구축하기

### 1. 필수 프로그램 확인

```bash
uname -m
brew --version
```

`uname -m` 결과가 `arm64`여야 한다. QEMU가 없으면 설치한다.

```bash
brew install qemu
qemu-system-aarch64 --version
```

### 2. 사용 포트 확인

```bash
lsof -nP -iTCP:2222 -sTCP:LISTEN
lsof -nP -iTCP:8101 -sTCP:LISTEN
lsof -nP -iTCP:3101 -sTCP:LISTEN
```

아무 출력도 없으면 비어 있는 포트다. `8101`과 `3101`은 기존 S.N.A.P 할당을 유지하고, `2222`는 QEMU SSH 전용으로 사용한다.

### 3. VM 생성

저장소 루트에서 실행한다.

```bash
cd /path/to/snap
tools/qemu/create.sh
```

이 명령은 다음 작업을 수행한다.

1. 공식 Debian ARM64 cloud 이미지와 SHA-512 목록을 받는다.
2. 이미지 무결성을 검증한다.
3. 최대 8GB의 copy-on-write qcow2 디스크를 만든다.
4. VM 전용 Ed25519 SSH 키를 저장소 밖에 만든다.
5. `snap` 사용자와 공개 키를 포함한 NoCloud seed ISO를 만든다.
6. VM별 UEFI 변수 파일을 준비한다.

qcow2는 sparse 디스크라 8GB를 즉시 점유하지 않는다. 사용한 데이터만큼 증가한다.

### 4. VM 시작

```bash
tools/qemu/start.sh
```

QEMU는 화면 없이 백그라운드로 실행되며, 기본적으로 SSH 준비를 최대 120초 기다린다. 첫 부팅은 cloud-init 때문에 이후 부팅보다 오래 걸릴 수 있다. 시작할 때 활성 사설 LAN IPv4를 자동 감지해 Gateway만 그 주소에 바인딩한다.

상태 확인:

```bash
tools/qemu/status.sh
```

`status.sh`는 사람이 상태를 읽는 명령이다. Gateway까지 성공·실패를 자동 판정할 때는 `verify.sh`를 사용한다.

직접 접속:

```bash
ssh \
  -i ~/VMs/snap-qemu/keys/id_ed25519 \
  -p 2222 \
  snap@127.0.0.1
```

### 5. Gateway 배포

```bash
tools/qemu/provision.sh
```

이 명령은 로컬 `pi-bridge/`만 패키징해 VM으로 복사하고, Python 가상환경과 `snap-gateway.service`를 만든다. 서비스는 VM 부팅 시 자동 시작하며 실패하면 재시작한다. 현재 LAN의 `http://<LAN-IP>:3101`을 CORS 허용 Origin에 함께 등록한다.

코드를 수정한 뒤에는 VM을 다시 만들지 않고 `provision.sh`만 재실행하면 된다.

각 배포는 VM의 `~/snap/releases/`에 새 릴리스로 남는다. 장기간 반복 배포할 때는 현재 `~/snap/current`가 가리키는 릴리스를 확인한 뒤 오래된 릴리스를 수동 정리한다.

Gateway 상태를 VM에서 확인하려면 다음을 사용한다.

```bash
ssh \
  -i ~/VMs/snap-qemu/keys/id_ed25519 \
  -p 2222 \
  snap@127.0.0.1 \
  'systemctl status snap-gateway.service --no-pager'
```

로그 확인:

```bash
ssh \
  -i ~/VMs/snap-qemu/keys/id_ed25519 \
  -p 2222 \
  snap@127.0.0.1 \
  'journalctl -u snap-gateway.service -n 100 --no-pager'
```

### 6. 통신 검증

안전한 읽기 전용 검증:

```bash
tools/qemu/verify.sh
```

가상 보드의 전체 주차·출차 상태 변경까지 검증:

```bash
tools/qemu/verify.sh --write-flow
```

`--write-flow`는 Gateway가 `pi-simulator` 계열 모드라고 응답할 때만 고객 차량 2대 등록, 1시간·4시간 이상 연속 입차, 첫 차량 독립 출차, 두 번째 차량 상태 유지, 정리 출차와 최종 `activeJob=null`을 실행한다.

개별 확인 주소:

```bash
SNAP_HOST_LAN_IP=192.168.0.50
curl "http://${SNAP_HOST_LAN_IP}:8101/health"
curl "http://${SNAP_HOST_LAN_IP}:8101/v1/parking-lots/demo-01/snapshot"
```

### 7. Web Mock 연결

Web Mock은 브라우저에서 열린 호스트의 `8101` 포트를 기본 Gateway로 사용한다. 따라서 `http://<HOST-LAN-IP>:3101`로 열면 API와 WebSocket도 같은 호스트의 `8101`을 사용하며 `.env.local`이 필요 없다.

이 Mac에서만 볼 때는 별도 터미널에서 실행한다.

```bash
cd /path/to/snap/web-mock
npm run dev
```

같은 네트워크의 다른 컴퓨터에서도 볼 때는 저장소 루트의 별도 터미널에서 다음 명령을 사용한다. Web Mock을 모든 인터페이스가 아닌 현재 사설 LAN IP 하나에만 바인딩한다.

```bash
tools/qemu/web-lan.sh
```

`npm run dev`로 로컬 전용 실행했다면 이 Mac에서 `http://localhost:3101`을 연다. `tools/qemu/web-lan.sh`로 실행했다면 이 Mac과 다른 컴퓨터 모두 `http://<LAN-IP>:3101`을 열고 `LIVE PI`를 선택한다.

```text
API: http://<LAN-IP>:8101
WebSocket: ws://<LAN-IP>:8101/v1/events
```

실제 Raspberry Pi처럼 Web Mock 호스트와 Gateway 호스트가 다를 때만 Git에 포함되지 않는 `web-mock/.env.local`로 주소를 덮어쓴다.

```dotenv
NEXT_PUBLIC_PI_API_BASE_URL=http://<PI-IP>:8101
NEXT_PUBLIC_PI_WS_URL=ws://<PI-IP>:8101/v1/events
```

`.env.local`을 변경한 뒤에는 Web Mock 개발 서버를 다시 시작한다.

확인 순서:

1. 연결 상태가 `LIVE PI`로 바뀌는지 확인한다.
2. 차량 ID와 선호 조건을 입력하고 주차를 요청한다.
3. 이벤트 스트림과 주차면 상태가 실시간으로 변하는지 확인한다.
4. 첫 차량이 `PARKED`인 동안 두 번째 차량 입차가 가능하고 두 슬롯이 각각 `OCCUPIED`가 되는지 확인한다.
5. 출차 요청 후 `IDLE`과 `AVAILABLE`로 돌아오는지 확인한다.

### 8. VM 종료

```bash
tools/qemu/stop.sh
```

기본 동작은 게스트에 정상 종료를 요청한다. 정상 종료가 되지 않는 것을 확인한 경우에만 다음 명령을 사용한다.

```bash
tools/qemu/stop.sh --force
```

## 평소 사용하는 명령

```bash
# 1. 가상 보드 시작
tools/qemu/start.sh

# 2. 현재 코드 배포
tools/qemu/provision.sh

# 3. 전체 통신 검증
tools/qemu/verify.sh --write-flow

# 4. Web Mock을 현재 사설 LAN IP에 실행
tools/qemu/web-lan.sh

# 5. 작업 종료 후 VM 중지
tools/qemu/stop.sh
```

이미 배포된 코드를 그대로 사용할 때는 `provision.sh`를 생략할 수 있다.

## 디렉터리 구조

```text
~/VMs/snap-qemu/
├── base/          # 공식 Debian 이미지와 체크섬
├── disk/          # copy-on-write VM 디스크
├── cloud-init/    # NoCloud seed와 사용한 공개 키 기록
├── keys/          # VM 전용 SSH 개인키·공개키·known_hosts
├── runtime/       # PID, monitor socket, serial log, UEFI vars
└── artifacts/     # 배포 중 사용하는 임시 패키지
```

`keys/`와 `disk/`는 GitHub, 메신저 또는 공동 드라이브에 올리지 않는다.

## 자원과 경로 변경

스크립트 실행 전에 환경 변수로 덮어쓸 수 있다.

```bash
export SNAP_QEMU_VM_DIR="$HOME/VMs/snap-qemu"
export SNAP_QEMU_CPUS=2
export SNAP_QEMU_MEMORY_MB=2048
export SNAP_QEMU_DISK_SIZE=8G
export SNAP_QEMU_SSH_PORT=2222
export SNAP_QEMU_GATEWAY_PORT=8101
export SNAP_QEMU_GATEWAY_FORWARD_HOST=auto
export SNAP_QEMU_WEB_PORT=3101
```

자동 감지가 올바른 인터페이스를 선택하지 못할 때만 시작 명령에 이 Mac의 사설 IP를 직접 지정한다.

```bash
SNAP_QEMU_GATEWAY_FORWARD_HOST=192.168.0.50 tools/qemu/start.sh
```

IP가 바뀌면 `tools/qemu/stop.sh` 후 `tools/qemu/start.sh`, `tools/qemu/provision.sh`를 다시 실행한다. QEMU가 실행 중인 동안에는 기존 바인딩 주소를 임의로 바꾸지 않는다.

VM을 만든 뒤 `SNAP_QEMU_VM_DIR`을 바꾸면 qcow2 backing image의 절대 경로가 달라질 수 있으므로 기존 VM 디렉터리를 임의로 이동하지 않는다.

## 문제 해결

### `port is already in use`

```bash
lsof -nP -iTCP:2222 -sTCP:LISTEN
lsof -nP -iTCP:8101 -sTCP:LISTEN
```

기존 QEMU가 실행 중이면 `tools/qemu/status.sh`와 `tools/qemu/stop.sh`를 사용한다. 다른 프로젝트가 포트를 사용 중이면 임의로 종료하지 말고 팀의 비공개 포트 레지스트리에서 새 포트를 배정한다.

### SSH가 준비되지 않음

```bash
tail -n 100 "$HOME/VMs/snap-qemu/runtime/serial.log"
tools/qemu/status.sh
```

첫 부팅에서 cloud-init이 진행 중이면 잠시 후 다시 확인한다.

### Gateway가 `NOT READY`

```bash
tools/qemu/provision.sh
```

배포 후에도 실패하면 VM의 systemd 로그를 확인한다.

### Web Mock이 `DISCONNECTED`

다음 순서로 확인한다.

1. `tools/qemu/status.sh`
2. `curl http://127.0.0.1:8101/health`
3. Web Mock의 API와 WebSocket 주소
4. `tools/qemu/verify.sh`

### 다른 컴퓨터에서 페이지가 열리지 않음

1. 두 컴퓨터가 같은 Wi-Fi 또는 유선 LAN인지 확인한다.
2. `tools/qemu/status.sh`가 표시하는 IP로 다시 접속한다.
3. Web Mock 터미널에 `Network` 주소가 표시되는지 확인한다.
4. macOS 방화벽 안내가 나타나면 Node와 QEMU의 수신 연결을 사설망에서 허용한다.
5. 게스트 Wi-Fi의 기기 간 통신 차단 기능이 켜져 있으면 일반 사설망으로 바꾼다.

방화벽 전체 비활성화, QEMU SSH `2222` 공개, 공유기 포트포워딩은 필요하지 않다.

## 초기화와 백업

자동화 스크립트는 기존 VM 디스크와 SSH 키를 덮어쓰지 않는다. 새로 만들기 전에는 QEMU를 정상 종료하고 `~/VMs/snap-qemu`를 별도 이름으로 이동해 백업한다.

공식 base 이미지 하나로 여러 copy-on-write VM을 만들 수 있지만, 현재 스크립트는 회의 시연의 단순성을 위해 `snap-qemu-pi` 한 대만 관리한다.

## 관련 문서

- [Raspberry Pi Gateway](../pi-bridge/README.md)
- [클라이언트–Gateway 검증](09-client-gateway-verification.md)
- [프로젝트 구성](../README.md#구성)
- [Web Mock](../web-mock/README.md)
