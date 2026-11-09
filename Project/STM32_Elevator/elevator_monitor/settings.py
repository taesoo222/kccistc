"""
settings.py : 바꾸기 쉬운 설정값 (이름, 시간, 색, 글꼴)

여기만 고치면 프로그램 전체에 반영됨
"""

from protocol import (
    DIR_DOWN, DIR_STOP, DIR_UP, ST_EMERGENCY, ST_IDLE, ST_INIT, ST_MOVING,
)

APP_NAME = "ELV Monitor"
APP_VER = "v1.0"
SITE_NAME = "KCCI 실습동"
CAR_NAME = "승강기 1호기"

RSP_TIMEOUT_S = 0.5
STATUS_POLL_MS = 300
BLINK_MS = 500
COMM_LOST_S = 2.0
ANIM_MS = 30
FLOORS = 3

# ---- 색 (다크 테마) ----
BG = "#0d1117"
SIDE = "#0a0d12"
CARD = "#161b22"
CARD2 = "#1c2230"
LINE = "#262c36"
TEXT = "#e6edf3"
SUB = "#8b949e"
MUTED = "#484f58"
ACCENT = "#2f81f7"
ACCENT_H = "#4b93f8"
OK = "#3fb950"
WARN = "#d29922"
DANGER = "#f85149"
DANGER_D = "#8e1f1a"

FONT = "Malgun Gothic"          # 윈도우 한글 글꼴 (없으면 기본 글꼴)
NUM = "Bahnschrift"             # 윈도우 숫자 글꼴 (계기판 느낌, 없으면 기본 글꼴)
MONO = "Consolas"

STATE_TEXT = {ST_INIT: "원점 복귀 중", ST_IDLE: "대기", ST_MOVING: "운행 중", ST_EMERGENCY: "비상 정지"}
STATE_COLOR = {ST_INIT: WARN, ST_IDLE: OK, ST_MOVING: ACCENT, ST_EMERGENCY: DANGER}
DIR_TEXT = {DIR_STOP: "정지", DIR_UP: "▲  상승", DIR_DOWN: "▼  하강"}
EMG_REASON = {1: "현장 비상 버튼", 2: "층 센서 못 찾음(시간 초과)", 3: "관제실 원격 정지", 4: "한계 위치 초과",
              5: "층 센서 건너뜀(센서 놓침)"}