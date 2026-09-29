"""웹캠 가위바위보 게임 (cvzone 손 검출 + TFLite 분류 모델).

인식 파이프라인은 레퍼런스 코드와 동일:
  cvzone HandDetector로 손 BB 검출 -> 손 영역 crop -> 흰 배경 정사각형 -> TFLite 추론

키: SPACE 라운드 시작, r 점수 초기화, q/ESC 종료
"""
import argparse
import random
import time
from collections import Counter

import cv2
import numpy as np
from ai_edge_litert.interpreter import Interpreter
from cvzone.HandTrackingModule import HandDetector

from gesture import judge

from common import CLASSES, hand_crop_box, make_square_img

ansToText = dict(enumerate(CLASSES))  # {0:'scissors', 1:'rock', 2:'paper'}
colorList = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]

COUNTDOWN_S = 3.0   # 3-2-1 카운트
CAPTURE_S = 0.6     # 카운트 직후 손 모양을 모으는 시간 (다수결)
RESULT_S = 2.5      # 결과 표시 시간


class RpsModel:
    def __init__(self, model_path):
        self.interpreter = Interpreter(model_path=model_path)
        self.interpreter.allocate_tensors()
        self.inp = self.interpreter.get_input_details()[0]
        self.out = self.interpreter.get_output_details()[0]
        self.size = self.inp['shape'][1]
        print('model input shape:', tuple(self.inp['shape']), self.inp['dtype'])

    def predict(self, img_bgr):
        img = make_square_img(img_bgr, self.size)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = np.expand_dims(img, 0).astype(np.float32)
        scale, zero = self.inp['quantization']
        if scale:  # int8/uint8 양자화 모델: 0~255 값을 모델의 정수 스케일로 변환
            info = np.iinfo(self.inp['dtype'])
            img = np.clip(np.round(img / scale + zero), info.min, info.max)
        self.interpreter.set_tensor(self.inp['index'], img.astype(self.inp['dtype']))
        self.interpreter.invoke()
        return int(np.argmax(self.interpreter.get_tensor(self.out['index'])[0]))


def text(img, s, org, scale=1.0, color=(255, 255, 255), thick=2):
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_PLAIN, scale, (0, 0, 0), thick + 3)
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_PLAIN, scale, color, thick)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default='sample_01.tflite')
    ap.add_argument('--camera', type=int, default=0)
    ap.add_argument('--width', type=int, default=320)
    ap.add_argument('--height', type=int, default=240)
    args = ap.parse_args()

    model = RpsModel(args.model)
    hd = HandDetector(maxHands=1)

    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    cv2.namedWindow('rps', cv2.WINDOW_NORMAL)
    cv2.resizeWindow('rps', args.width * 2, args.height * 2)

    state, t_state = 'idle', 0.0
    votes = Counter()
    player = computer = outcome = None
    score = Counter()
    t_prev = time.time()

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        fh, fw = frame.shape[:2]
        now = time.time()

        # ---- 손 인식 ----
        ans = None
        hands, _ = hd.findHands(frame, draw=False)
        if hands:
            box = hand_crop_box(hands[0]['bbox'], fw, fh)
            if box:
                x1, y1, x2, y2 = box
                ans = model.predict(frame[y1:y2, x1:x2])
                cv2.rectangle(frame, (x1, y1), (x2, y2), colorList[ans], 2)
                cv2.putText(frame, ansToText[ans], (x1, y1 - 7),
                            cv2.FONT_HERSHEY_PLAIN, 1.5, colorList[ans], 2)

        # ---- 게임 상태 머신: idle -> countdown -> capture -> result -> idle ----
        elapsed = now - t_state
        if state == 'countdown':
            if elapsed >= COUNTDOWN_S:
                state, t_state, votes = 'capture', now, Counter()
            else:
                text(frame, str(int(COUNTDOWN_S - elapsed) + 1),
                     (fw // 2 - 15, fh // 2), 4, (0, 255, 255), 4)
        if state == 'capture':
            if ans is not None:
                votes[ansToText[ans]] += 1
            text(frame, 'SHOW!', (fw // 2 - 50, fh // 2), 2.5, (0, 0, 255), 3)
            if now - t_state >= CAPTURE_S:
                player = votes.most_common(1)[0][0] if votes else None
                computer = random.choice(list(ansToText.values()))
                outcome = judge(player, computer) if player else 'no hand'
                if player:
                    score[outcome] += 1
                state, t_state = 'result', now
        if state == 'result':
            text(frame, f'YOU: {player or "?"}', (10, fh - 45), 1.3)
            text(frame, f'CPU: {computer}', (10, fh - 20), 1.3)
            color = {'win': (0, 255, 0), 'lose': (0, 0, 255)}.get(outcome, (0, 255, 255))
            text(frame, outcome.upper(), (fw // 2 - 60, fh // 2), 2.5, color, 3)
            if now - t_state >= RESULT_S:
                state = 'idle'
        if state == 'idle':
            text(frame, 'SPACE:play r:reset q:quit', (10, fh - 10), 1.0)

        # ---- 점수 / FPS ----
        fps = 1 / max(now - t_prev, 1e-6)
        t_prev = now
        text(frame, f'W{score["win"]} L{score["lose"]} D{score["draw"]}', (10, 25), 1.5)
        text(frame, f'FPS {fps:.1f}', (fw - 110, 25), 1.2, (0, 255, 255))

        cv2.imshow('rps', frame)
        key = cv2.waitKey(10) & 0xFF
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
