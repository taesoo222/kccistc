"""학습용 원본 사진 촬영 (640x480 화면 전체 저장).

  python capture.py raw_train     # 학습용
  python capture.py raw_test      # 시험용 (다른 시간에 따로 찍기)

키:
  1 가위 / 2 바위 / 3 보 : 해당 클래스 연속 저장 시작 (같은 키 다시 누르면 멈춤)
  0 또는 SPACE : 멈춤
  q / ESC : 종료

화면의 박스는 나중에 crop_hands.py 가 잘라낼 영역 미리보기 (저장 사진에는 안 그려짐).
  초록/파랑/빨강 박스 = 잘라서 쓸 수 있는 손, 회색 박스 = 화면 가장자리라 버려질 손
손이 하나도 안 잡힌 순간은 저장하지 않는다.
"""
import argparse
import time
from pathlib import Path

import cv2
from cvzone.HandTrackingModule import HandDetector

from crop_hands import CLASSES, crop_box

KEYS = {ord('1'): 0, ord('2'): 1, ord('3'): 2}
COLORS = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out', help='저장 폴더 (예: raw_train)')
    ap.add_argument('--camera', type=int, default=0)
    ap.add_argument('--interval', type=float, default=0.3, help='저장 간격(초)')
    args = ap.parse_args()

    out = Path(args.out)
    for c in CLASSES:
        (out / c).mkdir(parents=True, exist_ok=True)
    counts = [len(list((out / c).glob('*.jpg'))) for c in CLASSES]
    session = time.strftime('%m%d-%H%M%S')   # 파일 이름 앞부분 = 촬영 회차

    hd = HandDetector(maxHands=2)
    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    cv2.namedWindow('capture', cv2.WINDOW_NORMAL)

    rec, last, n = None, 0.0, 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        fh, fw = frame.shape[:2]
        view = frame.copy()          # 표시용. 저장은 frame(원본)으로
        now = time.time()

        hands, _ = hd.findHands(frame, draw=False)
        usable = 0
        for hand in hands:
            box = crop_box(hand['bbox'], fw, fh)
            if box:
                usable += 1
                color = COLORS[rec] if rec is not None else (255, 255, 255)
                cv2.rectangle(view, box[:2], box[2:], color, 2)
            else:
                x, y, w, h = hand['bbox']
                cv2.rectangle(view, (x, y), (x + w, y + h), (128, 128, 128), 2)

        if rec is not None and usable and now - last >= args.interval:
            n += 1
            cv2.imwrite(str(out / CLASSES[rec] / f'{session}_{n:04d}.jpg'), frame)
            counts[rec] += 1
            last = now

        # 화면 표시: 가운데 선(2인 구역), 상태, 장수
        cv2.line(view, (fw // 2, 0), (fw // 2, fh), (0, 255, 255), 1)
        status = f'REC {CLASSES[rec]}' if rec is not None else 'PAUSE  (1:scissors 2:rock 3:paper)'
        cv2.putText(view, status, (10, 30), cv2.FONT_HERSHEY_PLAIN, 1.8,
                    COLORS[rec] if rec is not None else (0, 255, 255), 2)
        cv2.putText(view, f'scissors {counts[0]}  rock {counts[1]}  paper {counts[2]}',
                    (10, fh - 15), cv2.FONT_HERSHEY_PLAIN, 1.6, (0, 255, 255), 2)
        cv2.imshow('capture', view)

        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            break
        if key in KEYS:
            rec = None if rec == KEYS[key] else KEYS[key]
        elif key in (ord('0'), ord(' ')):
            rec = None

    cap.release()
    cv2.destroyAllWindows()
    print('저장된 장수:', dict(zip(CLASSES, counts)))


if __name__ == '__main__':
    main()
