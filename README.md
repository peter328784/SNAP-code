# S.N.A.P Raspberry Pi Gateway

이 저장소의 Arduino 펌웨어는 그대로 유지하면서, Raspberry Pi에 REST API와 WebSocket, 두 Arduino의 Serial 통신을 연결하는 `pi-bridge`를 추가했다.

```text
고객 앱 / Web Mock
        │ HTTP + WebSocket (TCP 8101, Wi-Fi/LAN)
        ▼
Raspberry Pi : pi-bridge
        ├── Arduino Mega 센서  (/dev/ttyACM0, 115200 baud)
        └── 운반 로봇 Arduino (/dev/serial0, 9600 baud)
```

## 변경한 이유

기존 `라즈베리파이 경로 계산 코드`와 README의 `parking_send.py`는 터미널에서 Serial을 직접 시험하는 단독 프로그램이다. HTTP/WebSocket 서버가 아니므로 TCP `8101`을 `LISTEN`하지 않고 Web Mock과의 지속 연결인 `ESTAB`도 만들 수 없다.

기존 경로 계산 코드는 현재 저장소의 Arduino 펌웨어와도 다음 계약이 달랐다.

- Mega를 `9600 baud`로 열고 여섯 개 CSV 값을 기대하지만, `ADV_6_CODE0629.ino`는 `115200 baud`에서 ASCII 10진 비트마스크 `0..63`을 보낸다.
- 로봇에 `TARGET:n`을 보내지만, `sketch_aug24a.ino`는 `L/W/C/P/S/B/H`로 이루어진 경로 문자열을 받는다.

`pi-bridge`는 TCP `8101` 서버를 열고 현재 펌웨어의 baud rate와 프레임 형식을 사용한다. 기존 Arduino `.ino` 두 파일과 기존 Raspberry Pi 진단 코드는 수정하지 않았다.

## 변경 범위

| 경로 | 역할 | 이번 변경 |
|---|---|---|
| `ADV_6_CODE0629.ino` | 6개 주차면 센서 Mega 펌웨어 | 변경 없음 |
| `sketch_aug24a.ino` | 운반 로봇 펌웨어 | 변경 없음 |
| `라즈베리파이 경로 계산 코드` | 과거 Serial CLI/진단 코드 | 변경 없음, Gateway와 동시 실행 금지 |
| `pi-bridge/app/` | REST·WebSocket·제어기·Serial adapter | 추가 |
| `pi-bridge/requirements.txt` | Python 실행 의존성 | 추가 |
| `README.md` | 설치, 원리, API, 장애 확인 문서 | 갱신 |

## 동작 원리

1. Gateway가 시작된다.
   - 기본 `simulator` 모드는 Arduino 없이 API 흐름을 시험한다.
   - `serial` 모드는 Mega와 로봇 포트를 연다. 로봇에 모터를 움직이지 않는 `PING`, `STATUS`를 보내 `PONG`, `STATUS:IDLE`까지 확인해야 서버 시작이 완료된다.
2. 앱이 차량을 등록하고 주차를 요청한다.
3. Gateway가 센서 상태와 예상 주차시간에 따라 빈 주차면 하나를 예약한다.
4. 주차면에 맞는 경로 문자열을 로봇 Arduino에 전송한다.
5. 로봇의 `ROUTE_ACCEPTED`, `ACTION_START`, `ACTION_DONE`, `ROUTE_DONE` 순서를 검증한다.
6. 상태 변화마다 메모리 Snapshot을 갱신하고 `/v1/events` 구독자에게 WebSocket 이벤트를 보낸다.
7. Mega가 보낸 점유 비트마스크를 주차면 상태에 반영한다.

한 번에 로봇 작업 하나만 실행한다. 차량·주차 세션·작업 정보는 현재 메모리에만 저장되므로 Gateway를 재시작하면 사라진다.

### 주차면 배정

| `expectedMinutes` | 정책 | 확인 순서 |
|---:|---|---|
| `60`, `120` | `NEAR_FIRST` | 1 → 2 → 3 → 4 → 5 → 6 |
| `180` | `FAR_GROUP_FIRST` | 4 → 5 → 6 → 3 → 2 → 1 |
| `240` | `FARTHEST_FIRST` | 6 → 5 → 4 → 3 → 2 → 1 |

## Raspberry Pi 준비

Python 3.11 이상을 권장하며 최소 Python 3.10이 필요하다.

### SSH와 UART

Raspberry Pi Imager에서 hostname, 사용자, 비밀번호, Wi-Fi, SSH를 설정한 뒤 부팅한다. 아래 사용자와 주소는 예시다.

```bash
ssh pi@raspberrypi.local
ssh pi@192.168.0.50
```

GPIO UART를 사용하려면 `sudo raspi-config`의 `Interface Options > Serial Port`에서 login shell은 비활성화하고 serial hardware는 활성화한 뒤 재부팅한다.

```bash
sudo raspi-config
sudo reboot
```

Raspberry Pi GPIO UART는 **3.3V 전용**이다. 5V 신호를 직접 연결하면 Pi가 손상될 수 있으므로, 특히 5V Arduino의 TX와 Pi RX 사이에는 5V→3.3V level shifter 또는 적절한 분압 회로를 사용한다. 전원을 끈 상태에서 TX↔RX를 교차하고 GND를 공통으로 연결한다. 배선 전에는 [Raspberry Pi 공식 UART 경고](https://www.raspberrypi.com/documentation/computers/configuration.html#configure-uarts)를 확인한다.

두 Arduino를 연결한 뒤 포트와 권한을 확인한다.

```bash
ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
ls -l /dev/serial/by-id/ 2>/dev/null
groups
```

현재 사용자가 `dialout` 그룹에 없다면 한 번 추가하고 로그아웃한 뒤 다시 로그인한다.

```bash
sudo usermod -aG dialout "$USER"
```

`/dev/ttyACM0`은 USB 연결 순서에 따라 바뀔 수 있다. `/dev/serial/by-id/...`가 있다면 고정 경로를 `SNAP_MEGA_PORT`에 사용하는 편이 안전하다. Mega와 로봇은 서로 다른 장치여야 한다.

### Python 환경

```bash
sudo apt update
sudo apt install -y python3-venv

cd ~/SNAP-code/pi-bridge
python3 --version
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## 실행

### Simulator

환경변수를 지정하지 않으면 Arduino 없이 실행되는 Simulator다.

```bash
cd ~/SNAP-code/pi-bridge
source .venv/bin/activate
python -m app
```

기본 주소는 `http://127.0.0.1:8101`이다.

```bash
curl --fail --silent --show-error http://127.0.0.1:8101/health
```

```json
{"status":"ok","mode":"pi-simulator-multi-vehicle"}
```

### 실제 Arduino Serial 모드

아래 `192.168.0.20:3101`은 Web Mock이 열린 브라우저의 실제 Origin 예시다. 브라우저 주소창에 표시되는 scheme, host, port와 정확히 같아야 한다.

```bash
cd ~/SNAP-code/pi-bridge
source .venv/bin/activate

SNAP_HARDWARE_MODE=serial \
SNAP_MEGA_PORT=/dev/ttyACM0 \
SNAP_MEGA_BAUD=115200 \
SNAP_MEGA_READ_TIMEOUT_SECONDS=2 \
SNAP_MEGA_INITIAL_MASK='' \
SNAP_ROBOT_PORT=/dev/serial0 \
SNAP_ROBOT_BAUD=9600 \
SNAP_ROBOT_READ_TIMEOUT_SECONDS=30 \
SNAP_ROBOT_STARTUP_TIMEOUT_SECONDS=5 \
SNAP_SERIAL_RECONNECT_DELAY_SECONDS=1 \
SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_GATEWAY_PORT=8101 \
SNAP_CORS_ORIGINS=http://192.168.0.20:3101 \
python -m app
```

브라우저가 `http://localhost:3101`에서 열렸다면 Pi IP가 아니라 그 값을 `SNAP_CORS_ORIGINS`에 넣는다. 여러 Origin은 쉼표로 구분한다.

Gateway 실행 중에는 아래 프로그램을 동시에 실행하지 않는다.

- `라즈베리파이 경로 계산 코드`
- README에 있던 `parking_send.py`
- Arduino IDE Serial Monitor
- `minicom`, `picocom` 또는 다른 pyserial 스크립트

Serial 포트 하나를 여러 프로세스가 읽으면 포트 열기에 실패하거나 응답 프레임이 서로 나뉜다. Gateway를 두 Arduino Serial 포트의 유일한 소유자로 둔다.

### Hardware Health

```bash
curl --fail --silent --show-error http://127.0.0.1:8101/health
```

`curl` 성공은 HTTP 응답을 받았다는 뜻일 뿐이다. JSON의 다음 항목을 함께 확인한다.

- `status: "ok"`
- `mode: "pi-hardware-snap-code"`
- `hardware.mega.connected: true`
- `hardware.mega.verified: true`
- `hardware.robot.connected: true`
- `hardware.robot.ready: true`
- `hardware.robot.interlocked: false`

Mega는 상태가 변할 때만 프레임을 보낸다. 첫 정상 프레임 전에는 슬롯을 `UNKNOWN`으로 두고 Health는 `degraded`다. 센서 앞 물체를 한 번 넣었다 빼서 상태 변화 프레임을 발생시킨다.

`SNAP_MEGA_INITIAL_MASK=0`은 여섯 면이 실제로 모두 비어 있음을 확인한 테스트 현장에서만 사용한다. 초기 슬롯 상태만 지정하며 실제 Mega 통신 검증인 `verified:true`를 대신하지 않는다.

## API 공통 규칙

- Base URL: `http://<PI_IP>:8101`
- JSON 요청은 `Content-Type: application/json`을 사용한다.
- 공개 API 버전은 `v1`이고 주차장 ID는 `demo-01` 하나다.
- 요청의 `vehicleId`와 `vehicleNumber`는 둘 중 정확히 하나만 보낸다.
- `customerId`를 생략하면 하위 호환용 `legacy` 고객으로 처리한다.
- 날짜와 시간은 UTC ISO 8601 문자열이다.
- 추가 요청 필드는 `422`다. 과거 Web 호환을 위해 주차 요청의 `preference`만 받아서 무시한다.
- 실행 중 자동 문서는 `/docs`, `/redoc`, OpenAPI JSON은 `/openapi.json`에서 볼 수 있다.

### 오류

| HTTP | 의미 |
|---:|---|
| `404` | 차량, 요청, 작업, 주차장을 찾지 못함 |
| `409` | 작업 진행 중, 만차, 잘못된 차량 상태, 로봇 interlock, 실제 출차 미지원 |
| `422` | JSON 구조, 필드 길이, 차량 식별자 조합, 주차시간 검증 실패 |

제어기 오류는 `{"detail":"오류 설명"}` 형식이다. 요청 schema 검증에서 발생한 `422`는 잘못된 필드 위치와 원인을 담은 `detail` 배열을 반환한다.

## REST API

### 1. `GET /health`

Gateway 프로세스와 Hardware 준비 상태를 조회한다. Body는 없다.

Simulator 응답:

```json
{
  "status": "ok",
  "mode": "pi-simulator-multi-vehicle"
}
```

Serial 모드에서는 `hardware.mega`와 `hardware.robot` 아래에 장치, baud rate, 연결, 실제 프레임 검증, 마지막 송수신 시각, 오류, interlock이 포함된다. Health가 `degraded`여도 HTTP 상태는 `200`이므로 JSON 내용을 확인한다.

### 2. `GET /v1/customers/{customer_id}/vehicles`

고객에게 등록된 차량과 각 차량의 현재 주차 세션을 조회한다.

```bash
curl http://127.0.0.1:8101/v1/customers/customer-1/vehicles
```

```json
{
  "customerId": "customer-1",
  "vehicles": []
}
```

차량 항목에는 `vehicleId`, `customerId`, `vehicleNumber`, `state`, `updatedAt`이 있고 상태에 따라 `slotId`, `expectedMinutes`, `sessionId`, `currentSession`이 추가된다.

### 3. `POST /v1/customers/{customer_id}/vehicles`

차량번호를 등록하고 내부 `vehicleId`를 발급한다. 동일 고객과 정규화된 동일 차량번호를 다시 보내면 기존 차량을 반환한다.

```bash
curl -X POST http://127.0.0.1:8101/v1/customers/customer-1/vehicles \
  -H 'content-type: application/json' \
  -d '{"vehicleNumber":"12가3456"}'
```

요청:

```json
{"vehicleNumber":"12가3456"}
```

성공 `201 Created`:

```json
{
  "vehicle": {
    "vehicleId": "VEH-...",
    "customerId": "customer-1",
    "vehicleNumber": "12가3456",
    "state": "READY_TO_PARK",
    "updatedAt": "..."
  }
}
```

`vehicleNumber`는 공백 제거 후 대문자로 정규화되며 1~32자다.

### 4. `GET /v1/parking-lots/{lot_id}/snapshot`

주차장, 여섯 슬롯, 로봇, 현재 작업의 공개 Snapshot을 조회한다.

```bash
curl http://127.0.0.1:8101/v1/parking-lots/demo-01/snapshot
```

| 필드 | 의미 |
|---|---|
| `lotId`, `updatedAt` | 주차장 ID와 마지막 갱신 시각 |
| `status`, `isBusy` | `IDLE/BUSY`와 활성 작업 여부 |
| `availableCount` | `AVAILABLE` 슬롯 수 |
| `slots[]` | 슬롯 `id`, `sensorState`, `reservationState`, 최종 `state` |
| `robot` | 동작 상태, 메시지, 논리 위치, 진행률, 배터리 |
| `activeJob` | 현재 작업 또는 `null` |
| `job` | 현재 작업, 없으면 `IDLE` 표시용 객체 |

다른 `lot_id`는 `404`다. 공개 Snapshot에는 고객 ID와 차량번호를 노출하지 않는다.

### 5. `POST /v1/parking-requests`

빈 슬롯을 예약하고 주차 작업을 즉시 비동기로 시작한다.

```bash
curl -X POST http://127.0.0.1:8101/v1/parking-requests \
  -H 'content-type: application/json' \
  -d '{"customerId":"customer-1","vehicleId":"VEH-...","expectedMinutes":60}'
```

차량번호로 바로 요청하면 없는 차량은 해당 고객에게 자동 등록된다.

```json
{
  "customerId": "customer-1",
  "vehicleNumber": "12가3456",
  "expectedMinutes": 120
}
```

| 필드 | 필수 | 규칙 |
|---|---|---|
| `customerId` | 아니요 | 1~64자, 기본 `legacy` |
| `vehicleId` | 조건부 | `vehicleNumber`와 둘 중 하나만 |
| `vehicleNumber` | 조건부 | `vehicleId`와 둘 중 하나만 |
| `expectedMinutes` | 아니요 | `60/120/180/240`, 기본 `120` |
| `preference` | 아니요 | 과거 호환용, 배정에는 사용하지 않음 |

응답은 `{"requestId":"REQ-...","snapshot":{...}}`다. Snapshot에는 이미 예약된 슬롯과 시작된 작업이 반영된다. 이 API가 작업을 시작시키므로 별도 confirm을 기다리지 않는다.

### 6. `POST /v1/parking-requests/{request_id}/confirm`

이전 Web 클라이언트와의 호환을 위한 확인 API다. 존재하는 작업에 `confirmed:true`를 반환할 뿐 새 동작을 시작하거나 명령을 중복 전송하지 않는다. Body는 없다.

```bash
curl -X POST http://127.0.0.1:8101/v1/parking-requests/REQ-.../confirm
```

응답은 `{"requestId":"REQ-...","confirmed":true,"snapshot":{...}}`다. 없는 ID는 `404`다.

### 7. `GET /v1/jobs/{job_id}`

주차 또는 출차 작업 하나의 현재·최종 상태를 조회한다.

```bash
curl http://127.0.0.1:8101/v1/jobs/REQ-...
```

응답에는 `id`, `kind`, `state`, `vehicleId`, `sessionId`, `targetSlot`, `message`, `startedAt`, `updatedAt`이 있다. 주차 작업에는 `expectedMinutes`, `allocationPolicy`가 추가되고 완료되면 `completedAt`이 추가된다. 알 수 없는 ID는 `404`다.

### 8. `POST /v1/retrieval-requests`

주차 완료 차량의 출차 작업을 요청한다.

```bash
curl -X POST http://127.0.0.1:8101/v1/retrieval-requests \
  -H 'content-type: application/json' \
  -d '{"customerId":"customer-1","vehicleId":"VEH-..."}'
```

`customerId`와 `vehicleId` 또는 `vehicleNumber` 하나를 사용한다. 성공 응답은 `{"requestId":"RET-...","snapshot":{...}}`다.

Simulator는 주차와 출차를 모두 지원한다. 현재 `sketch_aug24a.ino`에는 검증된 출차 경로가 없으므로 Serial 모드에서는 모터에 임의 명령을 보내지 않고 `409 Conflict`로 거절한다.

## WebSocket API

### 9. `WS /v1/events`

주차장과 로봇 상태 변화를 구독한다.

```text
ws://<PI_IP>:8101/v1/events
```

연결 직후:

아래 예시는 envelope만 보여 주기 위해 `snapshot` 내용을 `{}`로 축약했다. 실제 메시지에는 Snapshot 조회 API와 같은 전체 객체가 들어온다.

```json
{
  "type": "SNAPSHOT",
  "message": "Pi 이벤트 채널이 연결됐습니다.",
  "snapshot": {}
}
```

그 뒤에도 `{"type":"PARKED","message":"...","snapshot":{...}}`와 같은 envelope를 사용한다.

- 요청: `JOB_REQUESTED`, `RETRIEVAL_REQUESTED`
- 센서: `OCCUPANCY_UPDATED`, `OCCUPANCY_STALE`
- 로봇 단계: `READY`, `TRACING`, `APPROACHING`, `GRIPPING`, `REVERSING`
- 완료: `PARKED`, `RETRIEVED`, `ROBOT_IDLE`
- 실패: `JOB_FAILED`

클라이언트가 WebSocket으로 보낼 명령은 없다. 느린 구독자의 큐가 가득 차면 가장 오래된 이벤트부터 제거해 최신 Snapshot을 우선한다. 허용되지 않은 브라우저 Origin은 close code `1008`로 종료한다. Origin 헤더가 없는 CLI 클라이언트는 허용된다.

## Arduino Serial 계약

### Mega 센서 → Pi

- 장치: `/dev/ttyACM0`
- 속도: `115200 baud`
- 프레임: ASCII 10진수 `0`~`63`과 줄바꿈
- bit 0은 슬롯 1, bit 5는 슬롯 6
- bit `1`은 `OCCUPIED`, `0`은 `EMPTY`

슬롯 1과 3이 점유되면 `1 + 4 = 5`이므로 다음 프레임이 온다.

```text
5\r\n
```

실제 Serial 경로는 비트마스크 형식을 엄격하게 사용한다. 정상적인 읽기 timeout은 상태 변화가 없다는 뜻일 수 있다. 잘못된 프레임이나 Serial 오류가 발생하면 모든 센서 상태를 `UNKNOWN`으로 바꾸고 Health를 `degraded`로 표시한다.

### Pi → 운반 로봇 Arduino

- 장치: `/dev/serial0`
- 속도: `9600 baud`
- 프레임: 경로 문자열과 줄바꿈

| 슬롯 | 전송 프레임 |
|---:|---|
| 1 | `LCPSBWB\n` |
| 2 | `LWPSBCB\n` |
| 3 | `LLCPSBWB\n` |
| 4 | `LLWPSBCB\n` |
| 5 | `LLLCPSBWB\n` |
| 6 | `LLLWPSBCB\n` |

Gateway는 `ROUTE_ACCEPTED:n`의 길이, 각 `ACTION_START:x`와 `ACTION_DONE:x`의 문자와 순서, 마지막 `ROUTE_DONE`을 검증한다. `ERR:*`, `STOPPED`, timeout, 길이·순서 불일치는 성공으로 처리하지 않는다.

통신 오류가 생기면 가능한 경우 `STOP`을 보내고 작업을 `FAILED`로 만든 뒤 interlock을 건다. 이후 실물 작업은 차단된다. 모터 전원을 안전하게 차단하고 로봇을 실제 대기 위치로 복구한 뒤 Gateway를 재시작한다. `STATUS:IDLE`은 논리 상태이므로 실제 위치도 눈으로 확인한다.

## 환경 변수

| 환경 변수 | 기본값 | 설명 |
|---|---|---|
| `SNAP_HARDWARE_MODE` | `simulator` | `simulator` 또는 `serial` |
| `SNAP_MEGA_PORT` | `/dev/ttyACM0` | Mega Serial 장치 |
| `SNAP_MEGA_BAUD` | `115200` | Mega baud rate |
| `SNAP_MEGA_READ_TIMEOUT_SECONDS` | `2` | Mega 한 줄 읽기 제한 |
| `SNAP_MEGA_INITIAL_MASK` | 미설정 | 확실할 때만 사용할 초기 `0..63` |
| `SNAP_ROBOT_PORT` | `/dev/serial0` | 로봇 Serial 장치 |
| `SNAP_ROBOT_BAUD` | `9600` | 로봇 baud rate |
| `SNAP_ROBOT_READ_TIMEOUT_SECONDS` | `30` | 로봇 한 줄 응답 제한 |
| `SNAP_ROBOT_STARTUP_TIMEOUT_SECONDS` | `5` | 시작 probe 전체 제한 |
| `SNAP_SERIAL_RECONNECT_DELAY_SECONDS` | `1` | Mega 오류 뒤 재시도 간격 |
| `SNAP_GATEWAY_HOST` | `127.0.0.1` | LAN 접속은 `0.0.0.0` |
| `SNAP_GATEWAY_PORT` | `8101` | HTTP·WebSocket 포트 |
| `SNAP_STEP_DELAY_SECONDS` | `1.05` | Simulator 단계와 완료 후 상태 전환 대기 |
| `SNAP_CORS_ORIGINS` | `http://localhost:3101,http://127.0.0.1:3101` | 허용 브라우저 Origin 목록 |

설정값이 잘못되었거나 Serial 모드에서 두 장치 경로가 같으면 시작을 거부한다.

## ESTAB 연결 확인

### 1. Pi의 LISTEN

Pi에서 실행한다.

```bash
ss -ltnp | grep ':8101'
```

LAN 연결이라면 `0.0.0.0:8101` 또는 Pi의 LAN 주소가 `LISTEN`이어야 한다. `127.0.0.1:8101`만 보이면 `SNAP_GATEWAY_HOST=0.0.0.0`으로 다시 실행한다. 아무것도 보이지 않으면 Gateway 시작 오류를 확인한다.

### 2. Pi IP와 로컬 Health

```bash
hostname -I
curl -v http://127.0.0.1:8101/health
```

로컬 curl도 실패하면 Wi-Fi보다 먼저 Gateway 실행 또는 Serial 시작 검증 실패를 확인한다.

### 3. Web PC의 TCP와 HTTP

Windows PowerShell:

```powershell
Test-NetConnection 192.168.0.50 -Port 8101
curl.exe http://192.168.0.50:8101/health
```

macOS/Linux:

```bash
curl -v http://192.168.0.50:8101/health
```

실패하면 같은 네트워크인지, guest Wi-Fi/AP isolation인지, Pi 방화벽이 켜졌는지 확인한다.

```bash
sudo ufw status
```

### 4. Origin과 WebSocket

TCP·curl은 성공하지만 브라우저만 실패하면 브라우저 개발자 도구의 Origin과 `SNAP_CORS_ORIGINS`가 같은지 확인한다. WebSocket이 `1008`로 닫히면 Origin이 허용 목록에 없는 것이다.

`ESTAB`는 연결이 유지되는 동안만 보인다. 단발 REST/curl 뒤 `ESTAB`가 사라지는 것은 정상이다. `/v1/events` WebSocket을 열어 둔 상태에서 확인해야 지속 연결이 보인다.

```bash
ss -tnp | grep ':8101'
```

### 5. Serial 시작

정상 초기 로그 예시:

```text
UART TX robot device=/dev/serial0 baud=9600 frame='PING'
UART RX robot device=/dev/serial0 baud=9600 frame='PONG'
UART TX robot device=/dev/serial0 baud=9600 frame='STATUS'
UART RX robot device=/dev/serial0 baud=9600 frame='STATUS:IDLE'
UART RX mega device=/dev/ttyACM0 baud=115200 frame='5'
```

`connected:true`는 포트 handle을 열었다는 뜻이고 `robot.ready:true`가 시작 probe까지 성공했다는 뜻이다. `tcpdump`는 TCP 패킷만 보며 `/dev/ttyACM0` 또는 `/dev/serial0`의 UART 프레임은 볼 수 없다.

## 안전과 현재 제한

- 실제 모터 시험은 바퀴가 바닥에 닿지 않고 즉시 전원을 끌 수 있는 상태에서 시작한다.
- 인증과 TLS가 없는 개발용 Gateway다. 신뢰하는 사설망에서만 사용하고 인터넷에 포트포워딩하지 않는다.
- 실제 Serial 모드는 현재 `PARKING`만 지원한다. `RETRIEVAL`은 `409`다.
- 상태는 메모리 전용이라 재시작 후 차량·세션·작업이 복원되지 않는다.
- Mega는 상태 변화 때만 프레임을 보내므로 마지막 프레임 이후 펌웨어 정지를 heartbeat로 구별할 수 없다.
- Simulator와 API 검증은 실제 배선, 전원, 센서 거리, 모터 방향, 물리 비상 정지를 대신하지 않는다.
