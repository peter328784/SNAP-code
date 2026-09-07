# Windows Web Mock과 실제 Raspberry Pi Wi-Fi 연동 매뉴얼

## 1. 목적과 완료 상태

이 문서는 처음 개발환경을 구성하는 팀원이 다음 상태까지 도달하도록 안내한다.

1. Windows PC에서 Web Mock 개발 서버를 `3101` 포트로 실행한다.
2. 실제 Raspberry Pi에서 Gateway를 `8101` 포트로 실행한다.
3. 두 장치를 같은 Wi-Fi에서 연결한다.
4. 브라우저에서 `LIVE PI`를 선택해 REST와 WebSocket을 연결한다.
5. 실제 동작을 만들지 않는 읽기 전용 명령으로 연결을 확인한다.

예시 주소는 다음과 같다.

| 이름 | 예시 | 역할 |
|---|---|---|
| `WEB_PC_IP` | `192.168.0.20` | Windows PC의 Wi-Fi IPv4 |
| `PI_IP` | `192.168.0.50` | Raspberry Pi의 Wi-Fi IPv4 |
| Web Mock | `http://localhost:3101` | 같은 Windows PC의 브라우저에서 여는 화면 |
| Web Mock LAN 주소 | `http://192.168.0.20:3101` | 다른 장치에서 화면을 열 때만 사용 |
| Pi API | `http://192.168.0.50:8101` | REST 주소 |
| Pi WebSocket | `ws://192.168.0.50:8101/v1/events` | 실시간 이벤트 주소 |

예시 IP를 그대로 사용하지 말고 각 장치에서 확인한 실제 값으로 바꾼다.

## 2. 왜 Wi-Fi로 연결할 수 있는가

```text
Windows PC
  ├── Web Mock 개발 서버 :3101 ──> 브라우저 화면 제공
  └── 브라우저
        ├── REST ────────────────> Raspberry Pi :8101
        └── WebSocket ───────────> Raspberry Pi :8101/v1/events
                                           │
                                           ├── Mega Serial 115200
                                           └── 로봇 Serial 9600
```

같은 Wi-Fi의 장치들은 사설 IP로 서로 TCP 연결을 만들 수 있다. 이 프로젝트에서는 다음 조건을 맞춘다.

- Pi Gateway를 `0.0.0.0:8101`에 열어 LAN에서 접근할 수 있게 한다.
- Gateway의 CORS 설정에 브라우저에서 연 Web 주소를 정확히 허용한다.
- 다른 장치에서 Web 화면도 열 때만 Web Mock을 `0.0.0.0:3101`에 열고 Windows 개인 네트워크 방화벽을 허용한다.

Web Mock이 화면을 중계해 주는 구조가 아니다. 브라우저가 Pi의 REST·WebSocket 주소로 직접 연결한다. 따라서 CORS Origin은 Web 주소이고, Pi에서 관측되는 패킷의 상대 주소는 브라우저를 실행한 PC의 IP다.

이 구성은 인증과 TLS가 없는 개발용 사설망 기준이다. 공유기 포트포워딩으로 `3101` 또는 `8101`을 인터넷에 공개하지 않는다.

## 3. 시작 전 준비

### Windows PC

- 팀이 공유한 SNAP 소스: `web-mock`과 `pi-bridge` 폴더가 함께 있는 버전
- Git
- Node.js `22.13.0` 이상과 npm
- PowerShell

### Raspberry Pi

- Raspberry Pi OS와 Wi-Fi 연결
- Python `3.11` 이상 권장
- 팀 펌웨어가 올라간 Mega와 로봇 Arduino
- 키보드·화면 또는 SSH로 사용할 수 있는 Pi 터미널

### 네트워크

- Windows PC와 Pi가 같은 공유기 또는 같은 Wi-Fi에 연결돼 있어야 한다.
- 게스트 Wi-Fi나 단말 격리 기능이 켜진 네트워크는 장치 간 통신을 막을 수 있다.
- 처음 시험할 때는 학교·회사 공용망보다 팀이 관리하는 사설 개발망을 권장한다.

## 4. Windows Web Mock 개발환경 구축

### 4.1 도구 버전 확인

일반 PowerShell에서 실행한다.

```powershell
git --version
node --version
npm --version
```

`node --version`이 `v22.13.0`보다 낮으면 Node.js를 갱신한 뒤 PowerShell을 새로 연다.

### 4.2 소스 준비

팀 Git 저장소를 처음 받는 경우 다음처럼 URL을 입력해 복제한다.

```powershell
$RepoUrl = Read-Host "팀 SNAP Git 저장소 URL"
git clone $RepoUrl C:\workspace\snap
```

이미 소스가 있으면 최신 팀 브랜치로 갱신한 뒤 `web-mock`으로 이동한다. 아래 경로는 예시다.

```powershell
Set-Location C:\workspace\snap\web-mock
git status --short
```

실제 보드 연동을 위해서는 받은 소스에 다음 항목이 있어야 한다.

```text
snap/
├── web-mock/
│   ├── package.json
│   └── scripts/verify-pi-gateway.mjs
└── pi-bridge/
    ├── requirements.txt
    └── app/runtime.py
```

### 4.3 의존성 설치와 개발 서버 실행

```powershell
Set-Location C:\workspace\snap\web-mock
npm.cmd ci
npm.cmd run dev
```

이 명령은 같은 Windows PC의 브라우저에서 `http://localhost:3101`로 사용할 때의 기본 실행법이다. 이 PowerShell은 Web Mock 로그를 보여주므로 그대로 둔다. 새 PowerShell에서 응답을 확인한다.

```powershell
curl.exe --fail --silent --show-error http://127.0.0.1:3101/
```

### 4.4 Windows Wi-Fi IP 확인

```powershell
Get-NetIPConfiguration |
  Where-Object { $_.NetAdapter.Status -eq "Up" } |
  Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway
```

`Wi-Fi` 행의 IPv4를 `WEB_PC_IP`로 사용한다. 예를 들어 `192.168.0.20`이면 브라우저 주소는 다음과 같다.

```text
http://192.168.0.20:3101
```

VPN, 가상 네트워크, Ethernet 주소가 함께 표시될 수 있다. Pi와 같은 공유기의 기본 게이트웨이를 사용하는 Wi-Fi 주소를 선택한다.

다른 PC에서도 Web 화면을 열어야 할 때만 기본 개발 서버를 종료하고 다음처럼 LAN 주소에 다시 연다.

```powershell
Set-Location C:\workspace\snap\web-mock
npm.cmd run dev -- --hostname 0.0.0.0
```

### 4.5 Windows 방화벽 허용

처음 실행할 때 Windows 보안 창이 나타나면 **개인 네트워크**만 허용한다. 다른 PC에서 `3101`에 접근해야 하는데 차단될 때만 관리자 PowerShell에서 다음 규칙을 추가한다.

```powershell
New-NetFirewallRule `
  -DisplayName "SNAP Web Mock 3101" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 3101 `
  -Profile Private
```

규칙 확인:

```powershell
Get-NetFirewallRule -DisplayName "SNAP Web Mock 3101"
```

더 이상 LAN 접속이 필요 없을 때 관리자 PowerShell에서 제거할 수 있다.

```powershell
Remove-NetFirewallRule -DisplayName "SNAP Web Mock 3101"
```

## 5. Raspberry Pi Gateway 개발환경 구축

이 절부터는 **실제 Pi 터미널**에서 실행한다.

### 5.1 Pi 주소와 Python 확인

```bash
hostname
hostname -I
ip -4 route
python3 --version
```

`hostname -I`의 Wi-Fi IPv4를 `PI_IP`로 사용한다. 예를 들어 `192.168.0.50`이면 Pi API 주소는 `http://192.168.0.50:8101`이다.

### 5.2 기본 패키지와 소스 준비

```bash
sudo apt update
sudo apt install -y git curl iproute2 python3 python3-venv python3-pip
```

Pi에도 팀 SNAP 소스가 없다면 복제한다.

```bash
read -rp "팀 SNAP Git 저장소 URL: " snap_repo_url
git clone "$snap_repo_url" "$HOME/snap"
```

이미 소스가 있다면 팀에서 정한 방식으로 최신 브랜치를 받은 뒤 다음 파일을 확인한다.

```bash
cd "$HOME/snap/pi-bridge"
ls requirements.txt app/runtime.py
```

### 5.3 Python 가상환경과 의존성 설치

```bash
cd "$HOME/snap/pi-bridge"
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -c 'import serial; print(serial.VERSION)'
```

다음에 다시 실행할 때는 `source .venv/bin/activate`만 하면 된다.

### 5.4 로봇 UART와 Serial 장치 준비

로봇 Arduino를 Pi GPIO UART에 연결하는 구성이라면 한 번만 설정한다.

```bash
sudo raspi-config
```

`Interface Options` → `Serial Port`에서 다음처럼 선택한 뒤 재부팅한다.

- 로그인 셸이 Serial을 사용하도록 할 것인가: `No`
- Serial 포트 하드웨어를 사용할 것인가: `Yes`

```bash
sudo reboot
```

재접속한 뒤 장치를 확인한다.

```bash
ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
ls -l /dev/serial/by-id/ 2>/dev/null
groups
```

기본 설정은 Mega `/dev/ttyACM0`·`115200`, 로봇 `/dev/serial0`·`9600`이다. USB 연결 방식이나 장치 이름이 다르면 실제 경로를 실행 환경변수에 사용한다.

현재 사용자에게 `dialout` 그룹이 없으면 한 번만 추가한 뒤 로그아웃하고 다시 접속한다.

```bash
sudo usermod -aG dialout "$USER"
```

Raspberry Pi의 GPIO UART는 **3.3V 전용**이므로 5V TTL 출력을 Pi RX에 직접 연결하면 보드가 손상될 수 있다. 5V Arduino와 GPIO UART를 연결한다면 검증된 레벨 시프터 또는 분압 회로를 사용한다. TX/RX 교차 연결과 공통 GND도 팀 배선도를 따르고, 모터 전원을 분리한 상태에서 통신부터 확인한다. 자세한 전기 조건은 [Raspberry Pi 공식 UART 문서](https://www.raspberrypi.com/documentation/computers/configuration.html#configure-uarts)를 참고한다.

### 5.5 실제 보드 모드로 Gateway 실행

먼저 로봇을 사람이 직접 대기 위치에 두고, 바퀴나 구동부가 예기치 않게 움직여도 위험하지 않은 상태를 만든다. Web Origin의 `192.168.0.20`은 앞에서 확인한 Windows PC IP로 바꾼다.

```bash
cd "$HOME/snap/pi-bridge"
source .venv/bin/activate

SNAP_HARDWARE_MODE=serial \
SNAP_MEGA_PORT=/dev/ttyACM0 \
SNAP_MEGA_BAUD=115200 \
SNAP_MEGA_READ_TIMEOUT_SECONDS=2 \
SNAP_ROBOT_PORT=/dev/serial0 \
SNAP_ROBOT_BAUD=9600 \
SNAP_ROBOT_READ_TIMEOUT_SECONDS=30 \
SNAP_ROBOT_STARTUP_TIMEOUT_SECONDS=5 \
SNAP_SERIAL_RECONNECT_DELAY_SECONDS=1 \
SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_GATEWAY_PORT=8101 \
SNAP_CORS_ORIGINS='http://192.168.0.20:3101,http://localhost:3101,http://127.0.0.1:3101' \
python -m app
```

Gateway는 시작할 때 다음 순서로 안전 상태를 확인한다.

1. Mega와 로봇 Serial 포트를 연다.
2. 로봇에 `PING`을 보내 `PONG`을 확인한다.
3. 로봇에 `STATUS`를 보내 `STATUS:IDLE`을 확인한다.
4. REST·WebSocket 서버를 `0.0.0.0:8101`에 연다.

포트 열기나 응답 확인이 실패하면 Gateway는 시작하지 않는다. 오류 메시지에 표시된 장치 경로, 권한, 펌웨어, 배선을 먼저 해결한다.

Gateway 실행 중에는 Arduino IDE Serial Monitor, `minicom`, `picocom`, 별도 Serial 스크립트를 동시에 열지 않는다. Gateway가 Serial 포트의 유일한 소유자여야 한다.

Mega 펌웨어는 점유 상태가 바뀔 때만 프레임을 보낸다. 첫 실제 프레임 전에는 `/health`가 `degraded`, `mega.verified:false`인 것이 정상이다. 모든 주차면이 비어 있다고 추측해 초기값을 강제로 넣지 말고, 안전하게 센서 상태를 한 번 변경해 실제 프레임을 발생시킨다.

### 5.6 Pi 내부 확인

Gateway 터미널은 그대로 두고 Pi의 두 번째 터미널에서 실행한다.

```bash
curl --fail --silent --show-error \
  http://127.0.0.1:8101/health \
  | python3 -m json.tool

sudo ss -ltnp 'sport = :8101'
```

확인값:

- `mode`가 `pi-hardware-snap-code`
- `hardware.robot.connected`와 `hardware.robot.ready`가 `true`
- 실제 Mega 프레임 수신 후 `hardware.mega.verified`가 `true`
- `ss`에 `0.0.0.0:8101` 표시

## 6. Windows에서 Pi Wi-Fi 연결 확인

새 PowerShell에서 실제 Pi IP를 지정한다.

```powershell
$PiIp = "192.168.0.50"
$WebPcIp = "192.168.0.20"
$WebOrigin = "http://localhost:3101"
```

다른 장치에서 Windows PC의 Web 화면을 열 때는 마지막 값을 다음처럼 바꾼다.

```powershell
$WebOrigin = "http://${WebPcIp}:3101"
```

### 6.1 TCP와 Health

```powershell
Test-NetConnection `
  -ComputerName $PiIp `
  -Port 8101 `
  -InformationLevel Detailed

curl.exe --fail --silent --show-error `
  "http://${PiIp}:8101/health"
```

`TcpTestSucceeded : True`이고 Health JSON이 출력돼야 한다. `ping` 응답 여부만으로 판단하지 않는다. 공유기나 방화벽이 ICMP를 막아도 TCP는 정상일 수 있다.

### 6.2 CORS 사전 요청

```powershell
curl.exe -i -X OPTIONS `
  "http://${PiIp}:8101/v1/parking-requests" `
  -H "Origin: $WebOrigin" `
  -H "Access-Control-Request-Method: POST" `
  -H "Access-Control-Request-Headers: content-type"
```

응답 헤더에 `$WebOrigin`으로 지정한 실제 Web 주소가 정확히 표시돼야 한다.

```text
access-control-allow-origin: http://localhost:3101
```

값이 없으면 Pi에서 Gateway를 종료하고 `SNAP_CORS_ORIGINS`의 IP와 브라우저 주소를 일치시켜 다시 실행한다.

### 6.3 REST·WebSocket 읽기 전용 검증

```powershell
Set-Location C:\workspace\snap\web-mock

npm.cmd run verify:pi -- `
  --base-url "http://${PiIp}:8101" `
  --read-only
```

이 명령은 Snapshot 조회와 WebSocket 초기 이벤트만 확인하며 차량 등록·주차·출차 요청을 만들지 않는다. 실제 장비에서는 처음부터 `--read-only`를 사용한다.

이 검증은 Node.js에서 실행되므로 브라우저 CORS 자체는 검사하지 않는다. 따라서 앞 절의 CORS 확인과 브라우저 연결도 함께 수행해야 한다.

## 7. Web Mock에서 `LIVE PI` 연결

같은 Windows PC의 브라우저에서는 다음 주소를 연다.

```text
http://localhost:3101
```

다른 장치에서 Web 화면을 열도록 4.4~4.5절의 선택 설정까지 했다면 다음 주소를 연다.

```text
http://192.168.0.20:3101
```

두 주소 중 실제로 연 주소가 Pi의 `SNAP_CORS_ORIGINS`에 있어야 한다. 이 매뉴얼의 Gateway 실행 명령은 둘 다 허용한다.

1. 화면 위의 모드를 `LIVE PI`로 변경한다.
2. 연결 설정을 연다.
3. API 기본 주소에 `http://192.168.0.50:8101`을 입력한다.
4. WebSocket 주소에 `ws://192.168.0.50:8101/v1/events`를 입력한다.
5. `저장 후 연결`을 누른다.

정상 상태:

- 상단 연결 표시가 `LIVE PI`
- EVENT STREAM에 `PI CONNECT`
- Pi Gateway 터미널에 REST `200`과 WebSocket `/v1/events` 연결 로그
- Pi에서 `sudo ss -tnp 'sport = :8101'` 실행 시 `ESTAB` 연결

연결 확인만 마친 단계에서는 차량 등록이나 주차 버튼을 누르지 않는다. 실제 주차 요청은 로봇 안전 상태와 비상 정지 수단을 팀원이 함께 확인한 뒤 수행한다.

## 8. 개발환경 검사

Windows에서 Web Mock 정적 검사를 실행한다.

```powershell
Set-Location C:\workspace\snap\web-mock
npm.cmd run lint
npm.cmd run build
```

Pi에서 Gateway 테스트를 실행한다.

```bash
cd "$HOME/snap/pi-bridge"
source .venv/bin/activate
python -m unittest discover -s tests -v
```

자동 검사는 네트워크·프로토콜 코드를 검증하지만 실제 배선, 센서 거리, 모터 방향, 비상 정지를 대신하지 않는다.

## 9. 오류 해결

### Windows에서 `192.168.0.20:3101`을 열 수 없음

Windows에서 확인한다.

```powershell
Get-NetTCPConnection -LocalPort 3101 -State Listen
Test-NetConnection -ComputerName 127.0.0.1 -Port 3101
```

- 다른 장치에서 열 때 개발 서버를 `npm.cmd run dev -- --hostname 0.0.0.0`으로 실행했는지 확인
- `WEB_PC_IP`를 현재 Wi-Fi IP로 다시 확인
- Windows 네트워크 프로필이 개인 네트워크인지 확인
- `3101/TCP` 개인 네트워크 방화벽 규칙 확인

### Windows에서 `PI_IP:8101` 접속 실패

Pi에서 확인한다.

```bash
hostname -I
curl --fail --silent --show-error http://127.0.0.1:8101/health
sudo ss -ltnp 'sport = :8101'
```

- `127.0.0.1:8101`만 표시되면 `SNAP_GATEWAY_HOST=0.0.0.0`으로 다시 실행
- PC와 Pi의 IPv4 앞부분과 기본 게이트웨이가 같은지 확인
- 공유기의 게스트 Wi-Fi·단말 격리 설정 확인
- Pi IP가 재부팅 후 바뀌지 않았는지 확인
- Pi에 별도 방화벽을 설정했다면 `8101/TCP` LAN 접근 규칙 확인

### EVENT STREAM에 `PI ERROR Not Found`

연결 주소를 다음처럼 바로잡는다.

```text
API:       http://192.168.0.50:8101
WebSocket: ws://192.168.0.50:8101/v1/events
```

- API 주소 끝에 `/health` 또는 `/v1/events`를 붙이지 않는다.
- WebSocket 경로에는 `/v1/events`를 붙인다.
- 예전에 저장한 주소가 남아 있으면 연결 설정을 다시 저장한다.
- Pi 내부 `/health`가 성공하는지 먼저 확인한다.

### 브라우저에 CORS 오류 표시

브라우저 주소와 `SNAP_CORS_ORIGINS`는 문자열 전체가 일치해야 한다. `localhost`, `127.0.0.1`, `192.168.0.20`은 서로 다른 Origin이다. 실제로 연 Web 주소를 Pi 실행 명령에 추가하고 Gateway를 다시 시작한다.

### Gateway가 Serial 오류로 시작하지 않음

```bash
ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
ls -l /dev/serial/by-id/ 2>/dev/null
groups
sudo fuser -v /dev/ttyACM0 /dev/serial0
```

- 실제 장치 경로를 `SNAP_MEGA_PORT`, `SNAP_ROBOT_PORT`에 반영
- `dialout` 그룹 추가 후 재로그인 여부 확인
- 다른 Serial Monitor나 스크립트 종료
- Mega `115200`, 로봇 `9600` 설정 확인
- 팀 펌웨어가 올라가 있는지 확인

### Health가 계속 `degraded`

- `mega.verified:false`: Mega의 실제 점유 프레임을 아직 받지 못함
- `robot.ready:false`: 시작 시 `PONG` 또는 `STATUS:IDLE` 확인 실패
- `robot.interlocked:true`: 작업 중 오류가 발생해 추가 명령이 차단됨
- `lastError`: 마지막 Serial 또는 프로토콜 오류 내용

Interlock이 걸리면 프로그램만 다시 누르지 않는다. 모터 전원을 안전하게 차단하고 사람이 로봇을 실제 대기 위치에 복구한 뒤 Gateway를 재시작한다.

## 10. 최종 체크리스트

- [ ] Windows `node --version`이 `v22.13.0` 이상이다.
- [ ] 같은 PC에서는 Web Mock `http://localhost:3101`이 열린다.
- [ ] 다른 장치에서 열 때만 Web Mock이 `0.0.0.0:3101`로 실행 중이고 개인 네트워크 방화벽 규칙이 있다.
- [ ] Pi와 Windows PC가 같은 Wi-Fi에 있다.
- [ ] Pi Gateway가 `0.0.0.0:8101`로 실행 중이다.
- [ ] `Test-NetConnection`의 `TcpTestSucceeded`가 `True`다.
- [ ] Windows에서 Pi `/health` JSON을 받는다.
- [ ] CORS 응답에 실제 Web Origin이 있다.
- [ ] `verify:pi --read-only`가 통과한다.
- [ ] Web Mock 상단에 `LIVE PI`, EVENT STREAM에 `PI CONNECT`가 표시된다.
- [ ] Pi 패킷 캡처에 Windows PC와 `8101/TCP` 통신이 보인다.

현재 팀 로봇 펌웨어는 실제 장비의 주차 경로만 제공한다. 실제 장비 모드의 출차 요청은 `409 Conflict`로 거절된다. 고객·차량·주차 세션도 Gateway 메모리에만 있어 재시작 후 복원되지 않으므로, 이 절차는 팀 실기 통신과 개발 검증용으로 사용한다.
