# S.N.A.P Flutter 모바일 클라이언트

한 Flutter 코드베이스로 iOS와 Android를 지원하는 S.N.A.P 고객용 앱이다. 앱은 Raspberry Pi의 FastAPI Gateway에만 연결하며 Arduino, 센서, 모터를 직접 제어하지 않는다.

Flutter, Dart, Android, iOS의 관계와 Flutter의 기능·역할이 낯선 팀원은 [처음 배우는 모바일 앱 기술](../docs/mobile-flutter-beginner-guide.md)을 먼저 읽는다.

## 구현 범위

- `GET /health`, `GET /v1/parking-lots/{lotId}/snapshot`
- `GET/POST /v1/customers/{customerId}/vehicles` 고객별 복수 차량 조회·등록
- `POST /v1/parking-requests`, `POST /v1/retrieval-requests`
- `POST /v1/parking-requests/{requestId}/confirm`, `GET /v1/jobs/{jobId}` 클라이언트 계약
- `WS /v1/events` 실시간 현황 반영
- WebSocket 15초 ping으로 무응답 연결 감지, 단절 시 지수형 재연결, **매 재연결 전 REST Snapshot 재조회**
- POST 응답의 `snapshot`과 WebSocket 이벤트의 `snapshot`을 같은 모델로 해석
- Snapshot 이벤트마다 고객 차량 목록도 다시 조회해 차량별 상태·배정 주차면 동기화
- 전송 중인 명령이 있으면 다음 명령을 거부해 클라이언트 동시 전송 방지
- 앱이 포그라운드로 돌아오면 최신 Snapshot 복구
- 홈·차량·기록·설정 4개 탭과 연결/주차 요청/진행/완료 상태 기반 화면 전환
- 동일한 Widget 구조를 공유하는 Light/Dark 테마와 S.N.A.P 전기 블루 포인트 색상
- 스토리보드 기반의 실사형 차량·로봇 hero/top-view 자산, 6면 주차장, 이동 경로·진행 단계 UI
- 차량번호별 `1/2/3/4시간 이상` 입차 요청과 원터치 출차 요청 UI
- 로봇 작업 중 물리 요청 비활성화, 만차 안내, 다른 차량 등록 UI

Gateway가 주차면을 자동 배정하므로 앱의 주차면 도식은 선택 입력이 아니라 실시간 현황과 배정 결과를 표시한다. Light/Dark 화면의 기준은 `assets/storyboard/tesla-theme/`이고, 여기서 분리·재제작한 투명 런타임 자산은 `assets/images/`에 있다. 전체 스크린샷을 배경으로 사용하지 않으므로 차량·주차면·로봇 위치·진행률은 실제 Gateway 데이터에 맞춰 계속 갱신된다.

외부 패키지 없이 Flutter/Dart SDK만 사용한다. 저장소에 포함된 `android/`, `ios/` 러너는 Flutter 3.47.2 Stable 템플릿으로 생성했다.

현재 Gateway 계약에는 `clientRequestId`나 Idempotency-Key가 없으므로 네트워크 재시도까지 포함한 종단 간 중복 방지는 아직 제공하지 않는다.

앱을 직접 개발하지 않고 Windows 10·11에서 Galaxy 또는 iPhone 배포본만 설치·확인하려면 [Windows 팀원용 실기기 확인 매뉴얼](../docs/manual/windows-mobile-app-device-check.md)을 먼저 따른다.

## 1. 개발환경 준비

Flutter Stable SDK와 Android SDK를 설치한다. iOS 빌드는 macOS, Xcode, CocoaPods 및 서명 설정이 추가로 필요하다.

```bash
flutter --version
dart --version
flutter doctor -v
```

플랫폼 러너는 저장소에 포함되어 있으므로 의존성을 받은 뒤 바로 검증한다.

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

`tool/bootstrap_platforms.sh`는 플랫폼 디렉터리가 없는 소스 사본에서 러너를 재생성할 때만 사용한다. 현재 체크아웃처럼 `android/` 또는 `ios/`가 이미 있으면 기존 플랫폼 파일을 보호하기 위해 안전하게 중단한다.

## 2. Gateway 실행과 앱 연결

실기기에서 연결할 때는 프로젝트 루트의 Gateway를 신뢰하는 LAN에 명시적으로 공개한다. 앱 Base URL에는 브라우저 주소가 아니라 실행 대상 기기에서 Raspberry Pi 또는 개발 PC에 도달할 수 있는 주소를 넣는다.

```bash
cd pi-bridge
SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_CORS_ORIGINS=http://192.168.0.50:3101 \
python -m app
```

```bash
flutter devices

# iOS Simulator: 개발 PC의 localhost
flutter run -d <ios-simulator-id> \
  --dart-define=PI_API_BASE_URL=http://127.0.0.1:8101 \
  --dart-define=PI_LOT_ID=demo-01 \
  --dart-define=PI_CUSTOMER_ID=demo-customer

# Android Emulator: 호스트 PC의 특별 주소
flutter run -d <android-emulator-id> \
  --dart-define=PI_API_BASE_URL=http://10.0.2.2:8101 \
  --dart-define=PI_LOT_ID=demo-01 \
  --dart-define=PI_CUSTOMER_ID=demo-customer

# Android/iOS 실기기: 같은 Wi-Fi의 Raspberry Pi 주소 예시
flutter run -d <physical-device-id> \
  --dart-define=PI_API_BASE_URL=http://192.168.0.50:8101 \
  --dart-define=PI_LOT_ID=demo-01 \
  --dart-define=PI_CUSTOMER_ID=<로그인-고객-ID>
```

꺾쇠 안의 값은 `flutter devices`에 표시된 실제 Device ID로 바꾼다.

기본값은 `http://127.0.0.1:8101`, 주차장 ID는 `demo-01`, 고객 ID는 `demo-customer`다. 배포 앱에서는 로그인 계정의 고유 ID를 `PI_CUSTOMER_ID`로 주입해야 고객별 차량이 분리된다. HTTP/HTTPS에 따라 WebSocket 주소는 각각 WS/WSS로 자동 변환된다.

## 3. 로컬 Raspberry Pi의 HTTP/ws 허용

모바일 OS는 평문 HTTP를 기본 차단할 수 있다. 데모 Gateway가 아직 HTTPS/WSS를 제공하지 않는 경우에만 현재 러너에 개발용 예외를 적용한다.

현재 개발 러너는 실제 Pi 검증용으로 Android Debug에만 cleartext를 허용하고, iOS는 ATS의 `NSExceptionDomains`에서 빌드 대상 `PI_IP` 하나만 허용한다. 두 설정 모두 `SNAP_DEV_NETWORK` 마커 안에 있어 아래 제거 명령으로 되돌릴 수 있다. 체크아웃에 이전 시험 주소가 남아 있을 수 있으므로 다른 Pi를 사용할 때는 iOS 예외 키와 `PI_API_BASE_URL`을 같은 주소로 바꾼다.

```bash
cd mobile
dart run tool/configure_local_network.dart --allow-insecure-local-http
```

플랫폼 디렉터리가 없는 별도 소스 사본에서 러너를 재생성하면서 예외를 적용하려면 다음 옵션을 사용한다.

```bash
sh tool/bootstrap_platforms.sh --allow-insecure-local-http
```

플랫폼 생성 스크립트는 옵션과 관계없이 Android Release의 `INTERNET` 권한과 iOS의 `NSLocalNetworkUsageDescription`을 추가한다. 마커가 없는 새 러너에서 평문 옵션을 사용하면 다음 개발 전용 설정도 적용한다.

- Android: `android/app/src/debug/AndroidManifest.xml`에만 `usesCleartextTraffic=true`를 병합하므로 Release에는 적용되지 않는다.
- iOS: `ios/Runner/Info.plist`에 개발용 `NSAllowsArbitraryLoads` 블록을 표시 마커와 함께 넣는다.

`NSAllowsArbitraryLoads`나 IP별 ATS 예외는 iOS Release에도 영향을 줄 수 있는 **개발 전용 예외**다. App Store/외부 배포 전 Gateway를 HTTPS/WSS로 전환하고 반드시 제거한다. 사내 실기기용 development-signed Release로 HTTP Pi를 검증할 때만 필요한 예외를 유지한다.

```bash
dart run tool/configure_local_network.dart --remove-insecure-local-http
flutter build apk --release
flutter build ios --release
```

제거 명령은 개발용 cleartext/ATS 블록만 삭제하며, 앱 통신에 필요한 Android `INTERNET` 권한과 iOS 로컬 네트워크 설명은 유지한다.

Android Release 러너는 debug key로 대체 서명하지 않는다. 배포용 APK/AAB를 만들기 전에 보호된 빌드 환경에서 별도의 Release keystore와 signing config를 설정한다. iOS도 저장소에 Team을 고정하지 않으므로 각 개발자 또는 CI의 서명 설정이 필요하다.

실기기 연결 시 Pi와 휴대폰이 같은 네트워크인지, Pi 방화벽이 `8101/tcp`를 허용하는지, Gateway가 `127.0.0.1`이 아닌 `0.0.0.0`에 바인딩됐는지도 확인한다.

## 4. 통신 검증

모바일 앱과 같은 Dart 모델·클라이언트로 읽기 계약을 빠르게 확인한다.

```bash
cd mobile
dart run tool/gateway_smoke.dart \
  --base-url=http://127.0.0.1:8101 \
  --customer-id=demo-customer
```

성공 조건은 Health, REST Snapshot, 고객 차량 목록, WebSocket 첫 `SNAPSHOT` 이벤트가 유효한 계약을 반환하는 것이다. 발렛·출차 POST 전체 흐름 검증은 프로젝트의 통합 검증 스크립트를 함께 사용한다.

## 5. 코드 구조

```text
lib/
├── app/                       # 환경 설정, 테마, 앱 진입점
├── core/
│   ├── contracts/             # REST/WS 공통 DTO와 상태 enum
│   └── networking/            # HttpClient, WebSocket, 재연결/동기화
└── features/parking_lot/      # 현황 및 발렛/출차 UI
```

네트워크 계층은 `dart:io`를 사용하므로 이 패키지의 배포 대상은 iOS와 Android다. Flutter Web용으로 확장할 때는 동일 계약을 유지하되 네트워크 어댑터를 분리한다.

## 현재 로컬 검증 경계

2026-09-06 기준 Flutter 3.47.2/Dart 3.13.2에서 `flutter analyze`, Flutter 테스트 41개, Android Debug APK 빌드, 서명된 iPhoneOS Release 빌드가 통과했다. 같은 테스트에서 430×932/932×430 phone과 834×1194/1194×834 tablet 레이아웃을 검증한다. 동일한 Dart 클라이언트로 검증 당시 실제 Raspberry Pi의 `PI_IP:8101`에서 Health, REST Snapshot, 고객 차량 조회, WebSocket Snapshot을 확인했다. 같은 Pi 주소를 주입한 Release 앱을 실제 iPad에 덮어 설치하고 전면 실행했다.

저장소에는 개인 Apple Development Team을 고정하지 않는다. 각 개발자가 Xcode에서 자신의 Team을 선택해야 실제 기기 서명이 가능하다. 현재 Pi의 Gateway 모드는 `pi-simulator-multi-vehicle`이므로 실제 센서·모터 E2E와 Gateway 강제 단절 후 재연결 시나리오는 별도 검증 범위다.
