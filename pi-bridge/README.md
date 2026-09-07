# S.N.A.P Raspberry Pi Gateway

Raspberry Pi에서 실행하는 REST·WebSocket Gateway다. Flutter 고객 앱과 Web Mock은 Wi-Fi로 이 Gateway에 연결하고, Gateway가 두 Arduino와 Serial로 통신한다.

```text
고객 앱 / Web Mock
        │ HTTP·WebSocket (:8101, Wi-Fi)
        ▼
Raspberry Pi Gateway
        ├── Arduino Mega 센서  (/dev/ttyACM0, 115200 baud)
        └── 운반 로봇 Arduino (/dev/serial0, 9600 baud)
```

실행 모드는 두 가지다.

- 기본 `simulator`: Arduino 없이 REST·WebSocket과 여러 차량 흐름을 개발한다.
- `serial`: 팀의 [SNAP-code 펌웨어](https://github.com/peter328784/SNAP-code/tree/24a742729e0ed398adf553622dc8e02d361dadbd)를 올린 실제 Mega와 로봇 Arduino를 사용한다.

실제 장비용 Serial 통합은 소프트웨어에 구현돼 있지만, 각 팀의 배선·전원·포트 이름까지 물리 보드에서 검증했다는 뜻은 아니다. 처음 구동할 때는 바퀴가 바닥에 닿지 않는 안전한 상태에서 시험한다.

## 설치

Python 3.11 이상을 권장한다. `requirements.txt`에는 실제 UART 통신에 필요한 `pyserial`도 포함돼 있다.

```bash
cd ~/snap/pi-bridge
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## Simulator 실행

환경변수를 지정하지 않으면 Simulator가 실행된다.

```bash
python -m app
```

같은 Wi-Fi의 Web PC에서 연결하려면 Pi가 모든 네트워크 인터페이스에서 요청을 받게 하고, 실제 Web Origin을 허용한다. 아래 주소는 예시이며 `192.168.0.20`을 Web PC의 실제 IP로 바꾼다.

```bash
SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_GATEWAY_PORT=8101 \
SNAP_CORS_ORIGINS=http://192.168.0.20:3101 \
python -m app
```

## 실제 Arduino Serial 모드 실행

### 1. 포트와 권한 확인

두 Arduino를 연결한 Pi에서 실행한다.

```bash
ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
ls -l /dev/serial/by-id/ 2>/dev/null
groups
```

Pi 사용자가 `dialout` 그룹에 없다면 한 번만 추가한 뒤 로그아웃하고 다시 로그인한다.

```bash
sudo usermod -aG dialout "$USER"
```

`/dev/ttyACM0`은 재연결 순서에 따라 바뀔 수 있다. `/dev/serial/by-id/...`가 보이면 그 고정 경로를 `SNAP_MEGA_PORT`에 사용하는 편이 안전하다. `/dev/serial0`은 Pi UART 설정과 배선이 올바른지 별도로 확인한다.

### 2. Gateway 실행

아래 주소는 예시다. `192.168.0.20`을 Web Mock을 실행하는 Windows/macOS/Linux PC의 실제 IP로 바꾼다.

```bash
cd ~/snap/pi-bridge
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

Gateway는 시작할 때 두 포트를 연 다음 모터를 움직이지 않는 `PING`과 `STATUS`를 로봇에 보내 `PONG`, `STATUS:IDLE`을 확인한다. 포트를 열지 못하거나 제한 시간 안에 두 응답이 없으면 명확한 오류와 함께 종료한다. 로봇이 이미 경로를 실행 중이어도 시작을 거부한다. 포트 경로, Arduino 연결, 펌웨어, `dialout` 권한을 해결한 뒤 다시 실행한다. 실행 중에는 다음 프로그램을 동시에 열지 않는다.

- SNAP-code 저장소의 별도 Raspberry Pi 콘솔 브리지
- Arduino IDE Serial Monitor
- `minicom`, `picocom`, 다른 pyserial 스크립트

한 Serial 포트를 여러 프로세스가 읽으면 프레임이 분산되거나 포트 열기가 실패한다. UART 확인은 Gateway를 유일한 Serial 소유자로 둔 상태에서 Gateway 로그와 `/health`를 사용한다.

### 3. Health 확인

Pi의 두 번째 터미널에서 확인한다.

```bash
curl --fail --silent --show-error http://127.0.0.1:8101/health
```

Hardware mode에서는 `mode`가 `pi-hardware-snap-code`, `robot.ready`가 `true`여야 한다. 첫 실제 Mega 프레임 전에는 안전을 위해 `status`가 `degraded`이고, `mega.verified:true`가 된 뒤 `ok`가 된다. `SNAP_MEGA_INITIAL_MASK`는 슬롯 사용만 초기화할 뿐 통신 검증을 대신하지 않는다. 기본 Simulator라면 `mode`는 `pi-simulator-multi-vehicle`이다. `connected:true`는 운영체제에서 Serial 핸들을 열었다는 뜻이고, `robot.ready:true`는 시작 시 `PING`/`PONG`과 `STATUS:IDLE`까지 확인했다는 뜻이다.

실제 프레임은 Gateway 실행 터미널의 다음 INFO 로그로 확인한다.

```text
UART TX robot device=/dev/serial0 baud=9600 frame='PING'
UART RX robot device=/dev/serial0 baud=9600 frame='PONG'
UART TX robot device=/dev/serial0 baud=9600 frame='STATUS'
UART RX robot device=/dev/serial0 baud=9600 frame='STATUS:IDLE'
UART RX mega device=/dev/ttyACM0 baud=115200 frame='5'
UART TX robot device=/dev/serial0 baud=9600 frame='LCPSBWB'
UART RX robot device=/dev/serial0 baud=9600 frame='ROUTE_ACCEPTED:7'
```

`tcpdump`는 Wi-Fi/Ethernet의 TCP `8101`을 확인하는 도구이며 이 UART 로그를 대신하지 않는다.

## 실제 펌웨어 통신 계약

### Mega 센서 → Pi

- 기본 장치: `/dev/ttyACM0`
- 속도: `115200 baud`
- 형식: 상태가 바뀔 때 출력되는 ASCII 10진수 `0`~`63`과 줄바꿈
- 비트: bit 0은 슬롯 1, bit 5는 슬롯 6, `1`은 `OCCUPIED`

예를 들어 슬롯 1과 3이 점유되면 Mega는 원시 1바이트가 아니라 다음 ASCII 프레임을 보낸다.

```text
5\r\n
```

Mega 펌웨어는 상태 변경 시에만 전송한다. 부팅 시 여섯 면이 모두 비어 있으면 첫 프레임이 오지 않을 수 있으므로 Gateway는 첫 정상 프레임 전까지 점유 상태를 `UNKNOWN`으로 둔다. 기본 실행 명령의 빈 `SNAP_MEGA_INITIAL_MASK=''`를 그대로 둔다. 모든 면이 실제로 비어 있음을 눈으로 확인한 테스트 현장에서만 그 값을 다음처럼 `0`으로 바꿀 수 있다.

```bash
SNAP_MEGA_INITIAL_MASK=0
```

점유 차량이 있는데 `0`을 사용하면 잘못된 주차면을 배정할 수 있으므로 추측해서 설정하지 않는다. 가장 안전한 확인 방법은 센서 앞 물체를 한 번 넣었다 빼서 Mega 상태 변경 프레임을 발생시키는 것이다.

### Pi → 운반 로봇 Arduino

- 기본 장치: `/dev/serial0`
- 속도: `9600 baud`
- 형식: 슬롯별 `L/W/C/P/S/B/H` 경로 문자열과 `\n`

| 슬롯 | 전송 경로 |
|---:|---|
| 1 | `LCPSBWB\n` |
| 2 | `LWPSBCB\n` |
| 3 | `LLCPSBWB\n` |
| 4 | `LLWPSBCB\n` |
| 5 | `LLLCPSBWB\n` |
| 6 | `LLLWPSBCB\n` |

로봇은 `READY`, `ROUTE_ACCEPTED:n`, `ACTION_START:...`, `ACTION_DONE:...`, 마지막 `ROUTE_DONE`을 줄 단위로 응답한다. Gateway는 수락된 길이가 전송 경로와 같은지, 모든 action이 경로 순서대로 시작·종료됐는지 확인한 뒤에만 완료 처리한다. `ERR:*`, `STOPPED`, 순서가 어긋난 프레임은 성공으로 처리하지 않는다.

현재 팀 로봇 펌웨어에는 **주차 경로만** 정의돼 있다. 따라서 Hardware mode의 출차 요청은 임의 경로로 모터를 움직이지 않고 HTTP `409 Conflict`로 거절한다. 출차를 사용하려면 팀이 안전하게 검증한 출차 경로와 펌웨어 명령 계약을 먼저 추가해야 한다. Simulator에서는 주차와 출차를 모두 시험할 수 있다.

## 고객·차량 API

차량을 먼저 등록한 뒤 반환된 내부 `vehicleId`로 주차를 요청한다. 실제 차량번호는 고객별 차량 API에만 포함되며 공개 주차장 Snapshot에는 노출되지 않는다.

```bash
curl -X POST http://localhost:8101/v1/customers/customer-1/vehicles \
  -H 'content-type: application/json' \
  -d '{"vehicleNumber":"12가3456"}'

curl http://localhost:8101/v1/customers/customer-1/vehicles

curl -X POST http://localhost:8101/v1/parking-requests \
  -H 'content-type: application/json' \
  -d '{"customerId":"customer-1","vehicleId":"VEH-...","expectedMinutes":60}'
```

`expectedMinutes`는 `60`, `120`, `180`, `240`만 허용하며 `240`은 4시간 이상을 뜻한다. 한 번에 로봇 작업 하나만 실행하지만 주차 완료 차량은 각각 `PARKED` 상태로 유지된다.

Web Mock의 `LIVE PI`에는 다음을 입력한다.

- API: `http://192.168.0.50:8101`
- WebSocket: `ws://192.168.0.50:8101/v1/events`

`192.168.0.50`은 `hostname -I`로 확인한 Pi의 실제 IP로 바꾼다. PC와 Pi는 같은 Wi-Fi에 있어야 한다. 인증과 TLS가 없는 개발용 Gateway이므로 신뢰하는 사설망에서만 사용하고 인터넷 포트포워딩은 하지 않는다.

## 설정

| 환경 변수 | 기본값 | 용도 |
|---|---|---|
| `SNAP_HARDWARE_MODE` | `simulator` | `simulator` 또는 실제 Arduino를 쓰는 `serial` |
| `SNAP_MEGA_PORT` | `/dev/ttyACM0` | 센서 Mega Serial 장치 |
| `SNAP_MEGA_BAUD` | `115200` | Mega 전송 속도. 팀 펌웨어와 일치해야 함 |
| `SNAP_MEGA_READ_TIMEOUT_SECONDS` | `2` | Mega 한 줄 읽기 제한 시간 |
| `SNAP_MEGA_INITIAL_MASK` | 미설정 | 첫 프레임 전 초기 비트마스크. 확실할 때만 `0`~`63` 지정 |
| `SNAP_ROBOT_PORT` | `/dev/serial0` | 운반 로봇 Arduino Serial 장치 |
| `SNAP_ROBOT_BAUD` | `9600` | 로봇 전송 속도. 팀 펌웨어와 일치해야 함 |
| `SNAP_ROBOT_READ_TIMEOUT_SECONDS` | `30` | 로봇 응답 한 줄 읽기 제한 시간 |
| `SNAP_ROBOT_STARTUP_TIMEOUT_SECONDS` | `5` | 시작 시 `PING`/`PONG`과 `STATUS:IDLE` 확인 제한 시간 |
| `SNAP_SERIAL_RECONNECT_DELAY_SECONDS` | `1` | 실행 중 Serial 오류 뒤 Mega 재연결 시도 간격 |
| `SNAP_GATEWAY_PORT` | `8101` | Pi Gateway HTTP·WebSocket 포트 |
| `SNAP_GATEWAY_HOST` | `127.0.0.1` | LAN 접속 시 `0.0.0.0` 지정 |
| `SNAP_STEP_DELAY_SECONDS` | `1.05` | Simulator 상태 간 대기 시간 |
| `SNAP_CORS_ORIGINS` | localhost 두 주소 | 허용 Web/WS Origin. 쉼표로 구분 |

## 안전한 연결 검증

실제 장비에서는 차량 상태를 바꾸지 않는 검증만 실행한다.

```bash
cd ~/snap/web-mock
npm run verify:pi -- \
  --base-url http://192.168.0.50:8101 \
  --read-only
```

Hardware mode에서 `--read-only`를 빼면 실제 주차 요청과 로봇 동작이 발생할 수 있으므로 사용하지 않는다. Wi-Fi TCP 패킷은 Pi의 `tcpdump`로, Arduino UART 프레임은 Gateway 로그와 Health의 Serial 상태로 확인한다. `tcpdump`는 `/dev/ttyACM0`이나 `/dev/serial0`의 UART 바이트를 볼 수 없다. 상세 명령은 [실제 Raspberry Pi 패킷 확인 매뉴얼](../docs/manual/raspberry-pi-web-packet-cmd.md)을 참고한다.

로봇 통신·프로토콜 오류가 한 번이라도 발생하면 Gateway는 `robot.interlocked:true`와 `status:degraded`로 바꾸고 이후 모든 실물 작업을 차단한다. 모터 전원을 안전하게 차단하고 로봇을 물리적으로 대기 위치에 복구한 뒤 Gateway를 재시작해야 한다. `STATUS:IDLE`은 펌웨어 상태일 뿐 실제 위치를 측정하지 않으므로 눈으로 위치를 확인한다.

현재 고객·차량·세션은 메모리에만 있어 Gateway 재시작 후 복원되지 않는다. 또한 팀 Mega 펌웨어는 상태 변화 프레임만 보내므로 마지막 프레임 이후 펌웨어 정지를 heartbeat로 구별할 수 없다. 이 구현은 팀 실기 통신·PoC용이며, 무인 운영 전에는 영속 저장, 부팅 시 상태 대조, Mega 부팅 snapshot/heartbeat와 물리 비상 정지를 추가해야 한다.

## 테스트

```bash
python3 -m unittest discover -s tests -v
```

테스트는 시간별 주차면 배정, 고객별 복수 차량, Simulator 주차·출차, Mega `0..63` 비트마스크, 로봇 경로·응답 Codec과 Serial 오류 처리를 검증한다. 자동 테스트 통과는 실제 배선, 센서 거리, 모터 방향과 비상 정지를 대신하지 않는다.
