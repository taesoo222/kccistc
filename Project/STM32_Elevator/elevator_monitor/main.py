"""
ELV Monitor · 승강기 원격 감시 시스템 (관제실 / 경비실용 PC 프로그램)

실행 : pip install pyserial customtkinter  →  python main.py

파일 구성 (모두 같은 폴더에 있어야 함)
  main.py      : 시작 파일 (이것만 실행)
  protocol.py  : 패킷 약속, 포트 자동 감지
  link.py      : 실제 보드 연결(SerialLink) / 데모(SimLink)
  settings.py  : 이름, 시간, 색, 글꼴 설정
  security.py  : 관리자 PIN 저장/확인
  ui.py        : 화면

데모 모드 키 : [E] 현장 비상 버튼, [P] 통신 끊기/잇기, [1][2][3] 호출
"""

import sys

try:
    import serial                   # noqa: F401  (pyserial 설치 확인용)
    import customtkinter            # noqa: F401
except ImportError as e:
    print(f"필요한 패키지가 없습니다 ({e.name}). 명령 프롬프트에서 실행 :  pip install pyserial customtkinter")
    sys.exit(1)

from ui import App


if __name__ == "__main__":
    app = App()
    app.bind("<Key>", app.on_key)
    app.mainloop()
