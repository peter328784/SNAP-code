라즈베리 파이 SSH 접속 방법
- Raspberry Pi Connect - Access your Raspberry Pi from anywhere – Raspberry Pi 
- 위 링크에서 raspberry pi imager 설치 
- SD 카드 읽은 후 정보 입력 후 기록
- → 호스트 : raspberrypi(선택)
- → 사용자 이름 : pi(선택)
- → 비밀번호 : snap(선택)
- → 와이파이 : 와이파이 이름 / 비밀번호
- SD 카드 다시 넣고 라즈베리파이 부팅 (1-2분)
  
  Powershell 열고 ssh pi@raspberrypi.local 입력 
- 뭐 물어보면 yes 입력하고 비밀번호 입력하기 
- 만약 hostname 못 읽어오면 2번부터 다시 해보기
  
  로컬 접속이 안되면 IP주소 ssh pi@192.168.0.95 로 접속
- UART 활성화 -> sudo raspi-config
- 설정 -> Serial Port, Login shell 사용안함, Serial Interface 사용
- sudo reboot
- UART 장치 확인 -> ls -l /dev/serial0
- 확인 정상 답변: /dev/serial0 -> ttyS0sudo raspi-config
- 파이썬 시리얼 라이브러리 설치	sudo apt install python3-serial -y
- 라즈베리 파이 전송코드 : nano parking_send.py
- 전체 코드:
<details>
<summary>코드 보기</summary>
import serial
import time

routes = {
    1: "LCPSBWB",
    2: "LWPSBCB",
    3: "LLCPSBWB",
    4: "LLWPSBCB",
    5: "LLLCPSBWB",
    6: "LLLWPSBCB",
}

ser = serial.Serial("/dev/serial0", 9600, timeout=1)

time.sleep(2)

parking_number = int(input("주차 번호 입력 (1~6): "))

if parking_number not in routes:
    print("잘못된 주차 번호입니다.")
else:
    route = routes[parking_number]

    ser.write((route + "\n").encode())

    print(f"{parking_number}번 경로 전송: {route}")

    while True:
        if ser.in_waiting:
            msg = ser.readline().decode(errors="ignore").strip()
            print(msg)

            if msg == "ROUTE_DONE":
                print("주차 완료!")
                break

ser.close()

</details>
- 코드 입력 후 저장 (Ctrl + O, Enter, Ctrl + X)

- 프로그램 실행 방법: **SSH에서**

- python3 parking_send.py 입력
