# Security policy

## 현재 보안 경계

이 저장소는 Web/Flutter 클라이언트와 Raspberry Pi Gateway 계약을 검증하는 프로토타입이다. 현재 Gateway에는 사용자 인증, 권한 분리, TLS가 없으며 메모리 기반 Simulator만 제공한다.

- 인터넷이나 공용 네트워크에 Gateway를 노출하지 않는다.
- 공유기 포트포워딩을 사용하지 않는다.
- 실제 차량 식별정보 대신 테스트 ID만 사용한다.
- `SNAP_CORS_ORIGINS`는 Web Mock을 실행하는 신뢰 Origin으로 제한한다.
- 실제 Arduino·센서·모터를 연결한 환경에는 현재 코드를 그대로 사용하지 않는다.

실제 하드웨어 연동 전에는 최소한 인증·권한 검사, HTTPS/WSS, WebSocket Origin 검사, 요청 중복 방지, 명령 만료, 비상정지와 물리 안전 계층을 별도로 구현하고 검증해야 한다.

## 민감정보

API 키, 비밀번호, 실제 `.env`, SSH 키, VM 이미지, 사용자·차량 개인정보를 커밋하지 않는다. 실수로 커밋했다면 파일만 삭제하지 말고 자격증명을 즉시 폐기한 뒤 Git 이력에서도 제거한다.

## 취약점 제보

공개 Issue에 민감한 재현정보를 게시하지 말고 GitHub의 비공개 Security Advisory 기능을 사용한다.
