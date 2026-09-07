# 실제 Raspberry Pi에서 Web Mock 통신 패킷 확인하기

## 문서 목적

이 문서는 **실제 Raspberry Pi 보드의 터미널**에서 Web Mock과 Pi Gateway 사이의 통신을 확인하는 명령만 설명한다.

- 네트워크 통신: Wi-Fi/Ethernet의 `8101/TCP` REST·WebSocket 패킷
- 보드 통신: Pi와 두 Arduino 사이의 Serial(UART) 프레임

두 통신은 서로 다르다. `tcpdump`로는 `8101/TCP`만 볼 수 있고, Arduino 프레임은 Gateway 실행 로그와 `/health`에서 확인한다.

아래 예시에서는 다음 주소를 사용한다.

| 장치 | 예시 주소 |
|---|---|
| Web Mock을 실행하고 브라우저를 여는 Windows PC | `192.168.0.20` |
| Raspberry Pi | `192.168.0.50` |

주소는 팀원의 실제 환경에 맞게 바꾼다. 이 문서의 명령은 별도 표시가 없는 한 모두 Pi 터미널에서 실행한다.

## 1. 진단 명령 설치

```bash
sudo apt update
sudo apt install -y curl iproute2 tcpdump psmisc
```

- `ss`: 수신 포트와 현재 TCP 연결 확인
- `tcpdump`: 실제 네트워크 패킷 출력·저장
- `fuser`: 포트 또는 Serial 장치를 사용 중인 프로세스 확인

## 2. Pi 주소와 Gateway 응답 확인

Pi의 실제 IPv4 주소를 확인한다.

```bash
hostname -I
ip -4 address show
ip -4 route
```

Gateway가 Pi 내부에서 응답하는지 확인한다.

```bash
curl --fail --silent --show-error \
  http://127.0.0.1:8101/health \
  | python3 -m json.tool
```

실제 Arduino를 사용하는 경우 핵심 확인값은 다음과 같다.

```text
mode: pi-hardware-snap-code
hardware.mega.connected: true
hardware.mega.verified: true
hardware.robot.connected: true
hardware.robot.ready: true
hardware.robot.interlocked: false
```

`mega.verified:false`는 아직 Mega에서 실제 점유 프레임을 받지 못했다는 뜻이다. 센서 상태를 안전하게 한 번 변경한 뒤 다시 확인한다. `robot.interlocked:true`이면 추가 명령을 보내지 말고 로봇 전원을 안전하게 차단한 뒤 실제 대기 위치 복구 절차를 수행한다.

## 3. `8101` 수신 포트 확인

```bash
sudo ss -ltnp 'sport = :8101'
```

LAN 연결이 가능한 정상 예:

```text
LISTEN ... 0.0.0.0:8101 ... python
```

- `0.0.0.0:8101`: 같은 네트워크의 PC에서 접속 가능
- `127.0.0.1:8101`: Pi 내부에서만 접속 가능. Gateway를 `SNAP_GATEWAY_HOST=0.0.0.0`으로 다시 실행해야 함
- 출력 없음: Gateway가 실행되지 않았거나 다른 포트로 실행됨

포트 사용 프로세스를 추가로 확인한다.

```bash
sudo fuser -v 8101/tcp
ps -ef | grep '[p]ython -m app'
```

## 4. WebSocket 연결 확인

Web Mock에서 `LIVE PI` 연결을 완료한 상태로 실행한다.

```bash
sudo ss -tnp 'sport = :8101'
```

브라우저와 Pi 사이의 WebSocket이 연결돼 있으면 `ESTAB` 행이 유지된다. REST 요청은 짧게 연결됐다가 종료되므로 `ss`에서 놓칠 수 있다.

연결 수만 반복 확인하려면 다음 명령을 사용한다.

```bash
watch -n 1 "ss -Htn 'sport = :8101'"
```

종료는 `Ctrl+C`다.

## 5. `8101/TCP` 패킷 실시간 출력

가장 먼저 다음 기본 명령을 사용한다.

```bash
sudo tcpdump -ni any -nn -tttt 'tcp port 8101'
```

그 상태에서 Web Mock의 `LIVE PI` 연결을 다시 저장하거나 새로고침한다. 차량 등록 또는 주차 요청은 실제 상태와 모터 동작을 바꿀 수 있으므로, 처음에는 연결과 조회만 확인한다.

출력 예:

```text
192.168.0.20.53000 > 192.168.0.50.8101: Flags [S]
192.168.0.50.8101 > 192.168.0.20.53000: Flags [S.]
192.168.0.20.53000 > 192.168.0.50.8101: Flags [P.]
```

첫 줄은 Windows PC가 Pi의 `8101` 포트에 연결을 시작했다는 뜻이다. 종료는 `Ctrl+C`다.

Windows PC의 패킷만 보려면 예시 IP를 실제 PC 주소로 바꾼다.

```bash
sudo tcpdump -ni any -nn -tttt \
  'host 192.168.0.20 and tcp port 8101'
```

Wi-Fi 인터페이스만 지정하려면 먼저 이름을 확인한다.

```bash
ip -brief link
ip -brief address
```

Raspberry Pi OS에서 보통 `wlan0`이지만 출력으로 확인한 뒤 사용한다.

```bash
sudo tcpdump -ni wlan0 -nn -tttt 'tcp port 8101'
```

## 6. HTTP 내용을 짧게 확인

개발용 HTTP는 암호화되지 않으므로 다음 명령으로 헤더와 일부 본문을 볼 수 있다.

```bash
sudo timeout 20 \
  tcpdump -ni any -nn -s 0 -A 'tcp port 8101'
```

`20`은 20초 뒤 자동 종료한다는 뜻이다. WebSocket 데이터는 프레임 형식 때문에 모든 내용이 읽기 쉽게 출력되지는 않지만, 연결 경로와 HTTP 요청은 확인할 수 있다.

> 이 출력에는 고객 식별자, 차량번호, 내부 차량 ID가 평문으로 포함될 수 있다. 신뢰하는 개발용 사설망에서만 짧게 사용하고 화면이나 로그를 공개 채널에 올리지 않는다.

## 7. 제한된 크기로 PCAP 저장

재현이 어려운 문제는 저장소 밖에 최대 약 30 MB로 캡처한다.

```bash
capture_dir="$HOME/snap-captures"
capture_file="$capture_dir/pi-8101.pcap"

mkdir -p "$capture_dir"

sudo timeout 60 \
  tcpdump -ni any -nn -s 0 \
  -C 10 -W 3 \
  -w "$capture_file" \
  'tcp port 8101'
```

- `timeout 60`: 최대 60초 캡처
- `-C 10`: 파일당 약 10 MB
- `-W 3`: 파일 최대 3개 순환 사용

저장 결과를 확인한다.

```bash
sudo chown "$USER":"$(id -gn)" "$capture_dir"/pi-8101.pcap*
chmod 600 "$capture_dir"/pi-8101.pcap*
ls -lh "$capture_dir"

for capture_path in "$capture_dir"/pi-8101.pcap*; do
  tcpdump -nn -r "$capture_path"
done
```

PCAP에는 고객·차량 정보가 포함될 수 있다. 저장소에 복사하거나 Git에 커밋하지 말고, 공유가 끝나면 팀의 보안 규칙에 따라 삭제한다.

## 8. Arduino Serial 통신 확인

### 8.1 장치와 소유 프로세스

```bash
ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
ls -l /dev/serial/by-id/ 2>/dev/null
sudo fuser -v /dev/ttyACM0 /dev/serial0
```

기본 연결은 다음과 같다.

| 장치 | 기본 포트 | 속도 | 프레임 |
|---|---|---:|---|
| 주차면 센서 Mega | `/dev/ttyACM0` | `115200` | ASCII 10진 비트마스크 `0..63` + 줄바꿈 |
| 운반 로봇 Arduino | `/dev/serial0` | `9600` | 경로 문자열과 줄 단위 상태 응답 |

Gateway가 실행 중일 때 Arduino IDE Serial Monitor, `minicom`, `picocom`, 별도 Serial 스크립트를 동시에 실행하지 않는다. 같은 장치를 여러 프로그램이 읽으면 프레임이 분산되거나 포트를 열지 못한다.

### 8.2 Gateway 전면 로그

Gateway를 실행한 첫 번째 Pi 터미널에서 UART 로그를 확인한다.

```text
UART TX robot device=/dev/serial0 baud=9600 frame='PING'
UART RX robot device=/dev/serial0 baud=9600 frame='PONG'
UART TX robot device=/dev/serial0 baud=9600 frame='STATUS'
UART RX robot device=/dev/serial0 baud=9600 frame='STATUS:IDLE'
UART RX mega device=/dev/ttyACM0 baud=115200 frame='5'
UART TX robot device=/dev/serial0 baud=9600 frame='LCPSBWB'
UART RX robot device=/dev/serial0 baud=9600 frame='ROUTE_ACCEPTED:7'
```

의미:

- `PING` → `PONG`: 로봇 Serial 왕복 통신 확인
- `STATUS` → `STATUS:IDLE`: 펌웨어가 유휴 상태라고 응답
- `UART RX mega ... frame='5'`: 슬롯 1과 3 점유 비트 수신
- 경로 전송 후 `ROUTE_ACCEPTED`, 모든 `ACTION_START`/`ACTION_DONE`, 마지막 `ROUTE_DONE`: 주차 경로 수행 확인

`STATUS:IDLE`은 펌웨어 상태일 뿐 로봇의 실제 위치를 측정하지 않는다. 구동 전에는 사람이 직접 로봇이 대기 위치에 있는지 확인한다.

## 9. 빠른 문제 판별표

| 확인 결과 | 판단 | 다음 확인 |
|---|---|---|
| Pi 내부 `curl` 실패 | Gateway 미실행 또는 시작 실패 | Gateway 실행 터미널 오류 |
| `127.0.0.1:8101`만 LISTEN | 외부 접속 차단 상태 | `SNAP_GATEWAY_HOST=0.0.0.0` |
| `0.0.0.0:8101` LISTEN, 패킷 없음 | PC에서 Pi까지 도달하지 않음 | IP, 같은 Wi-Fi, 공유기 단말 격리 |
| SYN만 반복 | Pi 방화벽 또는 응답 경로 문제 | Pi 방화벽·라우팅 |
| TCP 연결 후 HTTP 오류 | URL 또는 API 경로 문제 | API 기본 URL은 `http://PI_IP:8101` |
| `ss`에 `ESTAB` 유지 | WebSocket TCP 연결 정상 | Gateway 로그의 `/v1/events` |
| TCP는 정상, UART 로그 없음 | 네트워크와 Serial은 별도 문제 | 포트, 속도, 배선, 펌웨어 |
| `mega.verified:false` | 실제 Mega 프레임 미수신 | 안전하게 센서 상태 변경 |
| `robot.interlocked:true` | 로봇 오류 후 작업 차단 | 물리 복구 후 Gateway 재시작 |

## 10. 확인 완료 기준

다음 항목이 모두 맞으면 Web Mock과 실제 Pi 사이의 패킷이 보드에 도착하고 Gateway가 처리 중인 것이다.

1. `curl http://127.0.0.1:8101/health` 성공
2. `ss`에 `0.0.0.0:8101` 수신 표시
3. Web Mock 연결 중 `ss`에 `ESTAB` 표시
4. `tcpdump`에 `192.168.0.20 → 192.168.0.50:8101` 패킷 표시
5. Gateway 로그에 REST `200` 또는 WebSocket `/v1/events` 연결 표시
6. 실제 장비 모드라면 `mode: pi-hardware-snap-code` 및 UART TX/RX 로그 표시

현재 실제 로봇 펌웨어에는 주차 경로만 정의돼 있다. 실제 장비 모드의 출차 요청은 안전을 위해 `409 Conflict`로 거절된다. 또한 통신 오류로 interlock이 걸린 상태에서는 추가 주차 요청을 시험하지 않는다.
