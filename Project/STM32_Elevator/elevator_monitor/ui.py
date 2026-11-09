"""
ui.py : 화면 (메인 창, 승강로 그림, 관리자 인증 창)

화면 부품(card, button, Tile) → PinDialog(인증 창) → App(메인 창) 순서
"""

import queue
import time
import tkinter as tk
from collections import deque
from tkinter import ttk

import customtkinter as ctk
import serial

from protocol import (
    CMD_CALL_REQ, CMD_EMG_STOP_REQ, CMD_RELEASE_REQ, CMD_STATUS_REQ, DIR_DOWN, DIR_STOP, DIR_UP,
    EVT_ARRIVED, EVT_EMERGENCY, RSP_OFFSET, RSP_OK, ST_EMERGENCY, ST_IDLE, ST_MOVING, build_packet,
    find_stm32_port, list_ports, to_hex,
)
from link import (
    SerialLink, SimLink,
)
from settings import (
    ACCENT, ACCENT_H, ANIM_MS, APP_NAME, APP_VER, BG, BLINK_MS, CARD, CARD2, CAR_NAME, COMM_LOST_S,
    DANGER, DANGER_D, DIR_TEXT, EMG_REASON, FLOORS, FONT, LINE, MONO, MUTED, NUM, OK,
    RSP_TIMEOUT_S, SIDE, SITE_NAME, STATE_COLOR, STATE_TEXT, STATUS_POLL_MS, SUB, TEXT, WARN,
)
from security import (
    PIN_LOCK_S, PIN_MAX_FAIL, load_pin_record, pin_hash, save_pin,
)


def round_rect(cv, x0, y0, x1, y1, r, **kw):
    pts = [x0 + r, y0, x1 - r, y0, x1, y0, x1, y0 + r, x1, y1 - r, x1, y1,
           x1 - r, y1, x0 + r, y1, x0, y1, x0, y1 - r, x0, y0 + r, x0, y0]
    return cv.create_polygon(pts, smooth=True, **kw)


# ============================================================ 화면 부품
def card(master, **kw):
    return ctk.CTkFrame(master, fg_color=CARD, corner_radius=14, border_width=1, border_color=LINE, **kw)


def caption(master, text, **kw):
    return ctk.CTkLabel(master, text=text, text_color=SUB, font=(FONT, 12, "bold"), anchor="w", **kw)


def button(master, text, command, color=ACCENT, hover=None, height=40, size=13, **kw):
    return ctk.CTkButton(master, text=text, command=command, fg_color=color, hover_color=hover or color,
                         text_color="white", text_color_disabled=MUTED, corner_radius=10, height=height,
                         font=(FONT, size, "bold"), **kw)


class Tile(ctk.CTkFrame):
    """KPI 타일 : 제목 / 큰 값 / 아래 설명"""

    def __init__(self, master, title, value_font=(NUM, 34, "bold")):
        super().__init__(master, fg_color=CARD, corner_radius=14, border_width=1, border_color=LINE)
        caption(self, title).pack(fill="x", padx=18, pady=(12, 0))
        self.value = ctk.CTkLabel(self, text="--", text_color=TEXT, font=value_font, anchor="w")
        self.value.pack(fill="x", padx=18)
        self.sub = ctk.CTkLabel(self, text="", text_color=SUB, font=(FONT, 12), anchor="w")
        self.sub.pack(fill="x", padx=18, pady=(0, 12))


class PinDialog(ctk.CTkToplevel):
    """관리자 인증 / PIN 변경 창 (모달)

    fields : [(라벨, 키), ...]   on_ok : 함수(값 dict) → 오류 문구 or None(성공, 창 닫힘)
    check  : 체크박스 문구 (체크해야 확인 버튼 눌림), None 이면 없음
    """

    def __init__(self, app, title, message, fields, ok_text, on_ok, check=None, ok_color=ACCENT):
        super().__init__(app)
        self.app = app
        self.on_ok = on_ok
        self.ok_color = ok_color
        self.title(title)
        self.configure(fg_color=CARD)
        self.resizable(False, False)
        self.transient(app)

        ctk.CTkLabel(self, text="🔒  " + title, text_color=TEXT, font=(FONT, 17, "bold"), anchor="w").pack(
            fill="x", padx=26, pady=(22, 4))
        ctk.CTkLabel(self, text=message, text_color=SUB, font=(FONT, 12), justify="left", anchor="w",
                     wraplength=360).pack(fill="x", padx=26, pady=(0, 14))

        self.entries = {}
        for label, key in fields:
            ctk.CTkLabel(self, text=label, text_color=SUB, font=(FONT, 12), anchor="w").pack(fill="x", padx=26)
            e = ctk.CTkEntry(self, show="●", width=360, height=42, font=(MONO, 18), justify="center",
                             fg_color=BG, border_color=LINE, text_color=TEXT, corner_radius=10)
            e.pack(padx=26, pady=(4, 12))
            e.bind("<Return>", lambda _e: self.submit())
            self.entries[key] = e

        self.var_check = tk.BooleanVar(value=check is None)
        if check:
            ctk.CTkCheckBox(self, text=check, variable=self.var_check, command=self.update_ok, text_color=TEXT,
                            font=(FONT, 12), fg_color=OK, hover_color=OK, border_color=SUB,
                            corner_radius=6).pack(fill="x", padx=26, pady=(2, 4))

        self.lbl_err = ctk.CTkLabel(self, text="", text_color=DANGER, font=(FONT, 12, "bold"), anchor="w")
        self.lbl_err.pack(fill="x", padx=26, pady=(4, 0))

        row = ctk.CTkFrame(self, fg_color="transparent")
        row.pack(fill="x", padx=26, pady=(10, 24))
        self.btn_ok = button(row, ok_text, self.submit, color=ok_color, width=160)
        self.btn_ok.pack(side="right")
        button(row, "취소", self.destroy, color=CARD2, hover=LINE, width=90).pack(side="right", padx=8)

        self.update_ok()
        self.update_idletasks()
        x = app.winfo_rootx() + (app.winfo_width() - self.winfo_width()) // 2
        y = app.winfo_rooty() + (app.winfo_height() - self.winfo_height()) // 3
        self.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        self.after(150, self._grab)
        self.lock_tick()

    def _grab(self):
        try:
            self.grab_set()
            first = next(iter(self.entries.values()), None)
            if first is not None:
                first.focus_set()
        except tk.TclError:
            pass

    def update_ok(self):
        ok = self.var_check.get() and self.app.pin_locked_left() == 0
        self.btn_ok.configure(state="normal" if ok else "disabled", fg_color=self.ok_color if ok else CARD2)

    def lock_tick(self):
        if not self.winfo_exists():
            return
        left = self.app.pin_locked_left()
        for e in self.entries.values():
            e.configure(state="disabled" if left > 0 else "normal")
        if left > 0:
            self.lbl_err.configure(text=f"인증 {PIN_MAX_FAIL}회 실패 → {left}초 후 다시 시도")
        elif self.lbl_err.cget("text").startswith("인증"):
            self.lbl_err.configure(text="")
        self.update_ok()
        self.after(500, self.lock_tick)

    def submit(self):
        if self.btn_ok.cget("state") == "disabled":
            return
        values = {k: e.get().strip() for k, e in self.entries.items()}
        err = self.on_ok(values)
        if err:
            self.lbl_err.configure(text=err)
            for e in self.entries.values():
                e.delete(0, "end")
        else:
            self.destroy()


# ============================================================ 메인 창
class App(ctk.CTk):
    def __init__(self):
        super().__init__()
        ctk.set_appearance_mode("dark")
        self.title(f"{APP_NAME} · 승강기 원격 감시 시스템")
        self.configure(fg_color=BG)
        self.geometry("1040x920")
        self.minsize(960, 880)          # 960 보다 좁으면 통계 숫자/통신 타일 글자가 붙음

        self.rx_queue = queue.Queue()
        self.link = None
        self.tx_pending = deque()
        self.waiting = None

        self.cur = 0
        self.el_state = None
        self.dir = DIR_STOP
        self.target = 0
        self.calls = set()
        self.emergency = False
        self.alarm_acked = False
        self.emg_info = ""
        self.emg_started = None
        self.last_emg = None            # (발생 시각, 내용, 해제까지 걸린 초)
        self.blink = False

        self.pos = None
        self.floor_steps = 0
        self.car_level = 0.0
        self.last_status = 0.0
        self.comm_lost = False

        self.cnt_trip = 0
        self.cnt_emg = 0
        self.connected_at = None
        self.pin_salt, self.pin_hash, self.pin_default = load_pin_record()
        self.pin_fail = 0
        self.pin_lock_until = 0.0
        self.port_map = {}

        self._ttk_style()
        self._build()
        self.refresh_ports()
        self.update_display()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

        self.after(20, self.poll)
        self.after(STATUS_POLL_MS, self.auto_status)
        self.after(BLINK_MS, self.blink_tick)
        self.after(ANIM_MS, self.anim_tick)
        self.after(1000, self.clock_tick)
        self.after(400, self.auto_detect_connect)

    # ------------------------------------------------------------------ 표 스타일
    def _ttk_style(self):
        st = ttk.Style(self)
        st.theme_use("clam")
        st.configure("Log.Treeview", background=CARD, fieldbackground=CARD, foreground=TEXT, rowheight=30,
                     borderwidth=0, relief="flat", font=(FONT, 10))
        st.configure("Log.Treeview.Heading", background=CARD, foreground=SUB, relief="flat", borderwidth=0,
                     font=(FONT, 10, "bold"), padding=(8, 6))
        st.map("Log.Treeview", background=[("selected", "#1f3a5f")], foreground=[("selected", TEXT)])
        st.map("Log.Treeview.Heading", background=[("active", CARD)])
        st.layout("Log.Treeview", [("Treeview.treearea", {"sticky": "nswe"})])

    # ------------------------------------------------------------------ 화면 구성
    def _build(self):
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)
        self._build_sidebar()

        main = ctk.CTkFrame(self, fg_color=BG, corner_radius=0)
        main.grid(row=0, column=1, sticky="nsew")
        main.grid_columnconfigure(0, weight=1)
        main.grid_rowconfigure(3, weight=1, minsize=320)
        self.main = main

        # ---- 위 제목 줄 ----
        top = ctk.CTkFrame(main, fg_color="transparent")
        top.grid(row=0, column=0, sticky="ew", padx=28, pady=(18, 10))
        left = ctk.CTkFrame(top, fg_color="transparent")
        left.pack(side="left")
        ctk.CTkLabel(left, text=f"{SITE_NAME}  ›  {CAR_NAME}", text_color=SUB, font=(FONT, 12),
                     anchor="w").pack(anchor="w")
        ctk.CTkLabel(left, text="실시간 감시", text_color=TEXT, font=(FONT, 24, "bold"), anchor="w").pack(anchor="w")
        self.lbl_clock = ctk.CTkLabel(top, text="", text_color=TEXT, font=(NUM, 18))
        self.lbl_clock.pack(side="right")
        self.pill_link = ctk.CTkLabel(top, text="  ● 미연결  ", text_color=DANGER, fg_color=CARD, corner_radius=14,
                                      font=(FONT, 12, "bold"), height=30)
        self.pill_link.pack(side="right", padx=16)

        # ---- 비상 경보 띠 (평소엔 숨김) ----
        self.banner = ctk.CTkFrame(main, fg_color=DANGER, corner_radius=14)
        # 버튼을 글자보다 먼저 pack : 창이 좁으면 글자가 줄고 버튼은 안 찌그러짐
        self.btn_ack = button(self.banner, "경보음 확인", self.ack_alarm, color="#7a1a14", hover="#5e140f",
                              height=36, size=12, width=120)
        self.btn_ack.pack(side="right", padx=(6, 14))
        button(self.banner, "비상 해제", self.release, color="#1f7a3a", hover="#18602e", height=36, size=12,
               width=110).pack(side="right", padx=6)
        self.lbl_banner = ctk.CTkLabel(self.banner, text="", text_color="white", font=(FONT, 15, "bold"), anchor="w")
        self.lbl_banner.pack(side="left", fill="x", expand=True, padx=20, pady=12)

        # ---- KPI 타일 4개 ----
        kpi = ctk.CTkFrame(main, fg_color="transparent")
        kpi.grid(row=2, column=0, sticky="ew", padx=28, pady=(4, 12))
        for i in range(4):
            kpi.grid_columnconfigure(i, weight=1, uniform="k")
        self.t_floor = Tile(kpi, "현재 층", value_font=(NUM, 38, "bold"))
        self.t_state = Tile(kpi, "운행 상태", value_font=(FONT, 22, "bold"))
        self.t_dir = Tile(kpi, "방향 / 목표", value_font=(FONT, 22, "bold"))
        self.t_comm = Tile(kpi, "통신", value_font=(FONT, 22, "bold"))
        for i, t in enumerate((self.t_floor, self.t_state, self.t_dir, self.t_comm)):
            t.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 7, 0 if i == 3 else 7))

        # ---- 가운데 : 승강로 / 제어 ----
        mid = ctk.CTkFrame(main, fg_color="transparent")
        mid.grid(row=3, column=0, sticky="nsew", padx=28)
        mid.grid_columnconfigure(0, weight=5, uniform="m")
        mid.grid_columnconfigure(1, weight=4, uniform="m")
        mid.grid_columnconfigure(2, weight=5, uniform="m")
        mid.grid_rowconfigure(0, weight=1)

        c = card(mid)
        c.grid(row=0, column=0, sticky="nsew", padx=(0, 7))
        caption(c, "승강로").pack(fill="x", padx=18, pady=(14, 0))
        self.sv = tk.Canvas(c, bg=CARD, highlightthickness=0, height=300)
        self.sv.pack(fill="both", expand=True, padx=10, pady=(0, 12))
        self.sv.bind("<Configure>", lambda e: self._draw_shaft())

        c = card(mid)
        c.grid(row=0, column=1, sticky="nsew", padx=7)
        caption(c, "원격 호출").pack(fill="x", padx=18, pady=(14, 8))
        self.call_btn = {}
        for f in (3, 2, 1):
            b = button(c, f"{f}F", lambda k=f: self.call(k), color=CARD2, hover=LINE, height=58, size=20)
            b.pack(fill="x", padx=18, pady=5)
            self.call_btn[f] = b
        self.lbl_call_hint = ctk.CTkLabel(c, text="", text_color=SUB, font=(FONT, 11))
        self.lbl_call_hint.pack(fill="x", padx=18, pady=(4, 12))

        c = card(mid)
        c.grid(row=0, column=2, sticky="nsew", padx=(7, 0))
        caption(c, "비상 제어").pack(fill="x", padx=18, pady=(14, 8))
        button(c, "비상 정지", self.emg_stop, color=DANGER, hover="#d93a33", height=46, size=15).pack(
            fill="x", padx=18, pady=5)
        self.btn_release = button(c, "비상 해제  ·  관리자 인증", self.release, color="#1f7a3a", hover="#18602e",
                                  height=46, size=14)
        self.btn_release.pack(fill="x", padx=18, pady=5)
        ctk.CTkFrame(c, fg_color=LINE, height=1).pack(fill="x", padx=18, pady=(10, 8))
        caption(c, "최근 비상").pack(fill="x", padx=18)
        self.lbl_last_emg = ctk.CTkLabel(c, text="기록 없음", text_color=SUB, font=(FONT, 12), justify="left",
                                         anchor="w")
        self.lbl_last_emg.pack(fill="x", padx=18, pady=(2, 8))
        stat = ctk.CTkFrame(c, fg_color="transparent")
        stat.pack(fill="x", padx=18, pady=(4, 14))
        self.stat = {}
        for i, (key, name) in enumerate((("trip", "오늘 운행"), ("emg", "비상 발생"), ("time", "연결 시간"))):
            stat.grid_columnconfigure(i, weight=1)
            f = ctk.CTkFrame(stat, fg_color="transparent")
            f.grid(row=0, column=i, sticky="w")
            ctk.CTkLabel(f, text=name, text_color=SUB, font=(FONT, 11), anchor="w").pack(anchor="w")
            self.stat[key] = ctk.CTkLabel(f, text="0", text_color=TEXT, font=(NUM, 20, "bold"), anchor="w")
            self.stat[key].pack(anchor="w")

        # ---- 아래 : 로그 ----
        c = card(main)
        c.grid(row=4, column=0, sticky="nsew", padx=28, pady=(14, 20))
        tabs = ctk.CTkTabview(c, fg_color=CARD, segmented_button_fg_color=CARD2,
                              segmented_button_selected_color=ACCENT, segmented_button_selected_hover_color=ACCENT_H,
                              segmented_button_unselected_color=CARD2, segmented_button_unselected_hover_color=LINE,
                              text_color=TEXT, height=170, corner_radius=12, anchor="nw")
        tabs.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        t_evt = tabs.add("이벤트")
        t_raw = tabs.add("통신 로그")
        self.tree = ttk.Treeview(t_evt, columns=("time", "level", "msg"), show="headings", style="Log.Treeview",
                                 height=4)
        for col, name, w, anc in (("time", "시각", 100, "center"), ("level", "구분", 90, "center"),
                                  ("msg", "내용", 700, "w")):
            self.tree.heading(col, text=name, anchor=anc)
            self.tree.column(col, width=w, anchor=anc, stretch=(col == "msg"))
        self.tree.tag_configure("정보", foreground=TEXT)
        self.tree.tag_configure("운행", foreground="#79c0ff")
        self.tree.tag_configure("경고", foreground=WARN)
        self.tree.tag_configure("비상", foreground="white", background="#4c1d1b")
        sb = ctk.CTkScrollbar(t_evt, command=self.tree.yview, fg_color=CARD, button_color=LINE,
                              button_hover_color=MUTED)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="left", fill="y")
        self.txt_raw = ctk.CTkTextbox(t_raw, fg_color=CARD, text_color=SUB, font=(MONO, 12), state="disabled",
                                      corner_radius=8)
        self.txt_raw.pack(fill="both", expand=True)

    def _build_sidebar(self):
        side = ctk.CTkFrame(self, fg_color=SIDE, corner_radius=0, width=250)
        side.grid(row=0, column=0, sticky="nsw")
        side.grid_propagate(False)
        side.pack_propagate(False)

        logo = ctk.CTkFrame(side, fg_color="transparent")
        logo.pack(fill="x", padx=22, pady=(26, 28))
        ctk.CTkLabel(logo, text="⬢", text_color=ACCENT, font=(FONT, 26)).pack(side="left")
        col = ctk.CTkFrame(logo, fg_color="transparent")
        col.pack(side="left", padx=10)
        ctk.CTkLabel(col, text=APP_NAME, text_color=TEXT, font=(FONT, 17, "bold"), anchor="w").pack(anchor="w")
        ctk.CTkLabel(col, text="승강기 원격 감시", text_color=SUB, font=(FONT, 11), anchor="w").pack(anchor="w")

        caption(side, "장치").pack(fill="x", padx=22)
        dev = ctk.CTkFrame(side, fg_color=CARD, corner_radius=10, border_width=1, border_color=ACCENT)
        dev.pack(fill="x", padx=16, pady=(6, 0))
        self.dev_dot = ctk.CTkLabel(dev, text="●", text_color=MUTED, font=(FONT, 14))
        self.dev_dot.pack(side="left", padx=(12, 6), pady=10)
        ctk.CTkLabel(dev, text=CAR_NAME, text_color=TEXT, font=(FONT, 13, "bold")).pack(side="left")
        self.dev_floor = ctk.CTkLabel(dev, text="--", text_color=SUB, font=(NUM, 14, "bold"))
        self.dev_floor.pack(side="right", padx=12)

        # 아래쪽 : 연결 / 설정
        bottom = ctk.CTkFrame(side, fg_color="transparent")
        bottom.pack(side="bottom", fill="x", padx=16, pady=20)
        caption(bottom, "연결").pack(fill="x", padx=6, pady=(0, 6))
        self.opt_port = ctk.CTkOptionMenu(bottom, values=["(포트 없음)"], fg_color=CARD2, button_color=LINE,
                                          button_hover_color=MUTED, dropdown_fg_color=CARD2, text_color=TEXT,
                                          font=(FONT, 12), dropdown_font=(FONT, 12), corner_radius=10, height=36,
                                          dynamic_resizing=False)
        self.opt_port.pack(fill="x", pady=3)
        row = ctk.CTkFrame(bottom, fg_color="transparent")
        row.pack(fill="x", pady=3)
        self.btn_conn = button(row, "연결", self.toggle_connect, height=36, size=12, width=130, hover=ACCENT_H)
        self.btn_conn.pack(side="left", fill="x", expand=True)
        button(row, "↻", self.refresh_ports, color=CARD2, hover=LINE, height=36, size=14, width=44).pack(
            side="left", padx=(6, 0))
        button(bottom, "데모 모드", self.toggle_demo, color="#3b2f63", hover="#4a3b7d", height=36, size=12).pack(
            fill="x", pady=3)
        ctk.CTkFrame(bottom, fg_color=LINE, height=1).pack(fill="x", pady=12)
        button(bottom, "🔒  관리자 PIN 변경", self.change_pin_dialog, color=CARD2, hover=LINE, height=36,
               size=12).pack(fill="x", pady=3)
        self.lbl_hint = ctk.CTkLabel(bottom, text="", text_color=SUB, font=(FONT, 10), justify="left", anchor="w",
                                     wraplength=210)
        self.lbl_hint.pack(fill="x", pady=(10, 0))
        ctk.CTkLabel(bottom, text=f"{APP_NAME} {APP_VER}", text_color=MUTED, font=(FONT, 10), anchor="w").pack(
            fill="x", pady=(6, 0))

    # ------------------------------------------------------------------ 승강로 그림
    def _shaft_geom(self):
        w = max(self.sv.winfo_width(), 260)
        h = max(self.sv.winfo_height(), 260)
        car_h = min(84, (h - 70) / 3.4)
        return w, h, w / 2 + 10, 34, h - 30, 86, car_h

    def level_y(self, level):
        w, h, x, top, bot, car_w, car_h = self._shaft_geom()
        return bot - level / (FLOORS - 1) * (bot - top - car_h)

    def _draw_shaft(self):
        sv = self.sv
        sv.delete("all")
        w, h, x, top, bot, car_w, car_h = self._shaft_geom()
        half = car_w / 2 + 14
        round_rect(sv, x - half, top - 16, x + half, bot + 6, 14, fill=BG, outline=LINE)
        for rx in (x - half + 8, x + half - 8):                    # 레일
            sv.create_line(rx, top - 6, rx, bot, fill="#1f2630", width=3)
        sv.create_oval(x - 8, top - 12, x + 8, top + 4, fill=CARD2, outline=MUTED)
        self.hall_lamp = {}
        self.floor_pill = {}
        for f in range(1, FLOORS + 1):
            y = self.level_y(f - 1)
            yc = y - car_h / 2
            sv.create_line(x - half, y, x + half, y, fill=LINE, width=1, dash=(3, 3))
            px = x - half - 18
            self.floor_pill[f] = round_rect(sv, px - 44, yc - 15, px, yc + 15, 10, fill=CARD2, outline="")
            sv.create_text(px - 22, yc, text=f"{f}F", fill=TEXT, font=(NUM, 13, "bold"))
            self.hall_lamp[f] = sv.create_oval(x + half + 14, yc - 6, x + half + 26, yc + 6, fill=CARD2, outline=LINE)
        self.rope = sv.create_line(x, top - 4, x, top, fill=MUTED, width=2)
        self.car = round_rect(sv, 0, 0, 1, 1, 10, fill=ACCENT, outline="")
        self.car_hi = sv.create_rectangle(0, 0, 1, 1, fill="", outline="")
        self.car_door = sv.create_line(0, 0, 1, 1, fill="#ffffff", width=1)
        self.car_text = sv.create_text(0, 0, text="", fill="white", font=(NUM, 16, "bold"))
        self.shaft_info = sv.create_text(x, h - 10, text="", fill=SUB, font=(FONT, 9))
        self.draw_car()

    def draw_car(self):
        if not hasattr(self, "car"):
            return
        sv = self.sv
        w, h, x, top, bot, car_w, car_h = self._shaft_geom()
        lv = max(-0.1, min(FLOORS - 1 + 0.1, self.car_level))
        yb = self.level_y(lv)
        yt = yb - car_h
        live = self.is_live()
        if not live or self.el_state is None:
            color, label = MUTED, "--"
        elif self.emergency:
            color, label = DANGER if self.blink else DANGER_D, "비상"
        else:
            color, label = STATE_COLOR.get(self.el_state, ACCENT), f"{self.cur}F" if self.cur else "?"
        sv.delete(self.car)
        self.car = round_rect(sv, x - car_w / 2, yt, x + car_w / 2, yb, 10, fill=color, outline="")
        sv.coords(self.car_door, x, yt + 30, x, yb - 6)
        sv.itemconfigure(self.car_door, fill="#ffffff" if live else MUTED)
        sv.coords(self.car_text, x, yt + 14)
        sv.itemconfigure(self.car_text, text=label, font=(NUM if label != "비상" else FONT, 13, "bold"))
        sv.tag_raise(self.car_door)
        sv.tag_raise(self.car_text)
        sv.coords(self.rope, x, top - 4, x, yt)
        for f, lamp in self.hall_lamp.items():
            on = f in self.calls
            sv.itemconfigure(lamp, fill=WARN if on else CARD2, outline=WARN if on else LINE)
            here = live and self.cur == f and not self.emergency and self.el_state == ST_IDLE
            sv.itemconfigure(self.floor_pill[f], fill=OK if here else CARD2)
        if self.pos is not None and self.floor_steps:
            info = f"{'마지막 ' if self.comm_lost else ''}위치 {self.pos} / {self.floor_steps * (FLOORS - 1)} 스텝"
        elif live:
            info = "위치 정보 없음 · 층 기준 표시"
        else:
            info = ""
        sv.itemconfigure(self.shaft_info, text=info)

    def target_level(self):
        if self.pos is not None and self.floor_steps:
            return self.pos / self.floor_steps
        if not self.cur:
            return self.car_level
        base = self.cur - 1
        if self.el_state == ST_MOVING and self.dir == DIR_UP:
            return min(base + 0.5, FLOORS - 1)
        if self.el_state == ST_MOVING and self.dir == DIR_DOWN:
            return max(base - 0.5, 0)
        return base

    def anim_tick(self):
        goal = self.target_level()
        d = goal - self.car_level
        self.car_level = goal if abs(d) < 0.003 else self.car_level + d * 0.25
        self.draw_car()
        self.after(ANIM_MS, self.anim_tick)

    # ------------------------------------------------------------------ 표시 갱신
    def is_connected(self):
        return self.link is not None and self.link.is_open

    def is_live(self):
        return self.is_connected() and not self.comm_lost

    def update_display(self):
        connected = self.is_connected()
        live = self.is_live() and self.el_state is not None

        # 연결 표시
        if not connected:
            self.pill_link.configure(text="  ● 미연결  ", text_color=DANGER)
            self.dev_dot.configure(text_color=MUTED)
        elif self.comm_lost:
            self.pill_link.configure(text=f"  ● {self.link.name} · 응답 없음  ", text_color=WARN)
            self.dev_dot.configure(text_color=WARN)
        else:
            self.pill_link.configure(text=f"  ● {self.link.name} · 연결됨  ", text_color=OK)
            self.dev_dot.configure(text_color=DANGER if self.emergency else OK)

        # 현재 층
        if live:
            self.t_floor.value.configure(text=f"{self.cur}F" if self.cur else "?F",
                                         text_color=DANGER if self.emergency else TEXT)
            self.t_floor.sub.configure(text=f"{FLOORS}개 층 운행")
            self.dev_floor.configure(text=f"{self.cur}F" if self.cur else "?F")
        else:
            self.t_floor.value.configure(text="--", text_color=MUTED)
            self.t_floor.sub.configure(text="데이터 없음")
            self.dev_floor.configure(text="--")

        # 운행 상태
        if not connected:
            self.t_state.value.configure(text="미연결", text_color=MUTED)
            self.t_state.sub.configure(text="포트 연결 또는 데모 모드")
        elif self.comm_lost:
            self.t_state.value.configure(text="알 수 없음", text_color=WARN)
            self.t_state.sub.configure(text="통신 끊김")
        elif self.el_state is None:
            self.t_state.value.configure(text="응답 대기", text_color=SUB)
            self.t_state.sub.configure(text="")
        else:
            col = STATE_COLOR.get(self.el_state, TEXT)
            if self.emergency and not self.blink:
                col = DANGER_D
            self.t_state.value.configure(text=STATE_TEXT.get(self.el_state, "?"), text_color=col)
            self.t_state.sub.configure(text="현장 안전 확인 필요" if self.emergency else "정상 운행")

        # 방향 / 목표
        if live and not self.emergency:
            self.t_dir.value.configure(text=DIR_TEXT.get(self.dir, "-"),
                                       text_color=ACCENT if self.dir != DIR_STOP else TEXT)
            self.t_dir.sub.configure(text=f"목표 {self.target}F" if self.el_state == ST_MOVING else "대기 중")
        else:
            self.t_dir.value.configure(text="-", text_color=MUTED)
            self.t_dir.sub.configure(text="")

        # 통신
        if not connected:
            self.t_comm.value.configure(text="오프라인", text_color=MUTED)
        elif self.comm_lost:
            self.t_comm.value.configure(text="끊김", text_color=WARN)
        else:
            self.t_comm.value.configure(text="정상", text_color=OK)

        # 호출 버튼
        for f, b in self.call_btn.items():
            if not live or self.emergency:
                b.configure(state="disabled", fg_color=CARD2, text=f"{f}F")
            elif f in self.calls:
                b.configure(state="normal", fg_color=WARN, hover_color=WARN, text=f"{f}F  ·  호출됨")
            else:
                b.configure(state="normal", fg_color=CARD2, hover_color=LINE, text=f"{f}F")
        if not connected:
            self.lbl_call_hint.configure(text="제어기 연결 후 사용 가능")
        elif self.emergency:
            self.lbl_call_hint.configure(text="비상 정지 중에는 호출할 수 없습니다")
        else:
            self.lbl_call_hint.configure(text="층을 누르면 원격 호출")
        self.btn_release.configure(state="normal" if self.emergency else "disabled",
                                   fg_color="#1f7a3a" if self.emergency else CARD2)

        # 비상 경보 띠
        if self.emergency:
            if not self.banner.winfo_ismapped():
                self.banner.grid(row=1, column=0, sticky="ew", padx=28, pady=(0, 10))
            col = DANGER if (self.blink or self.alarm_acked) else DANGER_D
            self.banner.configure(fg_color=col)
            self.lbl_banner.configure(text=f"⚠   비상 정지 발생   ·   {self.emg_info}")
            self.btn_ack.configure(text="경보음 꺼짐" if self.alarm_acked else "경보음 확인")
        elif self.banner.winfo_ismapped():
            self.banner.grid_forget()

        # 통계 / 최근 비상
        self.stat["trip"].configure(text=str(self.cnt_trip))
        self.stat["emg"].configure(text=str(self.cnt_emg), text_color=DANGER if self.cnt_emg else TEXT)
        if self.last_emg:
            t, info, dur = self.last_emg
            tail = f"해제까지 {dur:.0f}초" if dur is not None else "해제 대기 중"
            self.lbl_last_emg.configure(text=f"{info}\n{t}  ·  {tail}", text_color=TEXT)  # 좁은 창에서도 2줄

    def blink_tick(self):
        self.blink = not self.blink
        if self.emergency and not self.alarm_acked and self.blink:
            beep(self)
        self.update_display()
        self.after(BLINK_MS, self.blink_tick)

    def clock_tick(self):
        self.lbl_clock.configure(text=time.strftime("%Y.%m.%d  %H:%M:%S"))
        if self.is_connected():
            ago = time.monotonic() - self.last_status
            self.t_comm.sub.configure(text=f"마지막 수신 {ago:.1f}초 전")
            el = int(time.monotonic() - self.connected_at)
            self.stat["time"].configure(text=f"{el // 3600:02d}:{el % 3600 // 60:02d}:{el % 60:02d}")
        else:
            self.t_comm.sub.configure(text="")
            self.stat["time"].configure(text="00:00:00")
        self.after(1000, self.clock_tick)

    # ------------------------------------------------------------------ 연결
    def refresh_ports(self):
        ports = list_ports()
        self.port_map = {f"{dev}  {desc}": dev for dev, desc in ports}
        values = list(self.port_map.keys()) or ["(포트 없음)"]
        self.opt_port.configure(values=values)
        if self.opt_port.get() not in values:
            self.opt_port.set(values[0])

    def auto_detect_connect(self):
        if self.is_connected():
            return
        self.refresh_ports()
        dev = find_stm32_port()
        if dev is None:
            self.event("정보", "자동 감지 : 승강기 제어기(Nucleo) 포트를 찾지 못함 → 포트 선택 또는 데모 모드")
            return
        for label, d in self.port_map.items():
            if d == dev:
                self.opt_port.set(label)
        self.connect(SerialLink(self.rx_queue), dev)

    def toggle_connect(self):
        if self.is_connected():
            self.disconnect()
            return
        dev = self.port_map.get(self.opt_port.get())
        if dev:
            self.connect(SerialLink(self.rx_queue), dev)

    def toggle_demo(self):
        if self.is_connected():
            self.disconnect()
        self.connect(SimLink(self.rx_queue), None)

    def connect(self, link, dev):
        try:
            link.open(dev)
        except serial.SerialException as e:
            self.event("경고", f"연결 실패 : {e} (다른 프로그램이 포트를 쓰고 있으면 닫기)")
            return
        self.link = link
        self.tx_pending.clear()
        self.waiting = None
        self.el_state = None
        self.calls.clear()
        self.emergency = False
        self.pos = None
        self.comm_lost = False
        self.last_status = time.monotonic()
        self.connected_at = time.monotonic()
        self.btn_conn.configure(text="연결 끊기", fg_color=CARD2, hover_color=LINE)
        self.event("정보", f"제어기 연결 : {link.name}")
        if isinstance(link, SimLink):
            self.lbl_hint.configure(text="데모 키 : [E] 현장 비상 버튼\n[P] 통신 끊기/잇기  [1][2][3] 호출")
        self.update_display()

    def disconnect(self, reason=None):
        if self.link is not None:
            self.link.close()
            self.event("경고" if reason else "정보", "연결 해제" + (f" : {reason}" if reason else ""))
        self.link = None
        self.tx_pending.clear()
        self.waiting = None
        self.el_state = None
        self.emergency = False
        self.calls.clear()
        self.pos = None
        self.comm_lost = False
        self.btn_conn.configure(text="연결", fg_color=ACCENT, hover_color=ACCENT_H)
        self.lbl_hint.configure(text="")
        self.update_display()

    # ------------------------------------------------------------------ 요청
    def request(self, cmd, payload=b"", unique=False, quiet=False):
        if not self.is_connected():
            if not quiet:
                self.event("경고", "제어기가 연결되지 않았음")
            return
        if unique:
            if self.waiting and self.waiting[0] == cmd + RSP_OFFSET:
                return
            if any(c == cmd for c, _ in self.tx_pending):
                return
        self.tx_pending.append((cmd, bytes(payload)))

    def call(self, floor):
        if self.emergency:
            return
        self.request(CMD_CALL_REQ, [floor])

    def emg_stop(self):
        self.request(CMD_EMG_STOP_REQ)

    # ---------------- 관리자 인증 ----------------
    def pin_locked_left(self):
        return max(0, int(self.pin_lock_until - time.monotonic() + 0.999))

    def check_pin(self, pin, purpose):
        """맞으면 True. 틀리면 실패 횟수 올리고, 3번이면 잠금"""
        if pin_hash(pin, self.pin_salt) == self.pin_hash:
            self.pin_fail = 0
            return True
        self.pin_fail += 1
        if self.pin_fail >= PIN_MAX_FAIL:
            self.pin_fail = 0
            self.pin_lock_until = time.monotonic() + PIN_LOCK_S
            self.event("경고", f"관리자 인증 {PIN_MAX_FAIL}회 실패 ({purpose}) → {PIN_LOCK_S}초 잠금")
        else:
            self.event("경고", f"관리자 인증 실패 ({purpose}) {self.pin_fail}/{PIN_MAX_FAIL}")
        return False

    def release(self):
        """비상 해제 : 관리자 PIN + 현장 안전 확인 → 해제 명령"""
        if not self.emergency:
            self.event("경고", "비상 정지 상태가 아님")
            return
        if not self.is_live():
            self.event("경고", "제어기와 통신이 안 돼서 해제할 수 없음")
            return

        def ok(values):
            if self.pin_locked_left() > 0:
                return f"잠금 중 ({self.pin_locked_left()}초)"
            if not self.check_pin(values["pin"], "비상 해제"):
                left = PIN_MAX_FAIL - self.pin_fail
                return "PIN 이 틀렸습니다" + (f" (남은 시도 {left}회)" if self.pin_locked_left() == 0 else "")
            self.event("정보", "관리자 인증 성공 → 비상 해제 요청")
            self.request(CMD_RELEASE_REQ)
            return None

        hint = "  (처음 PIN : 1234)" if self.pin_default else ""
        PinDialog(self, "관리자 인증 · 비상 해제",
                  f"비상 정지를 해제하면 승강기가 1층으로 원점 복귀합니다.{hint}",
                  [("관리자 PIN", "pin")], "비상 해제", ok,
                  check="현장 안전(갇힌 사람, 문, 승강로 주변)을 확인했습니다", ok_color="#1e8449")

    def change_pin_dialog(self):
        def ok(values):
            if self.pin_locked_left() > 0:
                return f"잠금 중 ({self.pin_locked_left()}초)"
            if not self.check_pin(values["old"], "PIN 변경"):
                return "현재 PIN 이 틀렸습니다"
            new, new2 = values["new"], values["new2"]
            if not (new.isdigit() and 4 <= len(new) <= 6):
                return "새 PIN 은 숫자 4~6자리"
            if new != new2:
                return "새 PIN 두 칸이 서로 다릅니다"
            try:
                self.pin_salt, self.pin_hash = save_pin(new)
            except OSError as e:
                return f"저장 실패 : {e}"
            self.pin_default = False
            self.event("정보", "관리자 PIN 변경됨")
            return None

        hint = "처음 PIN 은 1234 입니다. " if self.pin_default else ""
        PinDialog(self, "관리자 PIN 변경",
                  f"{hint}새 PIN 은 숫자 4~6자리.\n잊어버리면 monitor_config.json 을 지우면 1234 로 돌아갑니다.",
                  [("현재 PIN", "old"), ("새 PIN", "new"), ("새 PIN 확인", "new2")], "변경", ok)

    def ack_alarm(self):
        if self.emergency and not self.alarm_acked:
            self.alarm_acked = True
            self.event("정보", "관제실 경보음 확인 (비상 상태 유지)")
            self.update_display()

    def auto_status(self):
        self.request(CMD_STATUS_REQ, unique=True, quiet=True)
        self.after(STATUS_POLL_MS, self.auto_status)

    # ------------------------------------------------------------------ 주기 처리
    def poll(self):
        while True:
            try:
                item = self.rx_queue.get_nowait()
            except queue.Empty:
                break
            if item[0] == "packet":
                if item[1] != CMD_STATUS_REQ + RSP_OFFSET:
                    self.raw("RX  " + to_hex(build_packet(item[1], item[2])))
                self.handle_packet(item[1], item[2])
            elif item[0] == "error":
                self.disconnect(f"포트 오류 ({item[1]})")

        if self.waiting and time.monotonic() > self.waiting[1]:
            if self.waiting[0] != CMD_STATUS_REQ + RSP_OFFSET:
                self.raw(f"응답 없음 (0x{self.waiting[0]:02X})")
            self.waiting = None

        if self.is_connected() and not self.comm_lost and time.monotonic() - self.last_status > COMM_LOST_S:
            self.comm_lost = True
            self.event("경고", f"통신 끊김 : {COMM_LOST_S:.0f}초 이상 응답 없음 (제어기 전원 / USB 확인)")
            self.update_display()

        if self.is_connected() and self.waiting is None and self.tx_pending:
            cmd, payload = self.tx_pending.popleft()
            pkt = build_packet(cmd, payload)
            self.waiting = (cmd + RSP_OFFSET, time.monotonic() + RSP_TIMEOUT_S, payload)
            try:
                self.link.send(pkt)
            except serial.SerialException as e:
                self.disconnect(f"전송 실패 ({e})")
            else:
                if cmd != CMD_STATUS_REQ:
                    self.raw("TX  " + to_hex(pkt))

        self.after(20, self.poll)

    def handle_packet(self, cmd, payload):
        sent = b""
        if self.waiting and cmd == self.waiting[0]:
            sent = self.waiting[2]
            self.waiting = None
        ok = bool(payload) and payload[0] == RSP_OK

        if cmd == CMD_STATUS_REQ + RSP_OFFSET and len(payload) >= 4:
            self.last_status = time.monotonic()
            if self.comm_lost:
                self.comm_lost = False
                self.event("정보", "통신 복구")
            self.cur, self.el_state, self.dir, self.target = payload[:4]
            if len(payload) >= 8:
                pos = (payload[4] << 8) | payload[5]
                self.pos = pos - 0x10000 if pos >= 0x8000 else pos
                self.floor_steps = (payload[6] << 8) | payload[7]
            else:
                self.pos = None
            if (self.el_state == ST_EMERGENCY) != self.emergency:
                self.set_emergency(self.el_state == ST_EMERGENCY, "상태 확인으로 감지")
            if self.el_state == ST_IDLE:
                self.calls.discard(self.cur)

        elif cmd == CMD_CALL_REQ + RSP_OFFSET:
            floor = sent[0] if sent else 0
            if ok:
                self.calls.add(floor)
                self.event("운행", f"{floor}층 원격 호출")
            else:
                self.event("경고", f"{floor}층 호출 거부")

        elif cmd == CMD_RELEASE_REQ + RSP_OFFSET:
            if ok:
                self.event("정보", "비상 해제 → 1층으로 원점 복귀")
                self.set_emergency(False)
            else:
                self.event("경고", "비상 해제 실패 (비상 상태 아님)")

        elif cmd == CMD_EMG_STOP_REQ + RSP_OFFSET:
            if not ok:
                self.event("경고", "이미 비상 정지 상태")

        elif cmd == EVT_EMERGENCY and len(payload) >= 3:
            reason = EMG_REASON.get(payload[2], f"원인 {payload[2]}")
            self.set_emergency(True, f"{payload[0]}층 부근 · {reason} · {time.strftime('%H:%M:%S')}")

        elif cmd == EVT_ARRIVED and len(payload) >= 1:
            self.calls.discard(payload[0])
            self.cur = payload[0]
            self.dir = DIR_STOP
            self.cnt_trip += 1
            self.event("운행", f"{payload[0]}층 도착")

        self.update_display()

    def set_emergency(self, on, info=""):
        if on and not self.emergency:
            self.cnt_emg += 1
            self.alarm_acked = False
            self.emg_info = info
            self.emg_started = time.monotonic()
            short = " · ".join(info.split(" · ")[:2])          # "2층 부근 · 현장 비상 버튼"
            self.last_emg = (time.strftime("%H:%M:%S"), short, None)
            self.calls.clear()
            self.event("비상", f"비상 정지 발생 : {info}")
        elif not on and self.emergency and self.last_emg and self.emg_started:
            t, i, _ = self.last_emg
            self.last_emg = (t, i, time.monotonic() - self.emg_started)
        self.emergency = on
        self.update_display()

    # ------------------------------------------------------------------ 기록
    def event(self, level, msg):
        self.tree.insert("", 0, values=(time.strftime("%H:%M:%S"), level, msg), tags=(level,))
        items = self.tree.get_children()
        for it in items[300:]:
            self.tree.delete(it)

    def raw(self, msg):
        self.txt_raw.configure(state="normal")
        self.txt_raw.insert("end", time.strftime("[%H:%M:%S]  ") + msg + "\n")
        if int(self.txt_raw.index("end-1c").split(".")[0]) > 500:
            self.txt_raw.delete("1.0", "100.0")
        self.txt_raw.see("end")
        self.txt_raw.configure(state="disabled")

    def on_key(self, e):
        if isinstance(self.link, SimLink) and e.char.lower() == "e":
            self.link.board_emergency()
        elif isinstance(self.link, SimLink) and e.char.lower() == "p":
            self.link.paused = not self.link.paused
            self.event("정보", "데모 : 통신 끊음" if self.link.paused else "데모 : 통신 다시 이음")
        elif e.char in ("1", "2", "3"):
            self.call(int(e.char))

    def on_close(self):
        if self.link is not None:
            self.link.close()
        self.destroy()


def beep(root):
    try:
        import winsound
        winsound.MessageBeep(winsound.MB_ICONHAND)
    except ImportError:
        root.bell()
