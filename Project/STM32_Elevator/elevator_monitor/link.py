"""
link.py : 보드와 연결하는 통로 2가지 (사용법이 같아서 화면 코드는 어느 쪽인지 몰라도 됨)

SerialLink : 실제 보드 (시리얼 포트 + 수신 쓰레드)
SimLink    : 데모 모드 (보드 없이 가짜 승강기)
받은 패킷은 큐에 ("packet", cmd, payload) 로 넣어서 화면 쪽에 넘김
"""

import threading
import time

import serial

from protocol import (
    BAUDRATE, CMD_CALL_REQ, CMD_EMG_STOP_REQ, CMD_RELEASE_REQ, CMD_STATUS_REQ, DIR_DOWN, DIR_STOP,
    DIR_UP, EVT_ARRIVED, EVT_EMERGENCY, PacketParser, RSP_ERR, RSP_OFFSET, RSP_OK, ST_EMERGENCY,
    ST_IDLE, ST_MOVING,
)


class SerialLink:
    """실제 보드 : 시리얼 포트 + 수신 쓰레드 (받은 패킷은 큐로 GUI 에 전달)"""

    def __init__(self, out_queue):
        self.ser = None
        self.out = out_queue
        self.parser = PacketParser()
        self.running = False
        self.thread = None
        self.name = ""

    @property
    def is_open(self):
        return self.ser is not None and self.ser.is_open

    def open(self, port):
        self.close()
        self.ser = serial.Serial(port, BAUDRATE, timeout=0.1)
        self.ser.reset_input_buffer()
        self.parser.reset()
        self.name = port
        self.running = True
        self.thread = threading.Thread(target=self._rx_loop, daemon=True)
        self.thread.start()

    def close(self):
        self.running = False
        if self.thread is not None:
            self.thread.join(timeout=0.5)
            self.thread = None
        if self.ser is not None:
            try:
                self.ser.close()
            except serial.SerialException:
                pass
            self.ser = None

    def send(self, data):
        self.ser.write(data)

    def _rx_loop(self):
        while self.running:
            try:
                data = self.ser.read(self.ser.in_waiting or 1)
            except (serial.SerialException, OSError, TypeError, AttributeError) as e:
                self.out.put(("error", str(e)))
                break
            if not data:
                continue
            for cmd, payload in self.parser.feed_bytes(data):
                self.out.put(("packet", cmd, payload))


class SimLink:
    """데모 모드 : 보드 없이 가짜 승강기 (펌웨어 FSM 흉내). SerialLink 와 사용법 같음"""

    FLOOR_STEPS = 1000
    STEP_PER_TICK = 10          # 20ms 마다 10 스텝 → 한 층 2초

    def __init__(self, out_queue):
        self.out = out_queue
        self.parser = PacketParser()
        self.running = False
        self.thread = None
        self.lock = threading.Lock()
        self.name = "데모"
        self.paused = False         # True 면 응답 안 함 (USB 빠진 것처럼, 통신 끊김 테스트)

    @property
    def is_open(self):
        return self.running

    def open(self, _port=None):
        self.cur, self.state, self.dir, self.target = 1, ST_IDLE, DIR_STOP, 1
        self.pos, self.last_pos, self.calls = 0, 0, []
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def close(self):
        self.running = False

    def _reply(self, cmd, payload):
        self.out.put(("packet", cmd, bytes(payload)))

    def _emergency(self, reason):
        self.state = ST_EMERGENCY
        self.calls.clear()
        self._reply(EVT_EMERGENCY, [self.cur, self.dir, reason])

    def board_emergency(self):
        """데모용 : 보드 비상 버튼 누른 것처럼"""
        with self.lock:
            if self.state != ST_EMERGENCY:
                self._emergency(1)

    def send(self, data):
        time.sleep(0.01)
        if self.paused:
            return
        with self.lock:
            for cmd, pl in self.parser.feed_bytes(data):
                if cmd == CMD_CALL_REQ:
                    ok = self.state != ST_EMERGENCY and pl and 1 <= pl[0] <= 3
                    if ok:
                        self.calls.append(pl[0])
                    self._reply(cmd + RSP_OFFSET, [RSP_OK if ok else RSP_ERR])
                elif cmd == CMD_STATUS_REQ:
                    p = self.pos & 0xFFFF
                    fs = self.FLOOR_STEPS
                    self._reply(cmd + RSP_OFFSET,
                                [self.cur, self.state, self.dir, self.target, p >> 8, p & 0xFF, fs >> 8, fs & 0xFF])
                elif cmd == CMD_RELEASE_REQ:
                    ok = self.state == ST_EMERGENCY
                    self._reply(cmd + RSP_OFFSET, [RSP_OK if ok else RSP_ERR])
                    if ok:
                        diff = self.pos - self.last_pos
                        t = self.cur
                        if abs(diff) > self.FLOOR_STEPS // 2:
                            t = self.cur + (1 if diff > 0 else -1)
                        t = max(1, min(3, t))
                        self.target = t
                        goal = (t - 1) * self.FLOOR_STEPS
                        if self.pos == goal:
                            self.state, self.dir = ST_IDLE, DIR_STOP
                            self._reply(EVT_ARRIVED, [t])
                        else:
                            self.dir = DIR_UP if goal > self.pos else DIR_DOWN
                            self.state = ST_MOVING
                elif cmd == CMD_EMG_STOP_REQ:
                    ok = self.state != ST_EMERGENCY
                    if ok:
                        self._emergency(3)
                    self._reply(cmd + RSP_OFFSET, [RSP_OK if ok else RSP_ERR])

    def _run(self):
        while self.running:
            time.sleep(0.02)
            with self.lock:
                if self.state == ST_IDLE and self.calls:
                    f = self.calls.pop(0)
                    if f == self.cur:
                        self._reply(EVT_ARRIVED, [f])
                    else:
                        self.target = f
                        self.dir = DIR_UP if f > self.cur else DIR_DOWN
                        self.state = ST_MOVING
                elif self.state == ST_MOVING:
                    self.pos += self.STEP_PER_TICK if self.dir == DIR_UP else -self.STEP_PER_TICK
                    for f in (1, 2, 3):
                        if self.pos == (f - 1) * self.FLOOR_STEPS:
                            self.cur, self.last_pos = f, self.pos
                    if self.pos == (self.target - 1) * self.FLOOR_STEPS:
                        self.state, self.dir = ST_IDLE, DIR_STOP
                        self._reply(EVT_ARRIVED, [self.target])
