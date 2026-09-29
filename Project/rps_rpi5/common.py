"""collect.py / train / 게임이 같이 쓰는 전처리. 학습과 추론의 전처리를 반드시 동일하게 유지."""
import numpy as np
import cv2

CLASSES = ['scissors', 'rock', 'paper']   # 모델 출력 인덱스 순서 (0, 1, 2)
IMG_SIZE = 224
offset = 30


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


def hand_crop_box(bbox, frame_w, frame_h):
    """BB를 좌/상/우로 offset만큼 늘린 crop 영역. 화면을 벗어나면 None."""
    x, y, w, h = bbox
    if x < offset or y < offset or x + w + offset > frame_w or y + h > frame_h:
        return None
    return x - offset, y - offset, x + w + offset, y + h
