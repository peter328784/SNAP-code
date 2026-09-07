# S.N.A.P Web Mock

모바일 우선 Web Mock이다. 주차·출차 전체 흐름을 시연하며, `SIMULATOR`와 `LIVE PI` 데이터 원본을 명시적으로 분리한다.

## 로컬 실행

Node.js 22.13 이상이 필요하다.

```bash
npm install
npm run dev
```

이 Mac에서는 `http://localhost:3101`로 연다. 같은 네트워크의 다른 컴퓨터에서도 열려면 저장소 루트에서 `tools/qemu/web-lan.sh`를 실행하고, 스크립트가 표시하는 `http://<이-Mac의-LAN-IP>:3101`로 연다. 이 명령은 Web Mock을 현재 사설 LAN IP 하나에만 바인딩한다.

Web Mock은 열린 페이지의 호스트명을 사용해 기본 Gateway를 `http://<같은-호스트>:8101`, WebSocket을 `ws://<같은-호스트>:8101/v1/events`로 자동 구성한다. 원격 컴퓨터에서는 `localhost`나 `127.0.0.1`을 Gateway 주소로 사용하지 않는다.

## 회의 시연 순서

1. `SIMULATOR`에서 차량 ID와 배정 기준을 선택한다.
2. `원터치 주차 요청`을 눌러 6단계 진행, 로봇 위치, 이벤트를 확인한다.
3. 완료 뒤 같은 버튼의 `원터치 출차 요청`으로 출차 흐름을 보여준다.
4. Pi Gateway가 실행 중이면 `LIVE PI`를 선택한다.
5. API 기본 주소에 `http://<pi-host>:8101`을 입력하고 `저장 후 연결`을 누른다.

## LIVE PI 계약

| 동작 | 주소 |
|---|---|
| Gateway 상태 | `GET /health` |
| Snapshot | `GET /v1/parking-lots/demo-01/snapshot` |
| 주차 요청 | `POST /v1/parking-requests` |
| 주차 요청 확정 | `POST /v1/parking-requests/{requestId}/confirm` |
| 작업 조회 | `GET /v1/jobs/{jobId}` |
| 출차 요청 | `POST /v1/retrieval-requests` |
| 실시간 이벤트 | WebSocket `/v1/events` |

화면에서 주소를 비우면 Web Mock과 같은 Origin의 `/v1`을 사용한다. 환경 변수로 초기값을 지정하려면 `.env.example`을 `.env.local`로 복사한다.

QEMU 환경의 LAN 공개·CORS·IP 변경 대응은 [QEMU 가상 보드 가이드](../docs/10-qemu-virtual-board.md)의 `같은 네트워크의 다른 컴퓨터에서 접속` 절을 따른다. 회의용 개발 서버와 Gateway에는 인증·TLS가 없으므로 신뢰하는 사설망에서만 실행하고 공유기 포트포워딩은 사용하지 않는다.

공개된 HTTPS 페이지에서 로컬 Pi의 HTTP 주소로 직접 연결하면 브라우저의 Mixed Content/사설망 정책에 막힐 수 있다. 실제 Pi 연동 시연은 Pi 또는 같은 Wi-Fi의 노트북에서 Web Mock을 HTTP로 실행하는 구성이 가장 단순하다.

## 검증

```bash
npm run lint
npm run build
```

Pi Gateway를 먼저 실행한 뒤 아래 명령으로 REST와 WebSocket 계약을 한 번에 확인할 수 있다.

```bash
npm run verify:pi
```

기본 대상은 `http://127.0.0.1:8101`이다. 다른 Raspberry Pi를 검증할 때는 주소를 인자로 전달한다.

```bash
npm run verify:pi -- --base-url http://snap-pi.local:8101
```

검증기는 `/health`, Snapshot, WebSocket 초기 이벤트를 항상 조회한다. `/health`의 `mode`가 `pi-simulator`일 때만 고유한 검증 차량으로 주차 → 출차 상태 전이를 실행하며, 실제 Gateway 모드에는 제어 명령을 보내지 않는다. Simulator에서도 읽기만 확인하려면 `--read-only`를 붙인다.

CI나 별도 셸에서는 `SNAP_PI_API_BASE_URL`, `SNAP_PI_WS_URL`, `SNAP_PI_TIMEOUT_MS` 환경 변수를 사용할 수 있다. 브라우저용 `.env.local`은 Node 검증기에 자동 로드되지 않으므로, 검증 명령에는 인자 또는 셸 환경 변수를 사용한다.
