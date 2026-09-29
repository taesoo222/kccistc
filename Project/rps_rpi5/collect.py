"""현재 카메라로 학습용 손 이미지 수집 (게임과 동일한 crop -> 224 정사각형).

키:
  1 scissors / 2 rock / 3 paper : 해당 클래스 연속 저장 시작 (같은 키 다시 누르면 정지)
  0 또는 SPACE : 저장 정지
  q / ESC : 종료

저장 위치: <out>/<class>/<세션ID>_<번호>.jpg
세션ID(실행 시각)는 train_mobilenet.py 가 train/val 을 촬영 회차 단위로 나누는 데 쓴다.
"""
import argparse
import time
from pathlib import Path

import cv2
from cvzone.HandTrackingModule import HandDetector

from common import CLASSES, hand_crop_box, make_square_img

KEYS = {ord('1'): 0, ord('2'): 1, ord('3'): 2}
COLORS = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='data_new')
    ap.add_argument('--camera', type=int, default=0)
    ap.add_argument('--width', type=int, default=320)
    ap.add_argument('--height', type=int, default=240)
    ap.add_argument('--hands', type=int, default=2, help='한 프레임에서 저장할 최대 손 개수')
    ap.add_argument('--interval', type=float, default=0.15, help='저장 간격(초). 너무 짧으면 거의 같은 사진만 쌓임')
    args = ap.parse_args()

    out = Path(args.out)
    for c in CLASSES:
        (out / c).mkdir(parents=True, exist_ok=True)
    session = time.strftime('%Y%m%d-%H%M%S')
    counts = [len(list((out / c).glob('*.jpg'))) for c in CLASSES]

    hd = HandDetector(maxHands=args.hands)
    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    cv2.namedWindow('collect', cv2.WINDOW_NORMAL)
    cv2.resizeWindow('collect', args.width * 2, args.height * 2)

    rec, last_save, n = None, 0.0, 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        fh, fw = frame.shape[:2]
        view = frame.copy()   # 저장은 원본 frame 에서, 표시는 view 에
        now = time.time()

        hands, _ = hd.findHands(frame, draw=False)
        crops = []
        for hand in hands:
            box = hand_crop_box(hand['bbox'], fw, fh)
            if box is None:   # 게임에서도 판정하지 않는 위치 -> 저장하지 않음
                x, y, w, h = hand['bbox']
                cv2.rectangle(view, (x, y), (x + w, y + h), (128, 128, 128), 1)
                continue
            x1, y1, x2, y2 = box
            crops.append(frame[y1:y2, x1:x2])
            cv2.rectangle(view, (x1, y1), (x2, y2), COLORS[rec] if rec is not None else (255, 255, 255), 2)

        if rec is not None and crops and now - last_save >= args.interval:
            for crop in crops:
                n += 1
                cv2.imwrite(str(out / CLASSES[rec] / f'{session}_{n:05d}.jpg'), make_square_img(crop))
                counts[rec] += 1
            last_save = now

        status = f'REC {CLASSES[rec]}' if rec is not None else 'paused (1/2/3)'
        cv2.putText(view, status, (10, 20), cv2.FONT_HERSHEY_PLAIN, 1.3,
                    COLORS[rec] if rec is not None else (0, 255, 255), 2)
        cv2.putText(view, '  '.join(f'{c[0].upper()}:{k}' for c, k in zip(CLASSES, counts)),
                    (10, fh - 10), cv2.FONT_HERSHEY_PLAIN, 1.2, (0, 255, 255), 2)
        cv2.imshow('collect', view)

        key = cv2.waitKey(10) & 0xFF
        if key in (ord('q'), 27):
            break
        if key in KEYS:
            rec = None if rec == KEYS[key] else KEYS[key]
        elif key in (ord('0'), ord(' ')):
            rec = None

    cap.release()
    cv2.destroyAllWindows()
    print('saved per class:', dict(zip(CLASSES, counts)))


if __name__ == '__main__':
    main()
