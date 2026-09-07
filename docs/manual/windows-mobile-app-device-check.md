# Windows 팀원을 위한 Galaxy·iPhone 실기기 확인

이 문서는 앱 개발 경험이 없는 Windows 10·11 팀원이 **실제 Raspberry Pi에서 실행 중인 S.N.A.P Gateway**에 Galaxy 또는 iPhone 앱을 연결해 화면과 실시간 상태를 확인하는 절차다. QEMU나 PC의 `localhost`는 사용하지 않는다.

Flutter, APK, TestFlight 같은 용어가 낯설다면 [처음 배우는 모바일 앱 기술](../mobile-flutter-beginner-guide.md)을 먼저 읽는다.

> 이 문서에서 `PI_IP`는 **Raspberry Pi의 Wi-Fi 또는 유선 LAN 주소**를 뜻한다. 휴대폰 IP나 Windows PC IP가 아니다. 실제 숫자 주소를 찾은 뒤 `PI_IP`라고 적힌 곳에 대신 입력한다.

## 1. 내 상황에 맞는 방법

| 휴대폰과 준비물 | 따라갈 절 | 난이도 |
|---|---:|---|
| Galaxy와 팀이 제공한 APK가 있다 | 2 → 3 → 4 → 7 | 가장 쉬움 |
| Galaxy에 USB로 반복 설치해야 한다 | 2 → 3 → 5 → 7 | 보조 방법 |
| iPhone과 TestFlight 초대가 있다 | 2 → 3 → 6 → 7 | 가장 쉬움 |
| iPhone인데 TestFlight 초대가 없다 | 2 → 3 → 6.2 | Mac 담당자 필요 |
| 직접 앱을 빌드하거나 Pi Gateway를 설치해야 한다 | 9절과 기존 개발자용 매뉴얼 | 개발 담당자용 |

가장 중요한 차이는 다음과 같다.

- Galaxy에서 APK 파일을 직접 설치할 때는 Flutter, Android Studio, 개발자 옵션, USB 디버깅이 필요 없다.
- Windows에서는 iPhone용 Flutter 앱을 빌드하거나 서명해 직접 설치할 수 없다. iPhone 팀원은 TestFlight 초대 또는 Mac·Xcode 담당자의 설치 지원이 필요하다.
- 소스 코드만 내려받아서는 휴대폰에 앱이 생기지 않는다. Galaxy는 APK 파일, iPhone은 TestFlight 초대나 Mac에서 서명한 설치가 먼저 준비돼야 한다.

## 2. 시작 전에 준비할 것

다음을 준비한다.

- Galaxy 또는 iPhone
- 실제 Raspberry Pi와 그 터미널을 볼 수 있는 사람
- Raspberry Pi와 휴대폰이 함께 접속할 신뢰할 수 있는 Wi-Fi
- Galaxy: 팀 공식 경로로 받은 APK와 SHA-256 해시
- iPhone: 팀이 보낸 TestFlight 초대 링크, 또는 설치를 도와줄 Mac 담당자

휴대폰과 Pi를 같은 일반 Wi-Fi에 연결하고 VPN은 잠시 끈다. `게스트`, `Guest`, `IoT 격리`처럼 기기끼리 통신하지 못하게 하는 Wi-Fi는 사용하지 않는다. 같은 Wi-Fi 이름에 연결했더라도 공유기의 AP·Client Isolation 설정이 켜져 있으면 통신할 수 없다.

현재 앱은 Gateway 주소를 빌드할 때 고정한다. 앱의 `설정` 화면에서는 주소를 확인하고 복사할 수만 있고 수정할 수는 없다.

- 여러 휴대폰이 **같은 Pi**를 사용한다면 휴대폰마다 IP가 달라도 같은 앱 배포본을 사용할 수 있다.
- 팀원마다 **다른 Pi 또는 다른 네트워크**를 사용한다면 3절에서 찾은 각자의 `PI_IP`에 맞는 앱 배포본이 필요하다.
- 배포본의 주소가 다르면 `PI_IP`를 배포 담당자에게 보내고 새 APK 또는 iPhone 빌드를 요청한다.

## 3. 내 Raspberry Pi 주소 찾기

### 3.1 Pi 터미널에서 찾기

Pi에 모니터·키보드를 연결했거나 SSH 터미널이 이미 열려 있다면 다음 명령을 실행한다.

```bash
hostname -I
```

표시된 값 중 현재 공유기에 연결된 IPv4 주소를 적어 둔다. 일반적인 사설 IPv4는 `192.168.x.x`, `10.x.x.x`, 또는 `172.16.x.x`부터 `172.31.x.x` 형태다. `127.0.0.1`, `0.0.0.0`, `localhost`, `::1`은 휴대폰에서 사용할 Pi 주소가 아니다.

주소가 여러 개라 어느 것인지 모르겠다면 Wi-Fi는 첫 번째 명령, LAN 케이블은 두 번째 명령으로 다시 확인한다.

```bash
ip -4 -brief address show wlan0
ip -4 -brief address show eth0
```

`UP`인 줄에 표시된 `주소/숫자` 중 `/` 앞부분만 `PI_IP`로 사용한다. Pi 환경에 `wlan0`이나 `eth0`이라는 이름이 없으면 `ip -4 -brief address`로 전체 인터페이스를 보고 현재 공유기에 연결된 `UP` 항목을 찾는다. 활성 IPv4가 하나도 없으면 Pi 담당자에게 네트워크 연결을 요청한다.

Pi가 다른 Wi-Fi로 이동하거나 공유기에서 주소를 새로 받으면 `PI_IP`가 바뀔 수 있다. 시험을 시작할 때 다시 확인하고, 반복 배포가 필요하면 공유기 담당자가 Pi에 DHCP 예약 주소를 배정한다. 충돌 위험이 있으므로 사용 중인지 확인하지 않은 숫자를 Pi의 고정 주소로 임의 지정하지 않는다.

Pi 자체에서 Gateway가 실행 중인지도 확인한다.

```bash
curl http://127.0.0.1:8101/health
```

JSON이 보이면 Pi 내부에서 Gateway까지 연결된 것이다. `"status":"ok"`면 앱 확인을 계속할 수 있다. `"status":"degraded"`면 네트워크는 연결됐지만 장비 준비 상태가 정상이 아니므로 차량 등록·주차·출차를 누르지 말고 전체 JSON을 Pi 담당자에게 보낸다. `Connection refused`가 나오거나 응답이 없으면 휴대폰 설치보다 먼저 Pi 담당자가 Gateway를 실행해야 한다.

### 3.2 Windows에서 주소와 포트 확인하기

Windows 시작 메뉴에서 `PowerShell`을 열고 실행한다.

```powershell
$PI_IP = Read-Host "Raspberry Pi IP"
Test-NetConnection -ComputerName $PI_IP -Port 8101
Invoke-RestMethod -Uri "http://${PI_IP}:8101/health"
```

첫 명령이 주소를 물으면 3.1절에서 찾은 숫자만 입력한다. 결과의 `TcpTestSucceeded`가 `True`이고 Health JSON이 출력되면 Windows에서 Gateway까지의 연결은 성공이다. `status`가 `ok`면 계속하고, `degraded`면 변경 버튼을 누르지 말고 전체 결과를 Pi 담당자에게 보낸다.

Pi 터미널을 볼 수 없다면 Pi 담당자에게 `hostname -I` 결과를 요청하는 방법이 가장 확실하다. Pi의 호스트 이름을 알고 있고 같은 네트워크에서 이름 찾기가 지원될 때만 다음 명령을 보조로 사용할 수 있다.

```powershell
Resolve-DnsName raspberrypi.local
```

호스트 이름을 바꿨거나 공유기가 `.local` 이름 찾기를 막으면 이 명령은 실패할 수 있다. 추측한 주소로 앱을 빌드하지 않는다.

### 3.3 휴대폰 브라우저에서 마지막 확인하기

Galaxy는 Chrome 또는 Samsung Internet, iPhone은 Safari를 열고 주소창에 다음 형식으로 입력한다. `PI_IP` 글자를 그대로 쓰지 말고 앞에서 적어 둔 실제 숫자로 바꾼다.

```text
http://PI_IP:8101/health
```

JSON 글자가 보이면 휴대폰에서 실제 Pi까지의 네트워크 경로가 열린 것이다. 이 페이지가 열리지 않으면 앱도 연결되지 않으므로 8절의 네트워크 항목부터 해결한다.

## 4. Galaxy에 APK 직접 설치하기 — 권장

### 4.1 받은 파일이 맞는지 확인하기

배포 담당자에게 다음 두 가지를 함께 받는다.

1. APK 파일
2. 그 파일의 SHA-256 해시

이 문서나 메신저의 오래된 해시를 재사용하지 않는다. APK를 다시 빌드하면 해시도 바뀐다. Windows의 `다운로드` 폴더에 `app-debug.apk`를 받았다고 가정하면 PowerShell에서 다음을 실행한다.

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\app-debug.apk" -Algorithm SHA256
```

출력된 `Hash`가 배포 담당자가 **같은 파일과 함께 보낸 값**과 완전히 같아야 한다. 다르거나 해시를 받지 못했다면 설치하지 말고 파일을 다시 요청한다.

### 4.2 APK를 Galaxy에 넣기

둘 중 편한 방법 하나를 사용한다.

- Galaxy에서 팀의 승인된 다운로드 링크를 직접 열어 APK를 받는다.
- USB 데이터 케이블로 Galaxy와 Windows를 연결한다. Galaxy 알림에서 USB 용도를 `파일 전송/Android Auto`로 고른 뒤 Windows 파일 탐색기에서 APK를 `내장 저장공간\Download`로 복사한다.

충전만 가능한 케이블로는 파일을 복사할 수 없다.

### 4.3 설치하기

1. Galaxy에서 `내 파일 → 다운로드`를 연다.
2. 받은 APK를 누른다.
3. 설치가 허용되면 `설치 → 열기`를 누른다.
4. 홈 화면이나 앱 목록에서 Android 표시명인 `snap_mobile`을 연다.

`보안을 위해 이 출처의 알 수 없는 앱을 설치할 수 없습니다`와 비슷한 메시지가 나오면 다음과 같이 한다. Galaxy와 One UI 버전에 따라 메뉴 문구가 조금 다를 수 있으므로 설정 검색을 사용하는 것이 가장 빠르다.

1. `설정` 상단 검색에서 `출처를 알 수 없는 앱 설치`를 찾는다.
2. APK를 연 앱이 `내 파일`이면 **내 파일만**, 브라우저에서 바로 열었다면 **그 브라우저만** 선택한다.
3. `이 출처 허용`을 잠시 켜고 APK를 다시 연다.
4. One UI의 `자동 차단` 또는 `보안 위험 자동 차단`이 설치를 막는 경우에만 `설정 → 보안 및 개인정보 보호`에서 해당 기능을 잠시 끈다.
5. 설치가 끝나면 `이 출처 허용`을 다시 끄고 자동 차단도 다시 켠다.

Play Protect 전체를 끄거나 출처를 모르는 APK를 설치하지 않는다. Samsung도 외부 APK 설치가 보안 위험을 높일 수 있다고 안내한다.

## 5. Galaxy에 USB로 설치하기 — 필요할 때만

APK 직접 설치가 잘 되면 이 절은 건너뛴다. USB 설치를 반복해야 하는 팀원만 사용한다. Android Studio와 Flutter 전체를 설치할 필요는 없고 Android 공식 Platform-Tools만 있으면 된다.

### 5.1 Windows 준비

1. [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)에서 Windows용 ZIP을 받는다.
2. 압축을 풀어 `C:\platform-tools` 폴더가 되도록 한다.
3. Galaxy가 나중에 전혀 인식되지 않을 때만 [Samsung Android USB Driver](https://developer.samsung.com/android-usb-driver)를 설치한다.

### 5.2 Galaxy에서 USB 디버깅 켜기

`빌드번호`는 `휴대전화 정보` 첫 화면에 바로 보이지 않는 것이 정상이다. 다음처럼 한 단계 더 들어간다.

1. `설정 → 휴대전화 정보 → 소프트웨어 정보 → 빌드번호`로 이동한다.
2. **빌드번호 줄을 7번** 연속 누른다.
3. 요청되면 휴대전화 잠금 PIN을 입력한다.
4. 설정 첫 화면으로 돌아가 맨 아래의 `개발자 옵션`을 연다.
5. `USB 디버깅`을 켠다.

찾기 어려우면 설정 검색에 `빌드번호` 또는 `개발자 옵션`을 입력한다. 회사·학교에서 관리하는 기기, 자녀 보호가 적용된 기기에서는 이 메뉴가 차단될 수 있다. 그 경우 보안 정책을 우회하지 말고 4절의 APK 직접 설치를 사용한다.

One UI의 자동 차단 기능은 USB 명령도 막을 수 있다. ADB 연결이 계속 실패할 때만 테스트하는 동안 잠시 끄고, 끝난 뒤 다시 켠다.

### 5.3 Windows에서 연결과 설치 확인하기

1. 데이터 전송이 되는 USB 케이블로 Galaxy를 연결한다.
2. Galaxy 잠금을 풀어 둔다.
3. PowerShell에서 다음을 실행한다.

```powershell
Set-Location C:\platform-tools
.\adb.exe devices
```

Galaxy에 `이 컴퓨터에서 USB 디버깅을 허용하시겠습니까?`가 나오면 PC 화면의 RSA 지문과 팝업을 확인한 뒤 허용한다. 다시 `devices`를 실행했을 때 다음처럼 기기 번호 뒤에 `device`가 보여야 한다.

```text
List of devices attached
RXXXXXXXXXX    device
```

APK가 Windows 다운로드 폴더에 있으면 설치하고 실행한다.

```powershell
.\adb.exe -d install -r "$env:USERPROFILE\Downloads\app-debug.apk"
.\adb.exe -d shell am start -n dev.snap.valet.snap_mobile/.MainActivity
```

설치 명령 끝에 `Success`가 나오면 정상이다. `-r`은 같은 서명의 기존 앱을 앱 데이터와 함께 갱신한다.

확인을 마치면 Galaxy에서 USB 디버깅을 끈다. 필요하면 `개발자 옵션 → USB 디버깅 권한 승인 취소`로 이 PC에 준 신뢰도 제거한다.

## 6. iPhone에 설치하기

Windows 10·11에서는 Flutter iOS 앱을 빌드하거나 iPhone에 개발용 앱을 서명해 설치할 수 없다. Android용 APK, 저장소의 `Runner.app`, 파일 이름만 바꾼 IPA는 iPhone에 설치할 수 없다.

### 6.1 TestFlight 초대가 있을 때 — 권장

1. iPhone의 App Store에서 Apple의 `TestFlight`를 설치한다.
2. 배포 담당자가 보낸 초대 이메일 또는 공개 링크를 **iPhone에서** 연다.
3. `TestFlight에서 보기 → 수락 → 설치`를 누른다.
4. 설치된 iOS 표시명 `Snap Mobile`을 연다.
5. 처음 실행할 때 `로컬 네트워크의 기기를 찾고 연결`하겠다는 창이 나오면 `허용`한다.

TestFlight 설치에는 개발자 모드나 Windows USB 연결이 필요 없다. 로컬 네트워크를 실수로 거부했다면 다음 위치에서 다시 켠다.

```text
설정 → 개인정보 보호 및 보안 → 로컬 네트워크 → Snap Mobile 켜기
```

TestFlight 빌드는 최대 90일 동안 시험할 수 있다. 만료됐다는 메시지가 나오면 배포 담당자에게 새 빌드를 요청한다.

### 6.2 TestFlight 초대가 없을 때

현재 팀에서 TestFlight나 관리형 iPhone 배포를 준비하지 않았다면 Windows PC와 소스 코드만으로 설치를 진행하지 않는다. 다음 중 하나를 배포 담당자에게 요청한다.

- TestFlight 빌드와 초대 링크 준비
- Mac·Xcode가 있는 담당자가 iPhone을 직접 연결해 서명하고 설치

Mac에서 직접 개발용으로 설치할 때만 iPhone의 `설정 → 개인정보 보호 및 보안 → 개발자 모드`를 켜고 재시작해야 할 수 있다. 이 과정은 Mac 담당자와 함께 진행한다. 일반 TestFlight 설치에는 개발자 모드를 켜지 않는다.

서드파티 사이드로딩 프로그램이나 출처를 모르는 프로파일은 이 팀 매뉴얼의 지원 범위가 아니다.

## 7. 앱이 정상인지 확인하기

먼저 3.3절의 휴대폰 브라우저 Health 확인이 성공했는지 확인한다. 그다음 앱을 열고 아래 항목을 순서대로 본다.

1. 화면에 `주차하기`가 보인다.
2. 제목 아래에 `S.N.A.P · demo-01`이 보인다.
3. `주차면 현황`에 1번부터 6번까지의 주차면이 보인다.
4. 아래 메뉴에서 `설정`을 연다.
5. 표시된 Endpoint가 `http://PI_IP:8101` 형식이며, 숫자 부분이 3절에서 찾은 주소와 정확히 같다.
6. `Gateway`는 `정상`, `실시간 이벤트`는 `연결됨`으로 표시된다.
7. 30초 이상 화면을 열어 두어도 `재연결 대기`로 바뀌지 않는다.

Endpoint가 다르면 앱에서 직접 바꿀 수 없다. 현재 배포본이 다른 Pi용으로 빌드된 것이므로 올바른 `PI_IP`를 배포 담당자에게 보내고 새 배포본을 요청한다.

기본 확인은 여기까지이며 읽기 전용이다. 현재 Pi가 `pi-simulator-multi-vehicle` 모드라면 **실제 Pi 보드에서 앱↔Gateway REST·WebSocket 통신**을 확인한 것이지 Arduino, 센서, 모터의 실제 동작을 확인한 것은 아니다.

차량 등록, 주차 요청, 출차 요청은 공유 상태를 바꾼다. 배포 담당자가 변경 테스트 시간을 정한 경우에만 한 명씩 실행한다. 같은 `PI_CUSTOMER_ID`로 만든 앱을 여러 명이 사용하면 서로 같은 차량 목록과 상태가 보일 수 있다.

## 8. 잘 안 될 때

| 증상 | 확인할 것 |
|---|---|
| `hostname -I`에 IPv4가 없음 | Pi의 Wi-Fi 또는 LAN 연결을 Pi 담당자에게 요청한다. |
| Pi에서는 Health가 되지만 Windows·휴대폰에서는 안 됨 | 같은 일반 Wi-Fi인지, VPN·게스트망·AP Isolation이 꺼졌는지, Gateway가 외부 접속 가능한 `0.0.0.0:8101`에서 실행되는지 확인한다. |
| Windows의 `TcpTestSucceeded`가 `False` | IP 오타, Pi 주소 변경, Gateway 중지, 공유기 격리 또는 Pi 방화벽 문제다. 앱 설치보다 네트워크를 먼저 해결한다. |
| 휴대폰 Health는 되지만 앱만 연결되지 않음 | 앱 `설정`의 Endpoint가 같은 `PI_IP`인지 확인한다. iPhone은 로컬 네트워크 권한과 해당 IP용 빌드인지도 확인한다. |
| Galaxy에서 `빌드번호`가 안 보임 | `휴대전화 정보 → 소프트웨어 정보`까지 들어간다. APK 직접 설치만 할 때는 개발자 옵션 자체가 필요 없다. |
| `adb devices` 목록이 비어 있음 | 휴대폰 잠금, 데이터 케이블, USB 파일 전송 모드, Samsung 드라이버, 자동 차단을 확인한다. |
| `adb devices`에 `unauthorized`가 보임 | Galaxy 잠금을 풀고 RSA 허용 팝업을 승인한 뒤 다시 실행한다. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 이전 앱과 새 APK의 서명이 다르다. 기존 앱 삭제 시 로컬 앱 데이터도 지워지므로 먼저 배포 담당자에게 확인한다. |
| Galaxy에서 `앱이 설치되지 않았습니다` | APK 해시, 남은 저장공간, 자동 차단, 기존 앱 서명 충돌을 확인한다. Play Protect 전체를 끄지 않는다. |
| iPhone에서 초대 링크가 안 열림 | iPhone에 TestFlight가 설치됐는지, 이메일 초대라면 초대받은 Apple Account가 맞는지, 빌드가 만료되지 않았는지 담당자에게 확인한다. |
| 연결됐다가 계속 끊김 | 휴대폰의 Wi-Fi 절전·네트워크 전환, VPN, Pi Gateway 로그와 `/health` 응답을 확인한다. |

문제를 보고할 때는 아래 내용을 복사해 채운 뒤 홈과 설정 화면 캡처를 함께 보낸다. 비밀번호나 개인 토큰은 적지 않는다.

```text
휴대폰: Galaxy 또는 iPhone / 모델명
OS 버전:
앱을 받은 방법: APK 직접 / ADB / TestFlight / Mac 직접 설치
PI_IP:
휴대폰 브라우저 /health: 성공 / 실패
앱 설정의 Endpoint:
Gateway 표시: 정상 / 연결 확인 중
실시간 이벤트 표시: 연결됨 / 재연결 대기
발생 시각:
화면 오류 문구:
```

## 9. 배포 담당자만 확인할 내용

일반 앱 확인 팀원은 이 절을 실행하지 않는다.

### 9.1 팀원에게 받을 정보

- 3절에서 확인한 `PI_IP`
- Android 또는 iPhone 구분
- 팀원별로 분리할 `PI_CUSTOMER_ID`

앱 설정 화면에서 Gateway 주소를 편집할 수 없는 현재 구조에서는 팀원별 Pi 주소가 다르면 그 주소에 맞춰 다시 빌드해야 한다. APK·TestFlight 링크를 보낼 때 대상 `PI_IP`, 앱 버전, 고객 ID도 함께 적는다.

### 9.2 Android 내부 테스트 APK 만들기

Flutter 개발환경이 준비된 Windows PowerShell에서 `mobile` 폴더로 이동한 뒤 실행한다.

```powershell
$PI_IP = Read-Host "Raspberry Pi IP"
$CUSTOMER_ID = Read-Host "Tester customer ID"

flutter build apk --debug `
  --dart-define="PI_API_BASE_URL=http://${PI_IP}:8101" `
  --dart-define="PI_LOT_ID=demo-01" `
  --dart-define="PI_CUSTOMER_ID=${CUSTOMER_ID}"

Get-FileHash ".\build\app\outputs\flutter-apk\app-debug.apk" -Algorithm SHA256
```

현재 Android의 평문 HTTP 허용은 Debug 빌드에만 적용돼 있다. HTTP Pi에 연결할 내부 시험에서는 임의의 Release APK를 보내지 않는다. APK와 방금 계산한 SHA-256, 대상 `PI_IP`를 승인된 팀 공유 경로로 함께 전달한다.

### 9.3 iPhone 빌드 준비

iOS 빌드·서명·업로드에는 Mac, Xcode와 적절한 Apple Developer 설정이 필요하다. 배포 담당자는 다음을 모두 확인한다.

- 앱의 `PI_API_BASE_URL`이 팀원이 보낸 `PI_IP`를 가리킨다.
- `mobile/ios/Runner/Info.plist`의 `NSExceptionDomains` 아래 IP 키도 같은 `PI_IP`로 바꾼다. 주소가 다르면 Dart 설정만 바꿔서는 연결되지 않는다.
- Mac 터미널에서 `mobile` 폴더로 이동한 뒤 `plutil -lint ios/Runner/Info.plist`를 실행해 수정한 plist 문법이 정상인지 확인한다.
- 일반 Windows 팀원에게는 TestFlight 초대를 보낸다. 외부 테스터용 첫 빌드는 TestFlight 심사가 필요할 수 있다.
- 서로 다른 Pi 주소용 빌드는 각각 새 build number와 별도 tester group을 사용하고, 각 그룹에는 해당 `PI_IP`용 빌드만 배정한다.
- 외부 심사 환경에서는 사설망의 Pi에 접속할 수 없으므로 심사 메모에 현장 전용 LAN 앱이라는 점과 제한된 HTTP 예외의 사유를 설명한다.
- 소수 기기를 즉시 확인해야 하고 TestFlight가 아직 없다면 Mac·Xcode 담당자가 등록한 iPhone에 직접 설치한다.

상세 빌드와 Gateway 운영 절차는 [Flutter 고객 앱과 실제 Raspberry Pi Wi-Fi 연동 매뉴얼](raspberry-pi-flutter-app-wifi.md)을 따른다.

## 10. 보안과 시험 범위

- Gateway `8101` 포트를 인터넷에 공개하거나 공유기 포트포워딩을 설정하지 않는다.
- 이 프로토타입은 인증과 TLS가 없는 개발용 통신을 사용하므로 신뢰할 수 있는 사설망과 시험 데이터만 사용한다.
- 실제 차량, 센서, 모터를 움직이는 시험은 장비 담당자의 안전 절차와 명시적 승인 없이는 진행하지 않는다.
- 설치가 끝난 Galaxy는 알 수 없는 출처 허용, 자동 차단 해제, USB 디버깅을 원래대로 되돌린다.

## 공식 참고 문서

- [Android: 하드웨어 기기에서 앱 실행](https://developer.android.com/studio/run/device)
- [Android: ADB 사용법](https://developer.android.com/tools/adb)
- [Android: Galaxy의 개발자 옵션 경로](https://developer.android.com/studio/debug/dev-options?hl=ko)
- [Samsung: 알 수 없는 출처의 앱 설치](https://www.samsung.com/us/support/troubleshoot/TSG10001913/)
- [Samsung: Auto Blocker](https://www.samsung.com/us/support/answer/ANS10003636/)
- [Flutter: 지원 플랫폼별 개발환경](https://docs.flutter.dev/platform-integration)
- [Flutter: iOS 개발환경 설정](https://docs.flutter.dev/platform-integration/ios/setup)
- [Apple: TestFlight 개요](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Apple: 로컬 네트워크 접근 제어](https://support.apple.com/en-us/102229)
