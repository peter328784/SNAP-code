# 클라이언트–Raspberry Pi Gateway 통신 검증

기준일: 2026-08-29

검증 범위: Web Mock·Flutter 클라이언트 ↔ Raspberry Pi FastAPI Gateway

> **현재 상태 안내 (2026-08-29):** 아래 결과는 로컬 Simulator 중심의 당시 검증 기록이다. 이후 실제 Mega·로봇 Serial Adapter와 `SNAP_HARDWARE_MODE=serial`이 구현됐다. 최신 실행·환경변수는 [Pi Gateway README](../pi-bridge/README.md), 실제 Raspberry Pi의 TCP·UART 확인은 [패킷 확인 매뉴얼](manual/raspberry-pi-web-packet-cmd.md)을 따른다. 실제 배선·센서·모터의 물리 검증은 아직 별도이며 Hardware mode 출차는 지원하지 않아 `409 Conflict`로 거절한다.

## 한 줄 판정

Web Mock 검증기와 로컬 Pi Simulator 사이의 고객 차량 2대 등록→연속 입차→독립 출차 REST·WebSocket 흐름은 통과했다. Flutter 고객 앱 공통 소스와 통신 테스트는 작성됐지만 현재 PC에 Flutter SDK가 없어 Android·iOS 실행 검증은 아직 남아 있다.

## 구현한 클라이언트 계약

| 구분 | 계약 |
|---|---|
| 상태 확인 | `GET /health` |
| 최신 현황 | `GET /v1/parking-lots/{lotId}/snapshot` |
| 고객 차량 조회·등록 | `GET/POST /v1/customers/{customerId}/vehicles` |
| 주차 요청 | `POST /v1/parking-requests` |
| 기존 호환용 요청 확정 | `POST /v1/parking-requests/{requestId}/confirm` |
| 작업 조회 | `GET /v1/jobs/{jobId}` |
| 출차 요청 | `POST /v1/retrieval-requests` |
| 실시간 상태 | `WS /v1/events` |

Web Mock과 Flutter는 같은 `customerId`, 내부 `vehicleId`, `lotId`, 슬롯·로봇·작업 Snapshot, `60/120/180/240`분 주차 요청 DTO와 WebSocket 이벤트 봉투를 사용한다. 차량번호는 고객 차량 API에만 포함되고 공개 주차장 Snapshot에는 포함되지 않는다.

## 실행 검증 결과

| 검증 | 결과 | 증거 |
|---|---|---|
| Pi Gateway 단위·API·Adapter | 통과 | Python `unittest` 26건 |
| WebSocket 무이벤트 연결 종료 | 통과 | 회귀 테스트 1건, 구독·대기 task 즉시 정리 |
| Web Mock 정적 검사 | 통과 | `npm run lint` |
| Web Mock 프로덕션 빌드 | 통과 | `npm run build` |
| Gateway Health·REST Snapshot | 통과 | `npm run verify:pi` |
| WebSocket 최초 Snapshot | 통과 | `npm run verify:pi` |
| 고객 차량 2대 등록·조회 | 통과 | 고객별 GET/POST API와 서로 다른 내부 ID |
| 시간 기반 두 차량 입차 | 통과 | 1시간→1번, 4시간 이상→6번 배정 |
| `PARKED` 유지·대기 복귀 | 통과 | 첫 차량 주차 후 `activeJob=null`, 두 번째 입차 가능 |
| 차량별 독립 출차 | 통과 | 첫 차량 출차 뒤 두 번째 차량의 슬롯·`PARKED` 유지 |
| 최종 `IDLE` 복귀 | 통과 | 두 차량 정리 출차 뒤 WebSocket과 REST `activeJob=null` 일치 |
| WebSocket 종료 뒤 Gateway 정상 종료 | 통과 | Uvicorn 1회 `Ctrl+C`로 정상 종료 |
| Flutter 모델·재연결·중복 요청 테스트 | 작성, 미실행 | Flutter/Dart SDK 미설치 |
| Android·iOS 빌드와 실기기 LAN 통신 | 미검증 | Flutter 개발환경과 검증 기기 필요 |

## 재현 명령

아래 명령은 각 터미널을 현재 모노레포 루트인 `snap/`에서 연 기준이다.

첫 번째 터미널에서 Gateway를 실행한다.

```bash
cd pi-bridge
source .venv/bin/activate
python -m app
```

두 번째 터미널에서 Web 클라이언트 계약을 검증한다.

```bash
cd web-mock
npm run verify:pi
```

검증기는 `mode=pi-simulator` 계열에서만 차량 등록·주차·출차 쓰기 요청을 보낸다. 실제 Gateway 모드에서는 Health, REST Snapshot과 WebSocket 수신만 검사한다. 읽기 전용으로 강제하려면 `npm run verify:pi -- --read-only`를 사용한다.

Flutter SDK 설치 후 다음 Gate를 실행한다.

```bash
cd mobile
flutter pub get
# HTTP/ws 개발 Gateway를 사용할 때만 적용한다.
dart run tool/configure_local_network.dart --allow-insecure-local-http
flutter analyze
flutter test
flutter devices
```

그다음 Android Emulator와 iOS Simulator 또는 실기기에서 각각 앱을 실행하고 다음을 확인한다.

1. 최신 Snapshot과 6개 슬롯을 표시한다.
2. 주차 요청을 연속 탭해도 POST가 한 건만 생성된다.
3. WebSocket을 끊었다가 복구하면 REST Snapshot을 먼저 다시 조회한다.
4. 각 고객의 차량 번호, 예상 주차시간, 배정 슬롯, 입차·출차 상태가 Web Mock과 일치한다.
5. 첫 차량이 `PARKED`인 동안 두 번째 차량을 입차하고, 첫 차량만 출차해도 두 번째 차량 상태가 유지된다.

## 검증 경계

- 포함: 클라이언트 DTO, REST, WebSocket, 재연결·Snapshot 복구, 중복 탭 방지
- 이 기록의 제외 범위: 실제 Arduino·Serial/Bluetooth, 센서·모터, 경로 계획, 비상 정지와 물리 안전
- 이 기록에서 검증한 Gateway 흐름은 메모리 기반 Simulator이며 재시작하면 상태가 초기화된다. 이후 추가된 Serial mode의 상태는 문서 상단 안내를 참고한다.
- 서버 Idempotency-Key가 아직 없어 응답 유실 뒤 사용자가 다시 요청하는 경우의 종단 간 중복 방지는 Gateway 후속 계약이 필요하다.
