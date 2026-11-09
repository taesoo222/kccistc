"""
protocol.py : 패킷 약속 (보드 펌웨어의 protocol.c 와 같은 규칙)

패킷 : [0xAA] [LEN] [CMD] [PAYLOAD ...] [CKSUM]
       LEN = 1(CMD) + payload 길이,  CKSUM = (LEN + CMD + PAYLOAD...) & 0xFF
       응답 CMD = 요청 CMD + 0x80

  요청 (PC -> 보드)               응답 (보드 -> PC)
   0x50 층 호출 [층 1~3]     ->   0xD0 [0=OK / 1=ERR]
   0x51 상태 요청             ->   0xD1 [현재층][상태][방향][목표층] (+ [위치H][위치L][한층스텝H][한층스텝L])
   0x41 비상 해제             ->   0xC1 [OK/ERR]
   0x43 PC 비상 정지          ->   0xC3 [OK/ERR]
  이벤트 (보드 -> PC)
   0x40 비상 정지 발생  [층][방향][원인 1=버튼 2=시간 초과 3=PC 5=센서 건너뜀]
   0x42 도착           [층]
"""

import serial.tools.list_ports

PKT_START = 0xAA
PKT_MAX_LEN = 16
BAUDRATE = 115200

CMD_CALL_REQ = 0x50
CMD_STATUS_REQ = 0x51
CMD_RELEASE_REQ = 0x41
CMD_EMG_STOP_REQ = 0x43
EVT_EMERGENCY = 0x40
EVT_ARRIVED = 0x42

RSP_OFFSET = 0x80
RSP_OK = 0x00
RSP_ERR = 0x01

ST_INIT, ST_IDLE, ST_MOVING, ST_EMERGENCY = range(4)
DIR_STOP, DIR_UP, DIR_DOWN = range(3)

STM_VID = 0x0483


def build_packet(cmd, payload=b""):
    body = bytes([cmd]) + bytes(payload)
    length = len(body)
    if length >= PKT_MAX_LEN:
        raise ValueError("payload 가 너무 김")
    cksum = (length + sum(body)) & 0xFF
    return bytes([PKT_START, length]) + body + bytes([cksum])


class PacketParser:
    """STM32 protocol.c 의 parse() 와 같은 상태머신"""

    WAIT_START, WAIT_LEN, WAIT_DATA, WAIT_CHK = range(4)

    def __init__(self):
        self.reset()

    def reset(self):
        self.state = self.WAIT_START
        self.length = 0
        self.buf = bytearray()

    def feed(self, byte):
        if self.state == self.WAIT_START:
            if byte == PKT_START:
                self.state = self.WAIT_LEN
        elif self.state == self.WAIT_LEN:
            if byte == 0 or byte >= PKT_MAX_LEN:
                self.state = self.WAIT_START
            else:
                self.length = byte
                self.buf = bytearray()
                self.state = self.WAIT_DATA
        elif self.state == self.WAIT_DATA:
            self.buf.append(byte)
            if len(self.buf) >= self.length:
                self.state = self.WAIT_CHK
        elif self.state == self.WAIT_CHK:
            self.state = self.WAIT_START
            if (self.length + sum(self.buf)) & 0xFF == byte:
                return self.buf[0], bytes(self.buf[1:])
        return None

    def feed_bytes(self, data):
        out = []
        for b in data:
            pkt = self.feed(b)
            if pkt is not None:
                out.append(pkt)
        return out


def list_ports():
    return [(p.device, p.description) for p in serial.tools.list_ports.comports()]


def find_stm32_port():
    for p in serial.tools.list_ports.comports():
        text = f"{p.description} {p.manufacturer} {p.product}".lower()
        if p.vid == STM_VID or "stlink" in text or "st-link" in text or "stmicro" in text:
            return p.device
    return None


def to_hex(data):
    return " ".join(f"{b:02X}" for b in data)
