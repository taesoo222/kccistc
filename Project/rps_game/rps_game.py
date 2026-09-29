"""2인 가위바위보 게임 (cvzone 손 검출 + MobileNetV3-Small TFLite 분류)

  python rps_game.py                          # rps_model.tflite 사용
  python rps_game.py --model rps_model_v1.tflite

화면 왼쪽 = P1, 오른쪽 = P2
키: SPACE 게임 시작 (3-2-1 후 판정), r 점수 초기화, q/ESC 종료

손 자르기는 crop_hands.py 와 같은 함수를 쓴다 (학습 사진과 동일한 전처리).
"""
import argparse
import time
from collections import Counter

import cv2
import numpy as np
from ai_edge_litert.interpreter import Interpreter
from cvzone.HandTrackingModule import HandDetector

from crop_hands import CLASSES, crop_box, make_square_img

KOR = {'scissors': 'SCISSORS', 'rock': 'ROCK', 'paper': 'PAPER'}
COLORS = {'scissors': (255, 0, 0), 'rock': (0, 255, 0), 'paper': (0, 0, 255)}
BEATS = {'rock': 'scissors', 'scissors': 'paper', 'paper': 'rock'}   # 키가 값을 이김

COUNTDOWN_S = 3.0   # 3-2-1
CAPTURE_S = 0.6     # 카운트 직후 이 시간 동안 나온 판정 중 가장 많은 것을 채택
RESULT_S = 3.0      # 결과 표시 시간


class RpsModel:
    def __init__(self, path):
        self.it = Interpreter(model_path=path)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]
        self.out = self.it.get_output_details()[0]
        self.size = self.inp['shape'][1]

    def predict(self, hand_bgr):
        """-> (클래스 이름, 확률)"""
        img = make_square_img(hand_bgr, self.size)
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


def text(img, s, org, scale=1.0, color=(255, 255, 255), thick=2):
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 0, 0), thick + 4, cv2.LINE_AA)
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_SIMPLEX, scale, color, thick, cv2.LINE_AA)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default='rps_model.tflite')
    ap.add_argument('--camera', type=int, default=0)
    ap.add_argument('--no-mirror', action='store_true', help='좌우 반전(거울 모드) 끄기')
    args = ap.parse_args()

    model = RpsModel(args.model)
    hd = HandDetector(maxHands=2)
    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        raise SystemExit(f'카메라 {args.camera}번을 열 수 없습니다 (다른 프로그램이 사용 중인지 확인)')
    cv2.namedWindow('RPS 2P', cv2.WINDOW_NORMAL)

    state, t_state = 'idle', 0.0
    votes = {'P1': Counter(), 'P2': Counter()}
    picks = {'P1': None, 'P2': None}
    winner = None
    score = Counter()
    t_prev = time.time()

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if not args.no_mirror:
            frame = cv2.flip(frame, 1)   # 거울처럼 보이게 (학습 때 좌우반전 증강을 해서 인식에는 영향 적음)
        fh, fw = frame.shape[:2]
        view = frame.copy()              # 모델 입력은 frame, 그림은 view 에
        now = time.time()

        # ---- 손 찾기 -> 화면 절반 기준으로 P1/P2 배정 (같은 쪽에 여러 개면 큰 손) ----
        hands, _ = hd.findHands(frame, draw=False)
        best = {}
        for hand in hands:
            side = 'P1' if hand['center'][0] < fw // 2 else 'P2'
            area = hand['bbox'][2] * hand['bbox'][3]
            if side not in best or area > best[side][0]:
                best[side] = (area, hand)

        now_pick = {}
        for side, (_, hand) in best.items():
            box = crop_box(hand['bbox'], fw, fh)
            if box is None:              # 화면 가장자리: 학습 때처럼 판정하지 않음
                x, y, w, h = hand['bbox']
                cv2.rectangle(view, (x, y), (x + w, y + h), (128, 128, 128), 2)
                continue
            x1, y1, x2, y2 = box
            cls, p = model.predict(frame[y1:y2, x1:x2])
            now_pick[side] = cls
            cv2.rectangle(view, (x1, y1), (x2, y2), COLORS[cls], 2)
            text(view, f'{side} {KOR[cls]} {p:.0%}', (x1, max(20, y1 - 8)), 0.6, COLORS[cls], 2)

        # ---- 게임 진행: idle -> countdown -> capture -> result -> idle ----
        elapsed = now - t_state
        if state == 'countdown':
            if elapsed >= COUNTDOWN_S:
                state, t_state = 'capture', now
                votes = {'P1': Counter(), 'P2': Counter()}
            else:
                text(view, str(int(COUNTDOWN_S - elapsed) + 1), (fw // 2 - 30, fh // 2 + 30), 4, (0, 255, 255), 8)
        if state == 'capture':
            for side in ('P1', 'P2'):
                if side in now_pick:
                    votes[side][now_pick[side]] += 1
            text(view, 'SHOW!', (fw // 2 - 110, fh // 2 + 20), 2.2, (0, 0, 255), 5)
            if now - t_state >= CAPTURE_S:
                picks = {s: (votes[s].most_common(1)[0][0] if votes[s] else None) for s in ('P1', 'P2')}
                if picks['P1'] and picks['P2']:
                    winner = judge(picks['P1'], picks['P2'])
                    score[winner] += 1
                else:
                    winner = 'NO HAND'
                state, t_state = 'result', now
        if state == 'result':
            text(view, f"P1: {KOR.get(picks['P1'], '?')}", (15, fh - 50), 0.9)
            text(view, f"P2: {KOR.get(picks['P2'], '?')}", (fw // 2 + 15, fh - 50), 0.9)
            msg = {'P1': 'P1 WIN!', 'P2': 'P2 WIN!', 'DRAW': 'DRAW'}.get(winner, 'NO HAND')
            color = (0, 255, 255) if winner == 'DRAW' else (0, 255, 0) if winner in ('P1', 'P2') else (0, 0, 255)
            (tw, _), _ = cv2.getTextSize(msg, cv2.FONT_HERSHEY_SIMPLEX, 2.2, 5)
            text(view, msg, ((fw - tw) // 2, fh // 2 + 20), 2.2, color, 5)
            if now - t_state >= RESULT_S:
                state = 'idle'
        if state == 'idle':
            text(view, 'SPACE: start   r: reset   q: quit', (15, fh - 15), 0.6, (200, 200, 200), 1)

        # ---- 공통 표시: 가운데 선, 점수, FPS ----
        cv2.line(view, (fw // 2, 0), (fw // 2, fh), (200, 200, 200), 1)
        text(view, f"P1  {score['P1']}", (15, 35), 1.0, (255, 255, 0))
        text(view, f"{score['P2']}  P2", (fw - 120, 35), 1.0, (255, 255, 0))
        text(view, f"draw {score['DRAW']}", (fw // 2 - 50, 35), 0.6, (200, 200, 200), 1)
        fps = 1 / max(now - t_prev, 1e-6)
        t_prev = now
        text(view, f'FPS {fps:.0f}', (fw // 2 - 40, 60), 0.5, (200, 200, 200), 1)

        cv2.imshow('RPS 2P', view)
        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            break
        if key == ord(' ') and state == 'idle':
            state, t_state = 'countdown', now
        if key == ord('r'):
            score.clear()

    cap.release()
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
