# S.N.A.P 웹 요구사항 #2 구현 및 추적성 기록 (REQ-260829)

## 문서 정보

| 항목 | 내용 |
|---|---|
| 문서 목적 | 웹 요구사항을 현재 코드의 변경 지점과 검증 항목까지 추적 가능하게 연결 |
| 요구사항 원문 | 로컬 비공개 문서 `docs/.requirements/260829-inoutput.md` |
| 대상 구성요소 | `web-mock`, `pi-bridge`, 공유 API 계약 및 `mobile` 호환 계층 |
| 문서 상태 | 소프트웨어 기준선 구현 완료 — Flutter SDK 실행·QEMU·실장비 HIL은 후속 검증 |
| 작성 기준일 | 2026-08-29 |

## 0. 구현 결과 요약

2026-08-29 기준으로 Web Mock, Flutter 고객 앱 소스, Pi Gateway의 요구 기능을 구현했다.

- 고객별 차량 등록·목록 API와 차량별 상태·주차 위치
- 한 고객의 복수 차량 및 차량 간 독립 입·출차
- `60/120/180/240`분 입력과 Pi의 시간 기반 슬롯 `1~6` 배정
- 단일 `activeJob`, 작업 완료 후 `STANDBY` 복귀, 주차 차량의 `PARKED` 유지
- 지정 만차 오류, 공개 Snapshot의 차량번호 비노출
- Mega 프레임 엄격 파서와 Uno 슬롯별 경로·상태 Codec/Transport 경계
- 고객 화면의 배정 기준·배터리·리프트 제거와 통로 기반 경로 표시

검증은 Gateway 단위/API 테스트 26건, Web lint/build, REST·WebSocket 두 차량 통합 시나리오까지 통과했다. 현재 개발 머신에 Flutter/Dart SDK가 없어 Flutter 테스트와 analyze는 실행하지 못했으며, QEMU와 실제 Mega/Uno HIL도 별도 장비 검증으로 남아 있다. 상태 저장은 현재 프로세스 메모리 기반이며 재시작 복구, 사용자 인증, 실장비의 baud/ACK/timeout 확정은 원문 기능 범위 밖의 운영 후속 항목이다.

## 1. 결론

기존의 `Web Mock → FastAPI Pi Gateway → ParkingController` 통신 경계는 유지하고, 현재의 단일 전역 `job`을 다음 책임으로 분리한다.

- 사용자별 차량과 각 차량의 주차 상태
- 동시에 하나만 실행되는 로봇 작업
- 주차면의 물리 센서 상태와 소프트웨어 예약 상태
- 시간 기반 주차면 배정
- Arduino Mega 및 Uno 통신 Adapter
- 재시작 후에도 차량과 배정 상태를 복구할 수 있는 저장소

요구사항 원문에는 웹을 Flask로 표기했지만 현재 저장소는 React/Next 호환 Web과 FastAPI Gateway를 사용한다. Flask가 납품 필수 조건이 아니라면 기능과 무관한 프레임워크 재작성을 하지 않는다. Flask가 필수인 경우에도 도메인·배정·Adapter 계층은 유지하고 HTTP/WebSocket 전송 계층만 교체한다.

## 2. 권장 목표 구조

```text
Arduino Mega ── Bluetooth ── OccupancyAdapter ─┐
                                               ├── ParkingService ── REST/WS ── Web
Arduino Uno  ───── UART ───── RobotAdapter ────┘          │
                                                   SlotAllocator
                                                         │
                                                     SQLite
```

Web은 Raspberry Pi API만 호출한다. 센서 판정, 주차면 배정, 명령 직렬화, 하드웨어 오류 처리는 Raspberry Pi가 소유한다.

## 3. 구현 전 결정 기록

아래 항목은 구현 기준선에 포함할 권장 해석이다. `미확정` 항목은 장비 담당자와 합의한 뒤 상태를 `확정`으로 변경한다.

| 결정 ID | 상태 | 권장 결정 | 근거·영향 |
|---|---|---|---|
| DEC-260829-01 | 확정·구현 | 예상시간은 원문의 정형 명세인 `1시간/2시간/3시간/4시간 이상`을 기준으로 한다. | 원문 상단의 `30분/1시간/2시간/4시간`과 충돌한다. |
| DEC-260829-02 | 확정·구현 | 기존 React/Next 호환 Web과 FastAPI Gateway를 유지한다. | 현재 REST·WebSocket 및 Flutter 계약을 재사용할 수 있다. |
| DEC-260829-03 | 확정·구현 | 한 대의 로봇은 작업을 직렬 실행하고 작업 중 새 실행 요청은 거절한다. 완료되어 주차 중인 다른 차량은 다음 입차를 막지 않는다. | 사용자 상태 독립성과 단일 로봇 물리 제약을 동시에 만족한다. |
| DEC-260829-04 | 확정·구현 | 전체 차량번호와 내부 UUID를 분리하고 공개 Snapshot에는 차량번호를 넣지 않는다. | 뒤 4자리만으로는 차량을 고유하게 식별할 수 없다. |
| DEC-260829-05 | 확정·구현 | 정식 슬롯 ID는 `1~6`으로 통일하고 기존 `A1~B3` 입력만 각각 `1~6`으로 호환 변환한다. | Web, Pi, Flutter, 실제 배선이 같은 슬롯을 가리켜야 한다. |
| DEC-260829-06 | 확정·구현 | 3시간은 먼 그룹 `4→5→6`, 4시간 이상은 `6→1` 순으로 가장 먼 빈자리부터 배정한다. | 원문의 “먼”과 “가장 먼”을 구분하면서 에너지 목적을 반영한다. |
| DEC-260829-07 | 미확정 | Uno가 실제 위치를 전송하지 않으면 Web에는 위치를 `추정`으로 표시한다. | 현재 상태 문자열만으로 정확한 좌표를 알 수 없다. |
| DEC-260829-08 | 부분 구현 | 요구된 슬롯별 경로 6종과 상태 Codec/Transport를 구현했다. baud rate, 줄바꿈, ACK, timeout, 출차·복귀 경로는 실장비 HIL 전에 확정한다. | 새 요구사항과 기존 PoC 문서의 응답 코드가 서로 다르다. |

## 4. 요구사항 추적성 매트릭스

### 4.1 사용자·차량

| 요구사항 ID | 원문 위치 | 요구사항 | 구현 전 차이 | 구현 대상 | 검증 ID |
|---|---:|---|---|---|---|
| REQ-260829-VEH-01 | L8~10, L45~46 | 사용자 화면에 차량 ID 대신 차량번호 표시 | Web과 Flutter가 `차량 ID`를 표시 | `Vehicle.vehicleNumber` 추가, UI 라벨·검증 문구 변경 | AT-UI-01, AT-API-01 |
| REQ-260829-VEH-02 | L18~19, L39~40, L104~107 | 한 사용자가 여러 차량 등록 | 단일 `vehicleId` 상태만 존재 | 사용자별 `Vehicle[]`, 차량 등록 API, 차량 목록 UI | AT-FLOW-02 |
| REQ-260829-VEH-03 | L24~28 | 차량별 주차 상태와 주차 위치 표시 | 전역 `snapshot.job`만 존재 | 차량별 상태·`slotId` 저장 및 사용자용 조회 | AT-FLOW-01, AT-FLOW-03 |
| REQ-260829-VEH-04 | L100~103 | 차량 상태에 따라 입차 또는 출차 버튼 표시 | 전역 `job.state`로 버튼 하나를 전환 | 각 Vehicle Card에서 상태별 CTA 계산 | AT-UI-04 |
| REQ-260829-VEH-05 | L103 | 다른 사용자·차량 상태와 독립적으로 요청 | 주차된 첫 차량이 다음 입차를 차단 | 차량 상태와 `activeJob` 분리 | AT-FLOW-01, AT-CONC-01 |

### 4.2 시간·배정·주차면

| 요구사항 ID | 원문 위치 | 요구사항 | 구현 전 차이 | 구현 대상 | 검증 ID |
|---|---:|---|---|---|---|
| REQ-260829-TIME-01 | L203~212 | `1/2/3/4시간 이상` 중 하나 선택 | 현재 `30/60/120/240분` | Web 선택지를 `60/120/180/240+` 버킷으로 변경 | AT-UI-02, AT-API-02 |
| REQ-260829-ALLOC-01 | L214~218, L222~235 | Web은 시간을 보내고 Pi가 슬롯 선택 | 현재 Pi가 시간을 버리고 사용자 선호로 선택 | `SlotAllocator`와 서버 측 원자 예약 | AT-ALLOC-01~05 |
| REQ-260829-ALLOC-02 | L228~235 | 단시간은 가까운 슬롯, 장시간은 먼 슬롯 우선 | 고정 preference→slot 매핑 | 슬롯 topology의 거리 순위 기반 정책 | AT-ALLOC-01~03 |
| REQ-260829-LOT-01 | L146~155, L197~201 | Mega 상태로 1~6번 주차면을 실시간 갱신 | 실제 Mega Adapter 없음 | `OccupancyAdapter`, 상태 신선도와 WebSocket 이벤트 | AT-HW-MEGA-01~04 |
| REQ-260829-LOT-02 | L260~262 | 만차 시 입차 비활성화 및 지정 문구 표시 | 명시적 `LOT_FULL` 계약과 UI 없음 | 오류 코드, `availableCount`, 정확한 사용자 문구 | AT-ALLOC-05, AT-UI-03 |

### 4.3 로봇·화면

| 요구사항 ID | 원문 위치 | 요구사항 | 구현 전 차이 | 구현 대상 | 검증 ID |
|---|---:|---|---|---|---|
| REQ-260829-ROB-01 | L30~34, L239~254 | 배정 슬롯, 로봇 위치와 동작 상태 표시 | job 상태로 위치 비율을 임의 추정 | `robot.actionState`, `positionNode`, 사용자용 상태 매핑 | AT-HW-UNO-02, AT-UI-05 |
| REQ-260829-ROB-02 | L47~49, L97~99 | 작업 완료 후 입·출구 사이 대기 위치로 복귀 | 주차 완료가 `PARKED`에서 끝남 | `RETURNING_TO_STANDBY → IDLE`, `activeJob=null` | AT-FLOW-01 |
| REQ-260829-ROB-03 | L92~94 | 실제 통로를 따라 경로 표시 | 하드코딩 Bezier 경로가 공간을 가로지름 | waypoint 기반 통로 topology와 polyline | AT-GEO-01, AT-E2E-01 |
| REQ-260829-UI-01 | L85~96 | 배정 기준, 배터리, 리프트 과정·위치 삭제 | 사용자 화면에 모두 노출 | UI에서만 숨기고 운영 telemetry는 유지 | AT-UI-06 |
| REQ-260829-CONC-01 | L97~103, L258~262 | 작업 중 입차 비활성화, 완료 후 다른 차량 입차 허용 | `PARKED`가 전역 작업 상태라 출차 전까지 차단 | 단일 `ActiveRobotJob`과 차량별 `PARKED` 상태 분리 | AT-FLOW-01, AT-CONC-01 |

### 4.4 장치 통신

| 요구사항 ID | 원문 위치 | 요구사항 | 구현 전 차이 | 구현 대상 | 검증 ID |
|---|---:|---|---|---|---|
| REQ-260829-HW-01 | L146~155 | Mega가 `1:EMPTY,...` 형식으로 상태 전송 | Bluetooth 수신·파서 없음 | Mega serial-over-Bluetooth Reader와 Frame Parser | AT-HW-MEGA-01~04 |
| REQ-260829-HW-02 | L159~173 | Pi가 슬롯별 경로 문자열을 Uno로 전송 | UART Writer 없음 | 경로 테이블과 `RobotAdapter.executePath` | AT-HW-UNO-01 |
| REQ-260829-HW-03 | L177~191 | Uno 상태 문자열을 Pi가 수신 | 실제 Reader와 상태 매핑 없음 | 상태 Codec, timeout, 오류·중복 이벤트 처리 | AT-HW-UNO-02~04 |

## 5. 상세 구현 설계

### 5.1 도메인 상태 분리

권장 내부 상태는 사용자 표시 상태보다 상세하게 유지한다.

```text
VehicleState
  READY_TO_PARK
  PARKING_REQUESTED
  PARKING_IN_PROGRESS
  PARKED
  RETRIEVAL_REQUESTED
  RETRIEVING
  RETRIEVED
  ERROR

RobotState
  IDLE_AT_STANDBY
  MOVING_TO_ENTRY
  ACQUIRING_VEHICLE
  CARRYING_TO_SLOT
  MOVING_TO_PARKED_VEHICLE
  CARRYING_TO_EXIT
  RETURNING_TO_STANDBY
  OFFLINE
  FAULT
```

`GRIPPING` 같은 장비 세부 상태는 내부적으로 보존하되 사용자 화면에는 `차량 인수 중`처럼 추상화해 표시한다.

입차 완료 상태 전이는 다음과 같다.

```text
Vehicle: PARKING_IN_PROGRESS → PARKED
Slot: RESERVED → OCCUPIED
Robot: CARRYING_TO_SLOT → RETURNING_TO_STANDBY → IDLE_AT_STANDBY
ActiveRobotJob: RUNNING → COMPLETED → null
```

차량의 `PARKED` 상태가 로봇의 다음 작업을 막지 않아야 한다.

### 5.2 주차면 상태

센서 상태와 논리 상태를 분리한다.

| 필드 | 값 예시 | 소유자 |
|---|---|---|
| `sensorState` | `EMPTY`, `OCCUPIED`, `UNKNOWN` | Mega Adapter |
| `reservationState` | `NONE`, `RESERVED` | ParkingService |
| `displayState` | `AVAILABLE`, `RESERVED`, `OCCUPIED`, `UNKNOWN`, `OUT_OF_SERVICE` | 두 상태를 합성 |

센서 메시지가 정해진 시간 안에 갱신되지 않거나 소프트웨어 배정과 충돌하면 해당 슬롯을 `UNKNOWN`으로 두고 새 차량을 배정하지 않는다.

### 5.3 시간 기반 배정

`SlotAllocator`는 외부 I/O가 없는 순수 로직으로 작성한다.

1. 신선한 `EMPTY` 슬롯만 후보로 선택한다.
2. 예약, `UNKNOWN`, `OUT_OF_SERVICE` 슬롯을 제외한다.
3. 시간 버킷에 따른 거리 정책을 적용한다.
4. 동일 순위는 현재 로봇 이동거리와 슬롯 번호로 결정한다.
5. Controller lock 또는 저장소 트랜잭션 안에서 슬롯을 예약한다.
6. 후보가 없으면 `LOT_FULL`을 반환한다.

슬롯별 물리 정보를 설정 한 곳에서 관리한다.

```text
SlotTopology
  apiId
  displayNumber
  hardwareSlot
  distanceRank
  coordinates
  aisleWaypoints
  parkingRoute
  retrievalRoute
  returnToStandbyRoute
```

### 5.4 사용자와 저장소

MVP에서도 Pi 재시작 후 차량과 슬롯 관계가 사라지지 않도록 SQLite를 권장한다.

```text
User 1 ── N Vehicle 1 ── N ParkingSession
ParkingSession N ── 1 Slot
ParkingSession 1 ── N Job
```

브라우저 데모에서는 익명 owner token을 사용할 수 있으나, 운영 환경에서는 인증 계정과 차량 소유권 검증으로 교체한다. 공개 주차장 Snapshot에는 다른 사용자의 차량번호를 넣지 않는다.

### 5.5 API의 점진적 확장

기존 Web과 Flutter의 동시 회귀를 피하도록 파괴적 변경보다 필드 추가를 우선한다.

- 기존 `job`은 호환 alias로 일시 유지
- `activeJob` 추가
- `myVehicles` 또는 별도 `/v1/me/vehicles` 조회 추가
- `vehicleNumber`를 canonical 필드로 추가하고 기존 `vehicleId` 요청 alias를 한시적으로 허용
- 명령에 `clientRequestId`를 추가해 중복 POST 방지
- 이벤트에 `eventId`, `sequence`, `schemaVersion`, `occurredAt` 추가

권장 API는 다음과 같다.

| 용도 | 메서드·경로 |
|---|---|
| 주차장 Snapshot | `GET /v1/parking-lots/{lotId}/snapshot` |
| 내 차량 목록 | `GET /v1/me/vehicles` |
| 차량 등록 | `POST /v1/me/vehicles` |
| 입차 요청 | `POST /v1/parking-requests` |
| 출차 요청 | `POST /v1/retrieval-requests` |
| 작업 조회 | `GET /v1/jobs/{jobId}` |
| 실시간 이벤트 | `WS /v1/events` |

입차 요청에는 시간 버킷만 포함하고 `targetSlot`을 받지 않는다. 슬롯 결정은 Pi에서만 수행한다.

### 5.6 Mega Adapter

권장 신규 경계는 `OccupancyAdapter`다.

- newline 단위 Frame Reader
- 슬롯 1~6의 누락·중복 검사
- `EMPTY/OCCUPIED` 외 값 거부
- 부분 프레임과 최대 길이 제한
- Bluetooth 연결 재시도와 지수 backoff
- 마지막 정상 수신 시각 기록
- stale timeout 시 전체 또는 해당 슬롯을 `UNKNOWN` 처리
- 정상 변경만 WebSocket 이벤트로 전파

### 5.7 Uno Adapter

권장 신규 경계는 `RobotAdapter`다.

- 슬롯별 경로 문자열을 한 곳에서 관리
- 명령 프레이밍과 ACK timeout 적용
- `READY/TRACING/APPROACHING/GRIPPING/REVERSING/DONE`을 현재 Job 문맥과 함께 해석
- 알 수 없는 상태, 중복 `DONE`, 연결 해제, 작업 timeout 처리
- 시뮬레이터와 실제 Serial 구현이 같은 인터페이스를 구현

출차 및 대기 위치 복귀용 명령이 아직 정의되지 않았으므로 실제 장비 구현 전에 프로토콜을 확정한다.

### 5.8 Web UI

현재 단일 페이지는 다음 단위로 분리한다.

- `VehicleList` / `VehicleCard`
- `ParkingRequestForm`
- `ParkingLotMap`
- `RobotStatus`
- `useParkingSession`
- `parking-geometry.ts`

화면 변경사항은 다음과 같다.

- 차량 ID를 차량 번호로 변경
- 예상시간을 `1/2/3/4시간 이상`으로 변경
- 배정 기준 입력 삭제
- 배터리, 리프트 상태와 Lift Zone 삭제
- 차량별 상태에 따라 입차 또는 출차 버튼 표시
- 주차 완료 차량 아래 `다른 차량 등록하기` 표시
- 만차 시 정확한 문구와 비활성화 상태 표시
- 배정 슬롯과 로봇 진행 상태 표시
- 실제 통로 waypoint를 잇는 polyline으로 경로 표현
- 입구와 출구 사이에 별도 `STANDBY` 노드 배치

상태 문자열만으로 위치를 추정할 경우 접근성 라벨과 화면에 `추정 위치`임을 명시한다.

## 6. 변경 대상

### 6.1 Pi Gateway

| 파일 | 변경 내용 |
|---|---|
| `pi-bridge/app/controller.py` | 차량 상태와 로봇 작업 분리, 상태 전이 조정 |
| `pi-bridge/app/main.py` | DTO, 오류 코드, 사용자·차량 API, Snapshot 확장 |
| `pi-bridge/app/domain.py` | 차량·슬롯·로봇·작업 모델과 enum 신규 추가 |
| `pi-bridge/app/allocator.py` | 시간 기반 슬롯 배정 신규 추가 |
| `pi-bridge/app/adapters/occupancy.py` | Mega 전송 경계와 엄격 프레임 파서 신규 추가 |
| `pi-bridge/app/adapters/robot.py` | Uno 경로·상태 Codec, 전송 Adapter와 Simulator 신규 추가 |

### 6.2 Web

| 파일 | 변경 내용 |
|---|---|
| `web-mock/app/pi-client.ts` | 확장 Snapshot, 차량 모델, 오류 코드, API 함수 |
| `web-mock/app/page.tsx` | 화면 조합과 상태별 CTA |
| `web-mock/app/globals.css` | Lift Zone 제거와 차량 목록·경로 스타일 |
| `web-mock/scripts/verify-pi-gateway.mjs` | 두 차량 입·출차 흐름으로 검증 확장 |

### 6.3 공유 계약

API가 확장되면 다음 모바일 파일도 회귀 확인한다.

- `mobile/lib/core/contracts/parking_models.dart`
- `mobile/lib/core/networking/pi_gateway_client.dart`
- `mobile/lib/core/networking/pi_gateway_session.dart`
- `mobile/lib/features/parking_lot/parking_dashboard.dart`
- `mobile/test/`

## 7. 구현 단계

| 단계 | 산출물 | 완료 조건 |
|---|---|---|
| 0. 계약 확정 | 결정 기록, 슬롯 변환표, Uno/Mega 프로토콜 | 모든 `미확정` 항목에 담당자·확정값 기록 |
| 1. 도메인 리팩터링 | 차량별 상태, `activeJob`, SQLite, Allocator | Simulator에서 두 차량이 독립적으로 입·출차 |
| 2. Web 변경 | 차량 목록, CTA, 시간 선택, 새 지도 | UI 요구사항과 만차 UX 자동 테스트 통과 |
| 3. Mega 연동 | Bluetooth Adapter | 정상·오류·stale 상태가 Snapshot과 WS에 반영 |
| 4. Uno 연동 | UART Adapter | 경로 6종, ACK, 상태, timeout 검증 통과 |
| 5. 계약 회귀 | Web·Gateway·Flutter·QEMU 검증 | 공유 API와 두 차량 E2E 통과 |
| 6. HIL 검수 | 실제 Mega/Uno/로봇 통합 결과 | 경로·복귀·통신 단절 안전 동작 확인 |

## 8. 수용 테스트 추적성

| 검증 ID | 검증 내용 | 추적 요구사항 |
|---|---|---|
| AT-ALLOC-01 | 60분 요청이 가까운 유효 슬롯을 선택 | REQ-260829-ALLOC-01, REQ-260829-ALLOC-02 |
| AT-ALLOC-02 | 120분 요청이 가까운 유효 슬롯을 선택 | REQ-260829-ALLOC-02 |
| AT-ALLOC-03 | 180분과 240분 이상 정책이 확정된 순서대로 다른 거리 정책을 적용 | REQ-260829-TIME-01, REQ-260829-ALLOC-02 |
| AT-ALLOC-04 | 점유·예약·UNKNOWN 슬롯을 후보에서 제외하고 동률 규칙을 고정 | REQ-260829-ALLOC-01, REQ-260829-LOT-01 |
| AT-ALLOC-05 | 빈 슬롯이 없으면 `LOT_FULL`과 지정 문구를 반환 | REQ-260829-LOT-02 |
| AT-FLOW-01 | V1 주차 후 로봇은 대기 복귀·IDLE이 되고 V1은 PARKED를 유지하며 V2 입차 가능 | REQ-260829-ROB-02, REQ-260829-CONC-01 |
| AT-FLOW-02 | 한 사용자가 V1과 V2를 등록하고 상태를 독립 관리 | REQ-260829-VEH-02, REQ-260829-VEH-05 |
| AT-FLOW-03 | V1 출차 후에도 V2의 슬롯·상태가 변하지 않음 | REQ-260829-VEH-03, REQ-260829-VEH-05 |
| AT-CONC-01 | 동시 요청이 같은 슬롯을 이중 예약하지 않고 로봇 작업은 하나만 실행 | REQ-260829-ALLOC-01, REQ-260829-CONC-01 |
| AT-API-01 | 전체 차량번호와 내부 ID를 분리하고 타 사용자의 번호를 공개 Snapshot에서 숨김 | REQ-260829-VEH-01, REQ-260829-VEH-05 |
| AT-API-02 | 허용되지 않은 시간 버킷과 Web이 지정한 target slot을 거부 | REQ-260829-TIME-01, REQ-260829-ALLOC-01 |
| AT-HW-MEGA-01 | 슬롯 1~6 정상 프레임 파싱 | REQ-260829-HW-01, REQ-260829-LOT-01 |
| AT-HW-MEGA-02 | 순서가 다른 정상 프레임 파싱 | REQ-260829-HW-01 |
| AT-HW-MEGA-03 | 누락·중복·잘못된 상태 프레임 거부 | REQ-260829-HW-01 |
| AT-HW-MEGA-04 | 연결 해제·stale 상태를 UNKNOWN으로 전환 | REQ-260829-HW-01, REQ-260829-LOT-01 |
| AT-HW-UNO-01 | 슬롯별 6개 경로 문자열이 정확히 전송됨 | REQ-260829-HW-02 |
| AT-HW-UNO-02 | Uno 상태 문자열이 올바른 로봇·사용자 상태로 매핑됨 | REQ-260829-HW-03, REQ-260829-ROB-01 |
| AT-HW-UNO-03 | timeout·연결 해제를 완료 상태로 오인하지 않음 | REQ-260829-HW-03 |
| AT-HW-UNO-04 | 중복 DONE이 작업이나 슬롯을 중복 완료하지 않음 | REQ-260829-HW-03 |
| AT-UI-01 | 모든 사용자 라벨이 차량 ID가 아닌 차량 번호를 사용 | REQ-260829-VEH-01 |
| AT-UI-02 | `1/2/3/4시간 이상` 중 하나만 선택 가능 | REQ-260829-TIME-01 |
| AT-UI-03 | 만차 문구와 입차 버튼 비활성화가 정확히 표시 | REQ-260829-LOT-02 |
| AT-UI-04 | 각 차량 상태에 맞는 입차·출차 버튼과 추가 등록 버튼 표시 | REQ-260829-VEH-02, REQ-260829-VEH-04 |
| AT-UI-05 | 배정 슬롯과 로봇 진행 상태 표시 | REQ-260829-ROB-01 |
| AT-UI-06 | 배정 기준, 배터리, 리프트 상태와 위치가 사용자 화면에 없음 | REQ-260829-UI-01 |
| AT-GEO-01 | 모든 경로 segment가 통로 내부에 있고 슬롯 영역을 관통하지 않음 | REQ-260829-ROB-03 |
| AT-E2E-01 | Web→Pi→Adapter→WS 두 차량 전체 흐름과 대기 위치 복귀 확인 | 전체 핵심 요구사항 |

## 9. 검증 파이프라인

권장 실행 순서는 다음과 같다.

1. Python 3.11 환경에서 runtime 및 test 의존성 설치 후 Gateway 단위·API 테스트
2. Node.js 22에서 `npm ci`, lint, Web 단위 테스트, build
3. 짧은 Simulator step delay로 Gateway를 새로 실행하고 두 차량 `verify:pi`
4. 고정한 Flutter Stable 버전으로 `flutter test`, `flutter analyze`
5. QEMU ARM64 write-flow 검증
6. 실제 Mega·Uno 장비 HIL을 릴리스 게이트로 실행

현재 기준선에서는 Gateway 단위·API 테스트 26건, Python compileall, Web lint/build가 통과했다. 짧은 Simulator 지연으로 실행한 REST·WebSocket 통합 검증에서도 고객 차량 2대 등록, 1시간 차량 1번 배정, 4시간 이상 차량 6번 배정, 첫 차량 독립 출차, 두 번째 차량 `PARKED` 유지, 두 번째 차량 정리 출차, 최종 `activeJob=null`까지 통과했다. Flutter 소스는 정적 계약·구문 경계 검사를 마쳤지만 로컬에 Flutter/Dart SDK가 없어 `flutter test`와 `flutter analyze`는 실행하지 못했다. QEMU와 실제 Mega·Uno HIL은 릴리스 전 별도 검증 항목이다.

## 10. 완료 정의

다음 조건을 모두 만족하면 본 요구사항 구현을 완료한 것으로 판단한다.

- 모든 요구사항 ID가 구현 변경과 최소 하나의 수용 테스트에 연결된다.
- 모든 `미확정` 결정이 확정되거나 명시적으로 범위에서 제외된다.
- 첫 차량의 출차 없이 두 번째 차량을 주차할 수 있다.
- 차량별 입·출차 상태와 버튼이 서로 섞이지 않는다.
- Pi가 예상시간과 실제 빈자리 상태로 슬롯을 원자적으로 배정한다.
- Mega와 Uno의 정상·오류·단절 상태가 Web에 일관되게 반영된다.
- 로봇은 입·출차 후 대기 위치로 복귀하고 다음 요청을 받을 수 있다.
- 사용자 화면에 배정 기준, 배터리, 리프트 세부 상태가 노출되지 않는다.
- Web, Gateway, 공유 Flutter 계약, QEMU 및 실제 장비 검증 결과가 기록된다.
