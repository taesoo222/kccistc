"""가위바위보 게임: 2인 대전 / AI 대전 (cvzone 손 검출 + MobileNetV3-Small TFLite 분류)

  python rps_game.py                 # 시작 메뉴에서 모드 선택
  python rps_game.py --mode ai       # 메뉴 없이 바로 AI 대전
  python rps_game.py --mode 2p       # 메뉴 없이 바로 2인 대전

메뉴: 1 = 2인 대전, 2 = AI 대전, q = 종료
게임: SPACE 시작(3-2-1 후 판정), b 메뉴로, r 점수 초기화, q/ESC 종료

화면 = 카메라(640x480) + 오른쪽 정보 패널.
손 자르기는 crop_hands.py 와 같은 함수를 쓴다 (학습 사진과 동일한 전처리).

판정 = 학습 모델(MobileNetV3-Small) + 손가락 개수 규칙(finger_rule.py)
  둘이 같으면 그대로, 다르면 모델 확신이 --trust(기본 0.9) 이상일 때만 모델, 아니면 손가락 규칙.
  --judge cnn : 학습 모델만 / --judge rule : 손가락 규칙만 (비교용)
"""
import argparse
import random
import threading
import time
from collections import Counter, defaultdict
from pathlib import Path

import cv2
import numpy as np
from ai_edge_litert.interpreter import Interpreter
from cvzone.HandTrackingModule import HandDetector

import finger_rule
from crop_hands import CLASSES, crop_box, make_square_img

NAME = {'scissors': 'SCISSORS', 'rock': 'ROCK', 'paper': 'PAPER'}
COLORS = {'scissors': (255, 140, 0), 'rock': (80, 200, 80), 'paper': (60, 80, 255)}   # BGR
BEATS = {'rock': 'scissors', 'scissors': 'paper', 'paper': 'rock'}   # 키가 값을 이김

COUNTDOWN_S = 3.0   # 3-2-1
CAPTURE_S = 0.6     # 카운트 직후 이 시간 동안 나온 판정 중 가장 많은 것을 채택
RESULT_S = 3.0      # 결과 표시 시간

PANEL_W = 300                      # 오른쪽 정보 패널 폭
BG = (35, 30, 30)                  # 패널 배경
CARD = (60, 52, 50)                # 카드 배경
WHITE, GRAY, YELLOW = (255, 255, 255), (170, 170, 170), (0, 220, 255)
FONT = cv2.FONT_HERSHEY_SIMPLEX

# icons/<클래스>.png (Noto Emoji, icons/README.md 참고). 없으면 도형으로 대신 그린다.
ICONS = {c: cv2.imread(str(Path(__file__).with_name('icons') / f'{c}.png'), cv2.IMREAD_UNCHANGED)
         for c in CLASSES}


def jpeg_roundtrip(img, quality=95):
    """JPEG 로 압축했다가 다시 푼다. 학습 사진은 capture.py 와 crop_hands.py 에서
    cv2.imwrite (기본 품질 95) 로 두 번 JPEG 저장되므로, 게임 입력도 같은 과정을 거치게 한다."""
    ok, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return cv2.imdecode(buf, cv2.IMREAD_COLOR) if ok else img


class CameraThread:
    """카메라를 별도 스레드에서 계속 읽어 둔다. 본 루프가 판정하는 동안 다음 프레임이 준비되므로
    cap.read() 가 새 프레임을 기다리는 시간(30fps 카메라면 최대 약 33ms)이 사라진다."""

    def __init__(self, index):
        self.cap = cv2.VideoCapture(index)
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self.cond = threading.Condition()
        self.frame, self.fresh, self.running = None, False, self.cap.isOpened()
        threading.Thread(target=self._loop, daemon=True).start()

    def isOpened(self):
        return self.cap.isOpened()

    def _loop(self):
        while self.running:
            ret, f = self.cap.read()
            with self.cond:
                if not ret:
                    self.running = False
                else:
                    self.frame, self.fresh = f, True
                self.cond.notify()

    def read(self):
        """아직 안 쓴 최신 프레임을 돌려준다 (없으면 올 때까지 잠깐 기다림)"""
        with self.cond:
            self.cond.wait_for(lambda: self.fresh or not self.running, timeout=1.0)
            if self.frame is None or not self.running and not self.fresh:
                return False, None
            self.fresh = False
            return True, self.frame

    def release(self):
        self.running = False
        self.cap.release()


class RpsModel:
    def __init__(self, path, jpeg=True, threads=4):
        self.jpeg = jpeg
        self.it = Interpreter(model_path=path, num_threads=threads)   # 파이 5 의 4코어 사용
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]
        self.out = self.it.get_output_details()[0]
        self.size = self.inp['shape'][1]

    def predict(self, hand_bgr):
        """-> (클래스 이름, 확률)"""
        img = make_square_img(hand_bgr, self.size)
        if self.jpeg:
            img = jpeg_roundtrip(img)                          # crop_hands.py 의 두 번째 JPEG 저장과 동일
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)             # 학습 때와 같은 RGB
        img = np.expand_dims(img, 0).astype(self.inp['dtype'])  # 0~255 그대로 (정규화는 모델 안에서)
        self.it.set_tensor(self.inp['index'], img)
        self.it.invoke()
        prob = self.it.get_tensor(self.out['index'])[0]
        k = int(np.argmax(prob))
        return CLASSES[k], float(prob[k])


def judge(p1, p2):
    """-> 'P1', 'P2', 'DRAW'"""
    if p1 == p2:
        return 'DRAW'
    return 'P1' if BEATS[p1] == p2 else 'P2'


def assign_hands(hands, fw, mode):
    """cvzone 손 목록 -> {'P1': hand, 'P2': hand}
    2p: 화면 절반 기준 (같은 쪽에 여러 개면 큰 손) / ai: 가장 큰 손 하나만 P1"""
    best = {}
    for hand in hands:
        side = 'P1' if mode == 'ai' or hand['center'][0] < fw // 2 else 'P2'
        area = hand['bbox'][2] * hand['bbox'][3]
        if side not in best or area > best[side][0]:
            best[side] = (area, hand)
    return {side: hand for side, (_, hand) in best.items()}


# ---------------------------------------------------------------- 그리기 도우미
def text(img, s, org, scale=1.0, color=WHITE, thick=2, outline=True):
    if outline:
        cv2.putText(img, s, org, FONT, scale, (0, 0, 0), thick + 4, cv2.LINE_AA)
    cv2.putText(img, s, org, FONT, scale, color, thick, cv2.LINE_AA)


def text_c(img, s, cx, y, scale=1.0, color=WHITE, thick=2, outline=True):
    """가운데 정렬 글자"""
    (tw, _), _ = cv2.getTextSize(s, FONT, scale, thick)
    text(img, s, (cx - tw // 2, y), scale, color, thick, outline)


def shade(img, x1, y1, x2, y2, color=(0, 0, 0), alpha=0.55):
    """반투명 사각형"""
    roi = img[y1:y2, x1:x2]
    img[y1:y2, x1:x2] = cv2.addWeighted(roi, 1 - alpha, np.full_like(roi, color), alpha, 0)


_ICON_CACHE = {}


def _icon(cls, s, dim):
    """크기를 맞춘 아이콘 (rgb, alpha). 매 프레임 다시 줄이지 않도록 저장해 둔다."""
    key = (cls, s, dim)
    if key not in _ICON_CACHE:
        icon = ICONS.get(cls)
        if icon is None or icon.ndim != 3 or icon.shape[2] != 4:
            _ICON_CACHE[key] = None
        else:
            icon = cv2.resize(icon, (s, s), interpolation=cv2.INTER_AREA)
            rgb, alpha = icon[:, :, :3].astype(np.float32), icon[:, :, 3:].astype(np.float32) / 255
            if dim:
                rgb = np.repeat(cv2.cvtColor(icon[:, :, :3], cv2.COLOR_BGR2GRAY)[:, :, None], 3, 2).astype(np.float32)
                alpha *= 0.5
            _ICON_CACHE[key] = (rgb, alpha)
    return _ICON_CACHE[key]


def draw_icon(img, cls, cx, cy, s, color, dim=False):
    """가위/바위/보 아이콘을 (cx, cy) 중심에 s x s 크기로. dim=True 면 흐린 회색 (AI 고민 중)"""
    cached = _icon(cls, s, dim)
    if cached is not None:
        rgb, alpha = cached
        x1, y1 = cx - s // 2, cy - s // 2
        # 화면 밖으로 나가는 부분은 잘라낸다
        ix1, iy1 = max(0, -x1), max(0, -y1)
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(img.shape[1], cx - s // 2 + s), min(img.shape[0], cy - s // 2 + s)
        if x2 <= x1 or y2 <= y1:
            return
        rgb, alpha = rgb[iy1:iy1 + y2 - y1, ix1:ix1 + x2 - x1], alpha[iy1:iy1 + y2 - y1, ix1:ix1 + x2 - x1]
        roi = img[y1:y2, x1:x2].astype(np.float32)
        img[y1:y2, x1:x2] = (rgb * alpha + roi * (1 - alpha)).astype(np.uint8)
        return
    if dim:
        color = GRAY
    if cls == 'rock':        # 주먹: 둥근 덩어리 + 손가락 마디
        cv2.circle(img, (cx, cy), s // 2, color, -1, cv2.LINE_AA)
        for i in range(3):
            x = cx - s // 4 + i * s // 4
            cv2.line(img, (x, cy - s // 2 + 4), (x, cy - s // 6), BG, 3, cv2.LINE_AA)
    elif cls == 'paper':     # 보: 손바닥 + 손가락 다섯 개
        cv2.rectangle(img, (cx - s // 3, cy - s // 8), (cx + s // 3, cy + s // 2), color, -1)
        for i in range(4):
            x = cx - s // 3 + s // 12 + i * (s * 2 // 3 - s // 6) // 3
            cv2.line(img, (x, cy - s // 8), (x, cy - s // 2), color, max(4, s // 9), cv2.LINE_AA)
        cv2.line(img, (cx - s // 3, cy + s // 8), (cx - s // 2 - 4, cy - s // 10), color, max(4, s // 9), cv2.LINE_AA)
    else:                    # 가위: 손바닥 + V 두 손가락
        cv2.circle(img, (cx, cy + s // 4), s // 4, color, -1, cv2.LINE_AA)
        w = max(4, s // 8)
        cv2.line(img, (cx - s // 10, cy + s // 8), (cx - s // 3, cy - s // 2), color, w, cv2.LINE_AA)
        cv2.line(img, (cx + s // 10, cy + s // 8), (cx + s // 3, cy - s // 2), color, w, cv2.LINE_AA)


def card(panel, x, y, w, h, title, cls, sub='', hidden=False, t=0.0):
    """플레이어 카드: 제목 + 아이콘 + 이름. hidden=True 면 아이콘이 계속 바뀜(AI 고민 중)"""
    cv2.rectangle(panel, (x, y), (x + w, y + h), CARD, -1)
    text_c(panel, title, x + w // 2, y + 28, 0.7, YELLOW, 2, outline=False)
    cx, cy = x + w // 2, y + h // 2 + 8
    if hidden:
        cls = CLASSES[int(t * 8) % 3]                       # 빠르게 돌아가는 아이콘
        draw_icon(panel, cls, cx, cy - 4, 84, GRAY, dim=True)
        text_c(panel, '???', cx, y + h - 14, 0.7, GRAY, 2, outline=False)
    elif cls:
        draw_icon(panel, cls, cx, cy - 4, 84, COLORS[cls])
        text_c(panel, NAME[cls], cx, y + h - 14, 0.7, WHITE, 2, outline=False)
    else:
        text_c(panel, '-', cx, cy + 10, 1.2, GRAY, 2, outline=False)
        if sub:
            text_c(panel, sub, cx, y + h - 14, 0.5, GRAY, 1, outline=False)


# ---------------------------------------------------------------- 메인
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default='rps_model.tflite')
    ap.add_argument('--mode', choices=['2p', 'ai'], help='지정하면 메뉴 없이 바로 시작')
    ap.add_argument('--camera', type=int, default=0)
    ap.add_argument('--no-mirror', action='store_true', help='좌우 반전(거울 모드) 끄기')
    ap.add_argument('--no-jpeg', action='store_true',
                    help='모델 입력의 JPEG 압축 흉내 끄기 (학습 사진과 달라짐, 비교용)')
    ap.add_argument('--judge', choices=['both', 'cnn', 'rule'], default='both',
                    help='both: 학습 모델+손가락 규칙, cnn: 학습 모델만, rule: 손가락 규칙만')
    ap.add_argument('--trust', type=float, default=0.9,
                    help='두 판정이 다를 때 학습 모델을 믿는 최소 확률')
    ap.add_argument('--model-every', type=int, default=3,
                    help='평소에는 N 프레임마다 학습 모델 실행 (SHOW! 판정 구간은 항상 매 프레임)')
    ap.add_argument('--threads', type=int, default=4, help='학습 모델 계산 스레드 수')
    ap.add_argument('--profile', action='store_true', help='단계별 시간(ms)을 터미널에 출력')
    args = ap.parse_args()

    model = RpsModel(args.model, jpeg=not args.no_jpeg, threads=args.threads)
    hd = HandDetector(maxHands=2)
    cap = CameraThread(args.camera)
    if not cap.isOpened():
        raise SystemExit(f'카메라 {args.camera}번을 열 수 없습니다 (다른 프로그램이 사용 중인지 확인)')
    cv2.namedWindow('Rock Paper Scissors', cv2.WINDOW_NORMAL)

    mode = args.mode                 # None = 메뉴
    state, t_state = ('menu' if mode is None else 'idle'), 0.0
    votes = {'P1': Counter(), 'P2': Counter()}
    picks = {'P1': None, 'P2': None}
    winner, rounds = None, 0
    score = Counter()
    t_prev, fps = time.time(), 0.0
    model_cache = {}                 # side -> (모델 판정, 확률): 모델을 건너뛰는 프레임에서 재사용
    n_frame = 0
    prof, prof_n = defaultdict(float), 0

    while True:
        t0 = time.perf_counter()
        ret, frame = cap.read()
        if not ret:
            break
        n_frame += 1
        t_read = time.perf_counter()
        t_detect = t_read
        if not args.no_mirror:
            frame = cv2.flip(frame, 1)   # 거울처럼 보이게 (학습 때 좌우반전 증강을 해서 인식에는 영향 적음)
        fh, fw = frame.shape[:2]
        view = frame.copy()              # 모델 입력은 frame, 그림은 view 에
        now = time.time()
        label = {'P1': 'YOU' if mode == 'ai' else 'P1', 'P2': 'AI' if mode == 'ai' else 'P2'}

        # ---- 손 찾기 -> P1/P2 배정 -> 손마다 판정 (메뉴에서는 생략) ----
        now_pick = {}
        if state != 'menu':
            hands, _ = hd.findHands(frame, draw=False)
            t_detect = time.perf_counter()
            # 이번 프레임에 학습 모델을 돌릴지: 판정 구간(capture)은 항상, 평소에는 N 프레임마다
            run_model = args.judge != 'rule' and (state == 'capture' or n_frame % max(1, args.model_every) == 0)
            model_frame = None           # 모델에 넣을 화면 (JPEG 흉내), 필요할 때 한 번만 만든다
            assigned = assign_hands(hands, fw, mode)
            for side in list(model_cache):   # 손이 사라진 쪽의 저장값은 버린다
                if side not in assigned:
                    model_cache.pop(side)
            for side, hand in assigned.items():
                box = crop_box(hand['bbox'], fw, fh)
                if box is None:          # 화면 가장자리: 학습 때처럼 판정하지 않음
                    x, y, w, h = hand['bbox']
                    cv2.rectangle(view, (x, y), (x + w, y + h), (128, 128, 128), 2)
                    continue
                x1, y1, x2, y2 = box
                if run_model or side not in model_cache:
                    if model_frame is None:  # capture.py 의 첫 번째 JPEG 저장과 같은 과정
                        model_frame = frame if args.no_jpeg else jpeg_roundtrip(frame)
                    model_cache[side] = model.predict(model_frame[y1:y2, x1:x2])
                cnn_cls, p = model_cache[side]
                rule_cls = finger_rule.classify([(pt[0], pt[1]) for pt in hand['lmList']])
                if args.judge == 'cnn':
                    cls, src = cnn_cls, 'cnn'
                elif args.judge == 'rule':
                    cls, src = rule_cls, 'rule'
                else:
                    cls, src = finger_rule.fuse(cnn_cls, p, rule_cls, args.trust)
                if cls is None:          # 손가락 규칙만 쓸 때 애매한 모양
                    cv2.rectangle(view, (x1, y1), (x2, y2), (128, 128, 128), 2)
                    text(view, f'{label[side]}  ?', (x1 + 5, y1 - 6), 0.55, GRAY, 2)
                    continue
                now_pick[side] = cls
                cv2.rectangle(view, (x1, y1), (x2, y2), COLORS[cls], 3)
                mark = {'both': 'OK', 'cnn': 'AI', 'rule': 'FINGER'}[src]   # 어느 판정을 썼는지
                tag = f'{label[side]}  {NAME[cls]}  [{mark}]'
                (tw, th), _ = cv2.getTextSize(tag, FONT, 0.55, 2)
                cv2.rectangle(view, (x1, y1 - th - 12), (x1 + tw + 10, y1), COLORS[cls], -1)
                text(view, tag, (x1 + 5, y1 - 6), 0.55, WHITE, 2, outline=False)
                # 박스 아래: 두 판정을 각각 표시 (발표·디버깅용)
                detail = f"model {NAME[cnn_cls]} {p:.0%} / finger {NAME.get(rule_cls, '?')}"
                text(view, detail, (x1, min(fh - 8, y2 + 20)), 0.45, WHITE, 1)
        t_judge = time.perf_counter()

        # ---- 게임 진행: menu / idle -> countdown -> capture -> result -> idle ----
        elapsed = now - t_state
        if state == 'countdown':
            if elapsed >= COUNTDOWN_S:
                state, t_state = 'capture', now
                votes = {'P1': Counter(), 'P2': Counter()}
            else:
                n = int(COUNTDOWN_S - elapsed) + 1
                r = int(70 + 30 * ((COUNTDOWN_S - elapsed) % 1))      # 숫자마다 원이 줄어듦
                cv2.circle(view, (fw // 2, fh // 2), r, (0, 0, 0), -1, cv2.LINE_AA)
                cv2.circle(view, (fw // 2, fh // 2), r, YELLOW, 4, cv2.LINE_AA)
                text_c(view, str(n), fw // 2, fh // 2 + 35, 3.0, YELLOW, 7, outline=False)
        if state == 'capture':
            for side in ('P1', 'P2'):
                if side in now_pick:
                    votes[side][now_pick[side]] += 1
            text_c(view, 'SHOW!', fw // 2, fh // 2 + 25, 2.4, (0, 0, 255), 6)
            if now - t_state >= CAPTURE_S:
                picks = {s: (votes[s].most_common(1)[0][0] if votes[s] else None) for s in ('P1', 'P2')}
                if mode == 'ai':
                    picks['P2'] = random.choice(CLASSES)    # AI 는 무작위로 낸다
                if picks['P1'] and picks['P2']:
                    winner = judge(picks['P1'], picks['P2'])
                    score[winner] += 1
                    rounds += 1
                else:
                    winner = 'NO HAND'
                state, t_state = 'result', now
        if state == 'result':
            if mode == 'ai' and winner == 'P2':
                msg, col = 'YOU LOSE', (0, 0, 190)
            elif winner in ('P1', 'P2'):
                msg, col = f'{label[winner]} WIN!', (0, 170, 0)
            elif winner == 'DRAW':
                msg, col = 'DRAW', (0, 150, 200)
            else:
                msg, col = 'NO HAND - TRY AGAIN', (0, 0, 180)
            shade(view, 0, fh // 2 - 55, fw, fh // 2 + 45, col, 0.75)
            text_c(view, msg, fw // 2, fh // 2 + 15, 1.8 if len(msg) < 12 else 1.1, WHITE, 4)
            if now - t_state >= RESULT_S:
                state = 'idle'
        if mode == '2p' and state != 'menu':
            cv2.line(view, (fw // 2, 0), (fw // 2, fh), (200, 200, 200), 1)
            text(view, 'P1', (10, 30), 0.8, YELLOW)
            text(view, 'P2', (fw - 45, 30), 0.8, YELLOW)

        if state == 'menu':
            shade(view, 0, 0, fw, fh, (0, 0, 0), 0.6)
            text_c(view, 'ROCK  PAPER  SCISSORS', fw // 2, 110, 1.3, YELLOW, 3)
            for i, cls in enumerate(CLASSES):
                draw_icon(view, cls, fw // 2 - 120 + i * 120, 185, 80, COLORS[cls])
            for i, (k, s) in enumerate([('1', '2 PLAYERS'), ('2', 'VS AI')]):
                y = 270 + i * 70
                cv2.rectangle(view, (fw // 2 - 150, y), (fw // 2 + 150, y + 52), CARD, -1)
                cv2.rectangle(view, (fw // 2 - 150, y), (fw // 2 + 150, y + 52), YELLOW, 2)
                text(view, f'[{k}]  {s}', (fw // 2 - 120, y + 36), 0.9, WHITE, 2, outline=False)
            text_c(view, 'q : quit', fw // 2, fh - 25, 0.6, GRAY, 1)

        # ---- 오른쪽 패널 ----
        panel = np.full((fh, PANEL_W, 3), BG, np.uint8)
        px = 15
        if state == 'menu':
            text_c(panel, 'SELECT MODE', PANEL_W // 2, 50, 0.8, YELLOW, 2, outline=False)
            text_c(panel, 'press 1 or 2', PANEL_W // 2, 85, 0.6, GRAY, 1, outline=False)
        else:
            text_c(panel, 'VS AI' if mode == 'ai' else '2 PLAYERS', PANEL_W // 2, 35, 0.8, YELLOW, 2, outline=False)
            # 점수판
            cv2.rectangle(panel, (px, 50), (PANEL_W - px, 110), CARD, -1)
            text_c(panel, f"{score['P1']}  :  {score['P2']}", PANEL_W // 2, 92, 1.3, WHITE, 3, outline=False)
            text(panel, label['P1'], (px + 8, 72), 0.5, GRAY, 1, outline=False)
            text(panel, label['P2'], (PANEL_W - px - 32, 72), 0.5, GRAY, 1, outline=False)
            text_c(panel, f"round {rounds}   draw {score['DRAW']}", PANEL_W // 2, 130, 0.5, GRAY, 1, outline=False)
            # 두 플레이어 카드: 대기 중엔 실시간 인식, 결과 때는 확정된 선택
            cw, ch, cy = (PANEL_W - 3 * px) // 2, 170, 150
            for i, side in enumerate(('P1', 'P2')):
                x = px + i * (cw + px)
                if state == 'result':
                    card(panel, x, cy, cw, ch, label[side], picks[side], 'no hand')
                elif mode == 'ai' and side == 'P2':
                    card(panel, x, cy, cw, ch, 'AI', None, 'waiting',
                         hidden=state in ('countdown', 'capture'), t=now)
                else:
                    card(panel, x, cy, cw, ch, label[side], now_pick.get(side), 'no hand')
            if state == 'result' and winner in ('P1', 'P2'):   # 이긴 쪽 카드 테두리
                x = px + (0 if winner == 'P1' else cw + px)
                cv2.rectangle(panel, (x, cy), (x + cw, cy + ch), (0, 200, 0), 4)
            # 안내
            status = {'idle': 'press SPACE to play', 'countdown': 'get ready...',
                      'capture': 'SHOW YOUR HAND!', 'result': ''}[state]
            text_c(panel, status, PANEL_W // 2, 355, 0.6, WHITE, 1, outline=False)
            for i, s in enumerate(['SPACE  start', 'b  menu', 'r  reset score', 'q  quit']):
                text(panel, s, (px + 10, 395 + i * 22), 0.5, GRAY, 1, outline=False)
        fps = 0.9 * fps + 0.1 / max(now - t_prev, 1e-6)
        t_prev = now
        text(panel, f'FPS {fps:.0f}', (PANEL_W - 75, fh - 8), 0.45, GRAY, 1, outline=False)

        t_draw = time.perf_counter()
        cv2.imshow('Rock Paper Scissors', np.hstack([view, panel]))
        key = cv2.waitKey(1) & 0xFF
        if args.profile:
            t_show = time.perf_counter()
            for k, v in (('camera', t_read - t0), ('hand', t_detect - t_read), ('judge', t_judge - t_detect),
                         ('draw', t_draw - t_judge), ('show', t_show - t_draw), ('total', t_show - t0)):
                prof[k] += v
            prof_n += 1
            if prof_n == 30:             # 30 프레임 평균
                print('  '.join(f'{k} {v / prof_n * 1000:5.1f}ms' for k, v in prof.items()), flush=True)
                prof, prof_n = defaultdict(float), 0
        if key in (ord('q'), 27):
            break
        if state == 'menu':
            if key in (ord('1'), ord('2')):
                mode = '2p' if key == ord('1') else 'ai'
                state, rounds = 'idle', 0
                score.clear()
        else:
            if key == ord(' ') and state == 'idle':
                state, t_state = 'countdown', now
            if key == ord('b') and state in ('idle', 'result'):
                state = 'menu'
            if key == ord('r'):
                score.clear()
                rounds = 0

    cap.release()
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
