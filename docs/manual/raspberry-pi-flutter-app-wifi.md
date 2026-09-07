# Flutter 고객 앱과 실제 Raspberry Pi Wi-Fi 연동 매뉴얼

> 이 문서는 앱 빌드와 Gateway 운영 담당자용이다. 앱 개발 경험 없이 Windows 10·11에서 Galaxy 또는 iPhone 배포본만 설치·확인하려면 [Windows 팀원용 실기기 확인 매뉴얼](windows-mobile-app-device-check.md)을 먼저 따른다.

Flutter의 기능과 Dart·Android·iOS의 관계가 낯설다면 [처음 배우는 모바일 앱 기술](../mobile-flutter-beginner-guide.md)을 먼저 읽는다.

## 1. 목적과 완료 상태

이 문서는 처음 환경을 구성하는 팀원이 다음 상태까지 확인하도록 안내한다.

1. Windows PC에 Flutter Android 개발환경을 설치한다.
2. Android 실기기에 S.N.A.P 고객 앱을 실행한다.
3. 실제 Raspberry Pi에서 Gateway를 `8101` 포트로 실행한다.
4. 휴대폰과 Pi를 같은 Wi-Fi에 연결한다.
5. 앱에서 고객별 차량을 등록하고 Pi의 REST·WebSocket 상태를 받는다.
6. Pi 터미널에서 휴대폰 패킷이 도착하는지 확인한다.

기본 실습 대상은 **Windows 개발 PC + Android 실기기 + 실제 Raspberry Pi**다. iOS 앱은 같은 Flutter 소스를 사용하지만 빌드와 실기기 설치에 macOS와 Xcode가 필요하므로 13절에서 따로 설명한다.

아래 IP는 예시다.

| 이름 | 예시 | 역할 |
|---|---|---|
| `PI_IP` | `192.168.0.50` | 실제 Raspberry Pi의 Wi-Fi IPv4 |
| `PHONE_IP` | `192.168.0.80` | 앱을 실행하는 휴대폰의 Wi-Fi IPv4 |
| Pi API | `http://192.168.0.50:8101` | 앱이 호출할 Gateway 기본 주소 |

팀원의 실제 IP로 바꿔 사용한다. `0.0.0.0`, `127.0.0.1`, `localhost`는 실기기 앱에 넣을 Pi 주소가 아니다.

## 2. 통신 구조와 가능한 이유

```text
Android 또는 iPhone 고객 앱
        │
        ├── REST       차량 조회·등록, 주차·출차 요청
        └── WebSocket  주차장·로봇·작업 상태 실시간 수신
        │
        │ Wi-Fi · TCP 8101
        ▼
실제 Raspberry Pi Gateway
        ├── Mega Serial      /dev/ttyACM0 · 115200
        └── 로봇 Serial      /dev/serial0  · 9600
```

공유기는 휴대폰과 Pi에 같은 로컬 네트워크의 사설 IP를 할당하고 두 주소 사이의 패킷을 전달한다. Pi Gateway가 `0.0.0.0:8101`에서 기다리면 휴대폰은 Pi의 실제 IP와 `8101` 포트로 연결할 수 있다.

앱은 Arduino에 직접 연결하지 않는다. 앱은 고객의 요청만 Pi Gateway에 보내고, Pi는 물리 경로·Serial 통신과 통신/작업 오류 뒤 후속 요청을 막는 **소프트웨어 fault interlock**을 담당한다. 이 interlock은 물리 비상 정지 장치나 로봇 위치 증명을 대신하지 않는다. USB 디버깅 케이블은 앱을 휴대폰에 설치하는 용도이며, 설치된 앱과 Pi의 통신은 Wi-Fi로 이동한다.

Flutter 앱은 브라우저가 아닌 네이티브 `HttpClient`와 `WebSocket`을 사용하므로 브라우저 CORS 설정은 필요하지 않다. HTTP 기본 주소가 `http://...`이면 앱이 `ws://.../v1/events`를 자동으로 만들고, `https://...`이면 `wss://.../v1/events`를 사용한다.

## 3. 현재 구현 범위와 제한

현재 `mobile/` 소스에는 다음 기능이 구현돼 있다.

- 고객별 여러 차량 조회·등록
- 차량별 예상 주차시간 `60`, `120`, `180`, `240`분 선택
- 주차 요청과 원터치 출차 요청
- REST Snapshot과 WebSocket 실시간 이벤트 반영
- 연결 단절 시 재연결 및 Snapshot 재조회
- 물리 요청 전송 중 중복 버튼 입력 차단

현재 설정은 앱 내부 입력 화면이나 로그인 결과가 아니라 Flutter 실행 시 `--dart-define`으로 주입된다.

| 설정 | 기본값 | 실기기 설정 |
|---|---|---|
| `PI_API_BASE_URL` | `http://127.0.0.1:8101` | Pi 실제 IP로 반드시 변경 |
| `PI_LOT_ID` | `demo-01` | 현재 Gateway와 동일하게 유지 |
| `PI_CUSTOMER_ID` | `demo-customer` | 휴대폰·사용자별 고유 테스트 ID 사용 |

`PI_CUSTOMER_ID`는 고객 데이터를 구분하는 문자열일 뿐 인증 수단이 아니다. 운영 배포에는 별도의 로그인, 토큰, 서버 권한 검사가 필요하다.

실제 하드웨어 모드는 현재 팀 로봇 펌웨어의 **주차 경로만** 지원한다. 실제 장비에서 출차 요청을 누르면 `409 Conflict`로 거절되는 것이 현재 정상 동작이다. 출차 UI 흐름은 Pi Simulator에서만 시험한다.

## 4. 시작 전 준비

### Windows 개발 PC

- 64비트 Windows 10 또는 Windows 11
- Git for Windows와 Git Bash
- Flutter Stable SDK
- Android Studio, Android SDK와 Platform Tools
- 현재 프로젝트의 `mobile/` 소스

Flutter 공식 설치·Android 설정 절차:

- [Windows Flutter Android 개발환경](https://docs.flutter.dev/get-started/install/windows/mobile)
- [Flutter Android 도구와 기기 설정](https://docs.flutter.dev/platform-integration/android/setup)
- [Android 실기기 디버깅](https://developer.android.com/studio/run/device)

### Raspberry Pi

- Raspberry Pi OS와 Python `3.11` 이상 권장
- 현재 프로젝트의 `pi-bridge/` 소스
- 팀 펌웨어가 올라간 Mega와 로봇 Arduino
- SSH 또는 직접 사용할 수 있는 Pi 터미널

### Android 휴대폰

- Pi와 연결할 Wi-Fi
- 데이터 전송이 가능한 USB 케이블
- 개발자 옵션과 USB 디버깅

### 네트워크

- Pi, 휴대폰, Windows 개발 PC를 서로 접근 가능한 같은 LAN에 연결한다. PC는 같은 공유기의 유선 LAN이어도 된다.
- 게스트 Wi-Fi나 AP/Client Isolation이 적용된 네트워크는 사용하지 않는다.
- 처음 확인할 때 휴대폰과 개발 PC의 VPN을 끈다.
- `8101`을 공유기 포트포워딩으로 인터넷에 공개하지 않는다.

## 5. Windows Flutter Android 개발환경 구축

### 5.1 Flutter와 Android 도구 확인

PowerShell을 새로 열고 실행한다.

```powershell
git --version
flutter --version
dart --version
flutter doctor -v
```

Flutter 명령이 없다면 Flutter Stable SDK를 공백·특수문자·관리자 권한이 필요 없는 경로에 설치하고 SDK의 `bin`을 Windows `PATH`에 추가한다. Android Studio에서 Android SDK와 Command-line Tools를 설치한 뒤 라이선스를 확인한다.

```powershell
flutter doctor --android-licenses
flutter doctor -v
```

사용할 Android 관련 항목이 `flutter doctor -v`에서 정상이어야 한다. Windows Desktop이나 iOS 항목은 이 Android 실습의 통과 조건이 아니다.

### 5.2 프로젝트 소스 준비

팀 Git 저장소를 처음 받는 경우 PowerShell에서 실행한다.

```powershell
$RepoUrl = Read-Host "팀 SNAP Git 저장소 URL"
git clone $RepoUrl C:\workspace\snap
Set-Location C:\workspace\snap\mobile
```

이미 소스가 있으면 팀의 최신 브랜치를 받은 뒤 다음 파일을 확인한다.

```powershell
Set-Location C:\workspace\snap\mobile
Get-Item pubspec.yaml, tool\bootstrap_platforms.sh
```

받은 소스에는 최소한 다음 두 폴더가 함께 있어야 한다.

```text
snap/
├── mobile/
│   ├── lib/
│   ├── tool/
│   └── pubspec.yaml
└── pi-bridge/
    ├── app/
    └── requirements.txt
```

### 5.3 Android·iOS 플랫폼 러너 생성

현재 저장소는 공통 Dart 소스만 포함할 수 있으므로 먼저 `android/`와 `ios/` 존재 여부를 확인한다.

```powershell
Test-Path .\android
Test-Path .\ios
```

두 결과가 모두 `False`이면 **Git Bash**를 열어 다음을 실행한다. PowerShell에서 `.sh` 파일을 직접 실행하지 않는다.

```bash
cd /c/workspace/snap/mobile
sh tool/bootstrap_platforms.sh --allow-insecure-local-http
```

스크립트는 임시 Flutter 프로젝트에서 공식 `android/`, `ios/`, `.metadata`만 가져오며 기존 공통 Dart 소스를 덮어쓰지 않는다. `--allow-insecure-local-http`는 현재 개발용 Pi의 HTTP·WS 연결을 허용한다.

두 디렉터리가 이미 모두 있으면 bootstrap을 다시 실행하지 말고 PowerShell에서 네트워크 설정만 적용한다.

```powershell
Set-Location C:\workspace\snap\mobile
dart run tool/configure_local_network.dart --allow-insecure-local-http
```

`android/`와 `ios/` 중 하나만 있다면 불완전한 플랫폼 상태다. 기존 파일을 삭제하거나 `flutter create .`로 덮어쓰지 말고 팀 저장소에서 두 디렉터리를 함께 복구한다. Git Bash bootstrap이 팀 Windows 환경에서 동작하지 않으면 macOS/Linux의 같은 Flutter Stable 버전으로 한 번 생성해 검토한 뒤 팀 저장소에 커밋한다.

### 5.4 의존성·분석·테스트

PowerShell에서 실행한다.

```powershell
Set-Location C:\workspace\snap\mobile
flutter pub get
flutter test
flutter analyze
```

세 명령이 모두 성공한 뒤 실기기로 진행한다. 팀원마다 `flutter --version` 결과가 다르면 플랫폼 생성물이 바뀔 수 있으므로 사용한 Stable 버전을 기록한다.

## 6. Android 실기기 연결

1. 휴대폰 설정에서 개발자 옵션을 활성화한다.
2. 개발자 옵션에서 USB 디버깅을 켠다.
3. 데이터 전송 USB 케이블로 Windows PC와 연결한다.
4. 휴대폰의 `이 컴퓨터에서 USB 디버깅을 허용` 창을 승인한다.
5. Windows가 기기를 찾지 못하면 제조사 OEM USB 드라이버를 설치한다.

PowerShell에서 확인한다.

```powershell
adb devices
flutter devices
```

`unauthorized`이면 휴대폰 화면의 승인 창을 확인한다. `flutter devices`에 Android Device ID가 표시돼야 한다.

Android 11 이상에서는 무선 디버깅도 가능하지만, 처음 구축할 때는 앱 설치 문제와 Wi-Fi 통신 문제를 분리하기 쉬운 USB 디버깅을 권장한다.

## 7. Raspberry Pi Gateway 환경 구축

이 절부터는 **실제 Pi 터미널**에서 실행한다.

### 7.1 Pi IP와 Python 확인

```bash
hostname
hostname -I
ip -4 route
python3 --version
```

`hostname -I`의 Wi-Fi IPv4를 `PI_IP`로 사용한다. 여러 주소가 보이면 휴대폰과 같은 공유기의 기본 경로에 연결된 주소를 선택한다.

### 7.2 소스와 Python 가상환경

```bash
sudo apt update
sudo apt install -y git curl iproute2 tcpdump python3 python3-venv python3-pip
```

Pi에 소스가 없다면 팀 Git URL을 입력해 받는다.

```bash
read -rp "팀 SNAP Git 저장소 URL: " snap_repo_url
git clone "$snap_repo_url" "$HOME/snap"
```

Gateway 의존성을 설치한다.

```bash
cd "$HOME/snap/pi-bridge"
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### 7.3 Arduino 장치와 UART 안전 확인

```bash
ls -l /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
ls -l /dev/serial/by-id/ 2>/dev/null
groups
```

기본 연결은 Mega USB Serial `/dev/ttyACM0`·`115200`, 로봇 GPIO UART `/dev/serial0`·`9600`이다. 실제 장치 이름이 다르면 Gateway 실행 환경변수를 바꾼다.

`dialout` 그룹이 없다면 한 번만 추가한 뒤 로그아웃하고 다시 접속한다.

```bash
sudo usermod -aG dialout "$USER"
```

로봇 Arduino 연결 방식은 다음 중 팀에서 확정한 **한 가지**를 사용한다.

- USB Serial: Arduino를 Pi USB에 연결하고 `/dev/serial/by-id/...`의 안정적인 장치 경로를 `SNAP_ROBOT_PORT`에 넣는다. 환경에 따라 `/dev/ttyACM1` 또는 `/dev/ttyUSB0`처럼 보일 수도 있다.
- GPIO UART: `sudo raspi-config`에서 Serial login shell은 끄고 Serial hardware는 켠 뒤 재부팅한다. Pi 물리 핀 8(GPIO14/TXD)은 Arduino RX로, Pi 물리 핀 10(GPIO15/RXD)은 Arduino TX에서 **레벨 시프터를 거쳐** 연결하고, Pi GND와 Arduino GND를 공통으로 연결한다. TX와 RX는 서로 교차한다.

Raspberry Pi GPIO UART는 **3.3V 전용**이다. 5V TTL 출력을 Pi RX에 직접 연결하지 말고 검증된 양방향 레벨 시프터 등 팀이 검토한 회로를 사용한다. Arduino 보드별 Serial 핀도 다르므로 팀 배선도와 보드 핀맵이 확정되지 않았다면 전원과 모터를 연결하거나 실제 Arduino 모드를 실행하지 않는다. USB와 GPIO UART 중 어떤 경로를 쓰는지 먼저 정하고, 같은 Serial을 두 경로로 동시에 연결하지 않는다. 자세한 조건은 [Raspberry Pi 공식 UART 문서](https://www.raspberrypi.com/documentation/computers/configuration.html#configure-uarts)를 따른다.

## 8. 먼저 Pi Simulator로 Wi-Fi만 확인

Arduino를 움직이지 않고 앱과 Pi의 네트워크·API를 먼저 확인하는 권장 단계다. Pi 터미널에서 실행한다.

```bash
cd "$HOME/snap/pi-bridge"
source .venv/bin/activate

SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_GATEWAY_PORT=8101 \
python -m app
```

Pi의 두 번째 터미널에서 확인한다.

```bash
curl --fail --silent --show-error \
  http://127.0.0.1:8101/health \
  | python3 -m json.tool

sudo ss -ltnp 'sport = :8101'
```

정상 확인값:

```text
status: ok
mode: pi-simulator-multi-vehicle
LISTEN: 0.0.0.0:8101
```

이 단계는 **실제 Pi에서 Gateway가 실행되고 휴대폰과 통신할 준비가 됐다는 뜻**이며 Arduino·센서·모터 검증은 아니다.

## 9. 실제 Arduino 모드로 전환

8절의 Gateway를 `Ctrl+C`로 종료한다. 로봇이 실제 대기 위치에 있는지 사람이 확인하고, 바퀴나 구동부가 예기치 않게 움직여도 위험하지 않은 상태를 만든 뒤 실행한다.

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
python -m app
```

Gateway는 두 Serial 포트를 연 뒤 로봇에 `PING`과 `STATUS`를 보내 `PONG`, `STATUS:IDLE`을 확인한다. 포트나 응답 확인이 실패하면 서버를 열지 않는다.

실행 중에는 Arduino IDE Serial Monitor, `minicom`, `picocom`, 별도 Serial 스크립트를 동시에 열지 않는다. Gateway가 Serial 포트의 유일한 소유자여야 한다.

Pi의 두 번째 터미널에서 Health를 확인한다.

```bash
curl --fail --silent --show-error \
  http://127.0.0.1:8101/health \
  | python3 -m json.tool
```

실제 장비 모드의 핵심 값:

```text
mode: pi-hardware-snap-code
hardware.robot.connected: true
hardware.robot.ready: true
hardware.robot.interlocked: false
hardware.mega.connected: true
hardware.mega.verified: true
```

Mega 펌웨어는 점유 상태가 바뀔 때만 프레임을 보낼 수 있다. 첫 실제 프레임 전 `status: degraded`, `mega.verified:false`는 정상이다. 모든 주차면이 비었다고 추측해 초기값을 강제로 넣지 말고, 팀이 정한 안전한 절차로 센서 상태를 한 번 변경해 실제 프레임을 발생시킨다.

`mega.verified:true`는 Gateway 시작 후 실제 Mega 프레임을 **한 번 이상 받았다는 뜻**이다. 현재 Mega 프로토콜에는 주기적인 heartbeat가 없으므로 이후 케이블 단절이나 펌웨어 정지를 실시간으로 보증하지 않으며, `status: ok`도 Mega의 현재 liveness 증명이 아니다. 실제 주차 요청 직전 모터를 정지한 안전 상태에서 알려진 센서 변화를 유도한 뒤 원래 상태로 복구한다. 이때 `hardware.mega.lastFrameAt`이 두 번 갱신되고 REST Snapshot의 1~6번 점유 상태가 실제 현장과 일치하는지 확인한다. 하나라도 확인되지 않으면 요청하지 않는다.

통신·프로토콜 오류 뒤 `robot.interlocked:true`가 되면 추가 요청을 보내지 않는다. 모터 전원을 안전하게 차단하고 로봇을 실제 대기 위치로 복구한 뒤 Gateway를 재시작한다. `STATUS:IDLE` 응답만으로 실제 물리 위치를 증명할 수는 없다.

## 10. 휴대폰에서 Pi Wi-Fi 경로 확인

1. Android 휴대폰을 Pi와 같은 Wi-Fi에 연결한다.
2. VPN을 잠시 끈다.
3. 휴대폰 브라우저에서 실제 Pi IP를 연다.

```text
http://192.168.0.50:8101/health
```

JSON이 표시되면 휴대폰에서 Pi의 `8101/TCP`까지 도달한다. `status: degraded`여도 JSON을 받았다면 Wi-Fi 경로는 연결된 것이며, degraded 원인은 `hardware` 세부 값으로 따로 확인한다.

휴대폰 Wi-Fi IP도 기록한다. Android 설정의 현재 Wi-Fi 상세정보에서 확인하거나 Windows PowerShell에서 실행한다.

```powershell
adb shell ip -4 address show wlan0
```

## 11. Dart 읽기 전용 통신 검증

앱과 동일한 Dart 모델로 Health, Snapshot, 고객 차량 목록과 WebSocket 첫 Snapshot을 확인한다. 차량 등록이나 주차 요청은 만들지 않는다.

Windows PowerShell:

```powershell
Set-Location C:\workspace\snap\mobile
$PiIp = "192.168.0.50"
$CustomerId = "customer-team-01"

Test-NetConnection $PiIp -Port 8101

dart run tool\gateway_smoke.dart `
  "--base-url=http://${PiIp}:8101" `
  "--customer-id=${CustomerId}"
```

먼저 `TcpTestSucceeded : True`인지 확인한다. `False`이면 Dart 문제가 아니라 PC와 Pi 사이의 LAN·방화벽·Gateway 수신 주소부터 확인한다.

정상 출력:

```text
[PASS] GET /health (...)
[PASS] GET snapshot (6 slots)
[PASS] GET customer vehicles (...)
[PASS] WS /v1/events (SNAPSHOT)
Gateway 읽기 통신 검증 완료
```

이 도구는 `/health`의 `status`가 `ok`가 아니면 실패한다. 실제 Arduino 모드에서는 Mega 실제 프레임을 받은 뒤 실행한다. 네트워크 도달 여부만 먼저 볼 때는 10절의 휴대폰 브라우저 Health를 사용한다.

## 12. Android 실기기에 앱 실행

PowerShell에서 Device ID와 고객 ID를 지정한다.

```powershell
Set-Location C:\workspace\snap\mobile
flutter devices

$DeviceId = Read-Host "flutter devices에 표시된 Android Device ID"
$PiIp = "192.168.0.50"
$CustomerId = "customer-team-01"

flutter run -d $DeviceId `
  "--dart-define=PI_API_BASE_URL=http://${PiIp}:8101" `
  "--dart-define=PI_LOT_ID=demo-01" `
  "--dart-define=PI_CUSTOMER_ID=${CustomerId}"
```

중요한 주소 구분:

- `http://192.168.0.50:8101`: 휴대폰이 접속할 실제 Pi 주소
- `http://127.0.0.1:8101`: 휴대폰 자기 자신이므로 사용하지 않음
- `http://localhost:8101`: 휴대폰 자기 자신이므로 사용하지 않음
- `http://0.0.0.0:8101`: 서버 수신 설정이므로 접속 주소로 사용하지 않음
- API 주소 끝에 `/health`, `/v1` 또는 `/v1/events`를 붙이지 않음

`PI_API_BASE_URL`이나 `PI_CUSTOMER_ID`를 바꿨다면 Hot Reload만 하지 말고 실행을 종료한 뒤 새 `--dart-define` 값으로 다시 실행한다.

### 여러 고객을 시험하는 방법

휴대폰 또는 테스트 사용자마다 다른 고객 ID를 사용한다.

```text
첫 번째 휴대폰: PI_CUSTOMER_ID=customer-team-01
두 번째 휴대폰: PI_CUSTOMER_ID=customer-team-02
```

각 고객은 자기 ID로 등록한 여러 차량을 따로 조회한다. 차량번호를 앱에 입력하면 Gateway가 내부 `vehicleId`를 발급하고, 이후 차량별 예상 주차시간과 상태를 관리한다.

## 13. iPhone에서 실행할 때

Windows에서는 iOS 앱을 빌드하거나 iPhone에 설치할 수 없다. iOS 담당자는 [Flutter 공식 iOS 설정](https://docs.flutter.dev/platform-integration/ios/setup)에 따라 macOS, Xcode, 서명과 실기기를 준비한다.

macOS의 `mobile` 디렉터리에서 로컬 네트워크·개발용 HTTP 설정을 적용한다.

```bash
dart run tool/configure_local_network.dart --allow-insecure-local-http
flutter pub get
flutter devices
```

실제 Pi IP와 고객 ID를 넣어 실행한다.

```bash
flutter run -d IOS_DEVICE_ID \
  --dart-define=PI_API_BASE_URL=http://192.168.0.50:8101 \
  --dart-define=PI_LOT_ID=demo-01 \
  --dart-define=PI_CUSTOMER_ID=customer-team-ios-01
```

첫 연결에서 iOS의 로컬 네트워크 접근 창이 나타나면 허용한다. 거부했다면 iPhone 설정에서 해당 앱의 로컬 네트워크 권한을 다시 켠다.

## 14. 앱에서 연동 확인

### 네트워크·화면 확인

1. 앱의 연결 표시가 `Gateway 연결됨`으로 바뀐다.
2. 1~6번 주차면 상태가 표시된다.
3. Pi에서 다음 명령을 실행했을 때 휴대폰과의 연결이 보인다.

```bash
sudo ss -tnp 'sport = :8101'
```

휴대폰 IP만 패킷으로 확인한다. 예시 IP를 실제 `PHONE_IP`로 바꾼다.

```bash
sudo tcpdump -ni any -nn -tttt \
  'host 192.168.0.80 and tcp port 8101'
```

연결된 앱은 WebSocket을 유지하므로 `ss`에 `ESTAB`가 보이고, `tcpdump`에는 휴대폰과 Pi `8101` 사이의 패킷이 표시된다. 종료는 `Ctrl+C`다.

### 고객·차량 확인

1. 첫 고객 ID로 차량을 두 대 이상 등록한다.
2. 각 차량 카드가 독립적으로 표시되는지 확인한다.
3. 차량마다 `1시간`, `2시간`, `3시간`, `4시간 이상`을 선택할 수 있는지 확인한다.
4. Simulator에서는 차량별 주차와 출차 UI 흐름을 확인한다.
5. 실제 Arduino 모드에서는 팀 안전 확인 후 **주차 요청 한 건만** 시험한다.

실제 주차 요청 시 Pi Gateway 터미널에는 REST 요청과 다음 UART 흐름이 나타나야 한다.

```text
UART TX robot ... frame='LCPSBWB'
UART RX robot ... frame='ROUTE_ACCEPTED:7'
UART RX robot ... frame='ACTION_START:...'
UART RX robot ... frame='ACTION_DONE:...'
UART RX robot ... frame='ROUTE_DONE'
```

Gateway는 수락 길이와 모든 action 순서를 검증한 뒤에만 완료 처리한다. 실제 장비의 출차 버튼은 현재 `409` 오류 확인 외에는 사용하지 않는다.

## 15. 오류 해결

| 증상 | 주된 원인 | 확인과 해결 |
|---|---|---|
| `flutter` 명령을 찾을 수 없음 | SDK PATH 미설정 | Flutter SDK `bin`을 PATH에 추가 후 PowerShell 재시작 |
| `flutter doctor` Android 오류 | SDK/Command-line Tools/라이선스 누락 | Android Studio SDK Manager와 `flutter doctor --android-licenses` |
| `flutter devices`에 휴대폰 없음 | USB 디버깅·승인·드라이버 문제 | 휴대폰 승인 창, 데이터 케이블, OEM 드라이버 확인 |
| bootstrap이 기존 파일 때문에 중단 | `android/` 또는 `ios/`가 이미 있음 | 삭제하지 말고 두 러너의 Git 상태 확인 후 설정 도구만 실행 |
| Android cleartext 오류 | 개발용 HTTP 설정 미적용 | `configure_local_network.dart --allow-insecure-local-http` 후 재빌드 |
| 휴대폰 브라우저 Health도 실패 | Pi IP·바인딩·Wi-Fi 문제 | `hostname -I`, `0.0.0.0:8101`, 같은 Wi-Fi, 단말 격리 확인 |
| 브라우저 Health 성공, 앱 실패 | 잘못된 compile-time URL 또는 플랫폼 설정 | `PI_API_BASE_URL`, cleartext 설정 후 앱 완전 재실행 |
| `Connection refused` | Pi의 해당 포트에 서버가 없음 | Gateway 프로세스와 `ss -ltnp` 확인 |
| 연결 시간이 초과됨 | IP 변경, VPN, 게스트망, 방화벽 | Pi 현재 IP와 공유기 경로 확인 |
| Snapshot `Not Found` | Base URL 뒤에 잘못된 경로 추가 또는 구버전 Gateway | Base URL을 `http://PI_IP:8101`로 수정하고 최신 소스 실행 |
| REST는 되지만 실시간 갱신 안 됨 | WebSocket 경로 또는 연결 단절 | Pi `/v1/events` 로그와 앱 재연결 상태 확인 |
| Smoke Test만 health 오류 | Hardware Health가 아직 degraded | Mega 실제 프레임과 `/health` 세부 값 확인 |
| 실제 출차 요청이 `409` | 출차 경로 미지원 | 현재 정상 제한이며 Simulator에서만 출차 시험 |
| `robot.interlocked:true` | Serial·프로토콜 작업 오류 | 추가 명령 금지, 물리 복구 후 Gateway 재시작 |
| Pi 재부팅 후 앱 연결 실패 | DHCP로 Pi IP 변경 | `hostname -I` 재확인 후 앱을 새 URL로 다시 실행 |

### 가장 빠른 분리 순서

1. Pi에서 `curl http://127.0.0.1:8101/health`
2. 휴대폰 브라우저에서 `http://PI_IP:8101/health`
3. Windows에서 `gateway_smoke.dart`
4. `flutter run`으로 앱 실행
5. Pi에서 `ss`와 `tcpdump` 확인

- 1 실패: Gateway 설치·실행 문제
- 1 성공, 2 실패: Wi-Fi·Pi 바인딩·방화벽 문제
- 2 성공, 3 실패: Gateway Health 또는 REST·WebSocket 계약 문제
- 3 성공, 4 실패: Flutter 플랫폼·빌드 설정 문제
- 4 성공, 5에 패킷 표시: 앱 ↔ Pi Wi-Fi 연결 정상

## 16. 개발용 HTTP와 배포 전 보안

현재 팀 개발환경은 `http://`와 `ws://`를 사용한다. `--allow-insecure-local-http`는 다음 개발 예외를 적용한다.

- Android: Debug Manifest에서만 cleartext HTTP 허용
- iOS: `Info.plist`에 개발용 ATS 예외 추가

iOS ATS 예외는 Release에도 영향을 줄 수 있으므로 배포 전에 반드시 제거한다.

```bash
dart run tool/configure_local_network.dart --remove-insecure-local-http
```

운영 배포 전에는 다음 작업이 필요하다.

- Gateway를 HTTPS/WSS로 전환
- 사용자 로그인·인증 토큰·고객 권한 검사 추가
- Gateway 주소를 앱 설정·서비스 검색 또는 고정 도메인으로 제공
- 차량·주차 세션을 영속 저장하고 재시작 시 복구
- 물리 비상 정지와 부팅 상태 대조 검증

현재 Gateway는 인증·TLS가 없는 개발 서버이며 고객·차량·주차 세션은 메모리에만 있다. 신뢰하는 사설망에서만 사용하고 인터넷에 노출하지 않는다.

## 17. IP 변경과 고객 ID 주의

현재 `PI_API_BASE_URL`과 `PI_CUSTOMER_ID`는 compile-time 설정이다.

- Pi IP가 바뀌면 새 주소로 앱을 다시 실행하거나 다시 빌드해야 한다.
- 공유기 DHCP 예약으로 Pi IP를 고정하면 팀 실습이 안정적이다.
- 여러 사람이 같은 `PI_CUSTOMER_ID`를 사용하면 같은 고객 차량 목록을 보게 된다.
- 고객 ID는 비밀번호나 인증 토큰이 아니다.
- Gateway를 재시작하면 현재 차량·주차 세션이 사라질 수 있다.

정식 제품에서는 고객 ID를 빌드 명령에 고정하지 않고 로그인 결과에서 받아야 한다.

## 18. 최종 체크리스트

- [ ] Windows에서 `flutter doctor -v`의 Android 항목이 정상이다.
- [ ] `android/`, `ios/` 러너와 개발용 로컬 HTTP 설정을 준비했다.
- [ ] Android 실기기가 `flutter devices`에 표시된다.
- [ ] Pi, 휴대폰, Windows 개발 PC가 서로 접근 가능한 같은 LAN에 있다.
- [ ] `hostname -I`로 Pi 실제 IP를 확인했다.
- [ ] Pi Gateway가 `0.0.0.0:8101`에서 실행 중이다.
- [ ] 휴대폰 브라우저에서 Pi `/health` JSON을 받는다.
- [ ] Windows의 `Test-NetConnection` 결과가 `TcpTestSucceeded : True`다.
- [ ] `gateway_smoke.dart`가 REST·WebSocket 읽기 검증을 통과한다.
- [ ] 앱을 Pi 실제 IP와 고객별 고유 ID로 실행했다.
- [ ] 앱 연결 표시와 1~6번 주차면 Snapshot이 보인다.
- [ ] Pi `ss`와 `tcpdump`에 휴대폰 `8101/TCP` 연결이 보인다.
- [ ] 고객별 여러 차량과 차량별 예상 주차시간 선택을 확인했다.
- [ ] Simulator 결과와 실제 Arduino 결과를 구분했다.
- [ ] 실제 장비에서는 출차가 아직 지원되지 않음을 팀이 확인했다.

위 항목을 통과하면 **Flutter 실기기 고객 앱 ↔ 실제 Raspberry Pi Gateway의 Wi-Fi 연동**을 확인한 것이다. 실제 차량을 올린 무인 운영 승인을 의미하지는 않는다.
