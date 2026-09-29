"""원본 사진(raw)에서 cvzone으로 손을 찾아 잘라 데이터셋을 만든다.

  python crop_hands.py raw_train dataset/train
  python crop_hands.py raw_test  dataset/test

입력:  <src>/scissors|rock|paper/*.jpg   (640x480 화면 전체)
출력:  <dst>/scissors|rock|paper/<원본이름>_L.jpg / _R.jpg  (224x224, 흰 배경 정사각형)
       _L = 화면 왼쪽 손, _R = 화면 오른쪽 손

자르는 규칙은 레퍼런스 코드와 동일 (게임에서도 이 함수를 그대로 쓴다):
  손 BB를 좌/상/우로 offset 만큼 넓히고, 아래쪽은 넓히지 않음. 화면을 벗어나면 버림.
"""
import argparse
from pathlib import Path

import cv2
import numpy as np

CLASSES = ['scissors', 'rock', 'paper']   # 모델 출력 순서: 0 가위, 1 바위, 2 보
IMG_SIZE = 224
OFFSET = 60   # 640x480 기준 (320x240 에서 30px 과 같은 비율)


def crop_box(bbox, frame_w, frame_h, offset=OFFSET):
    """cvzone BB -> 잘라낼 영역 (x1, y1, x2, y2). 화면을 벗어나면 None."""
    x, y, w, h = bbox
    if x < offset or y < offset or x + w + offset > frame_w or y + h > frame_h:
        return None
    return x - offset, y - offset, x + w + offset, y + h


def make_square_img(img, size=IMG_SIZE):
    """손 이미지를 비율 유지한 채 size x size 흰 배경 가운데에 붙인다."""
    ho, wo = img.shape[:2]
    wbg = np.ones((size, size, 3), np.uint8) * 255
    if ho > wo:  # portrait
        wk = max(1, int(wo * size / ho))
        img = cv2.resize(img, (wk, size))
        d = (size - wk) // 2
        wbg[:, d:d + wk] = img
    else:        # landscape
        hk = max(1, int(ho * size / wo))
        img = cv2.resize(img, (size, hk))
        d = (size - hk) // 2
        wbg[d:d + hk, :] = img
    return wbg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src', help='원본 폴더 (예: raw_train)')
    ap.add_argument('dst', help='출력 폴더 (예: dataset/train)')
    ap.add_argument('--offset', type=int, default=OFFSET)
    args = ap.parse_args()

    from cvzone.HandTrackingModule import HandDetector
    # staticMode=True: 사진이 서로 독립이므로 매 장마다 새로 검출 (추적 X)
    hd = HandDetector(staticMode=True, maxHands=2)

    total = {'images': 0, 'saved': 0, 'no_hand': 0, 'out_of_frame': 0}
    for cls in CLASSES:
        src_dir, dst_dir = Path(args.src) / cls, Path(args.dst) / cls
        if not src_dir.is_dir():
            print(f'[건너뜀] {src_dir} 없음')
            continue
        dst_dir.mkdir(parents=True, exist_ok=True)
        saved = 0
        for p in sorted(src_dir.glob('*.jpg')):
            frame = cv2.imread(str(p))
            if frame is None:
                continue
            total['images'] += 1
            fh, fw = frame.shape[:2]
            hands, _ = hd.findHands(frame, draw=False)
            if not hands:
                total['no_hand'] += 1
                continue
            used = set()
            for hand in hands:
                box = crop_box(hand['bbox'], fw, fh, args.offset)
                if box is None:
                    total['out_of_frame'] += 1
                    continue
                side = 'L' if hand['center'][0] < fw // 2 else 'R'
                if side in used:          # 같은 쪽에 손이 두 개인 경우
                    side += '2'
                used.add(side)
                x1, y1, x2, y2 = box
                cv2.imwrite(str(dst_dir / f'{p.stem}_{side}.jpg'),
                            make_square_img(frame[y1:y2, x1:x2]))
                saved += 1
        total['saved'] += saved
        print(f'{cls:9s}: {saved}장 저장')

    print(f"\n원본 {total['images']}장 -> 손 사진 {total['saved']}장 저장")
    print(f"  손 못 찾음: {total['no_hand']}장, 화면 가장자리에 걸려 버린 손: {total['out_of_frame']}개")


if __name__ == '__main__':
    main()
