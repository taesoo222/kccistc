"""MediaPipe 손 관절 21개로 펴진 손가락을 세서 가위/바위/보를 판정하는 규칙.

관절 번호 (MediaPipe Hands): 0 손목, 6/10/14/18 = 검지~새끼 둘째 마디(PIP), 8/12/16/20 = 손가락 끝.
엄지는 바위/가위 모두에서 모양이 애매해서 쓰지 않는다.
손목~끝 거리와 손목~둘째 마디 거리를 비교하므로 손이 기울어져도 결과가 같다.
"""
from math import dist

WRIST = 0
FINGERS = {'index': (6, 8), 'middle': (10, 12), 'ring': (14, 16), 'pinky': (18, 20)}  # (PIP, TIP)
EXTEND_RATIO = 1.15   # 손가락 끝이 둘째 마디보다 이만큼 더 멀면 '펴짐'


def extended_fingers(points):
    """points: 관절 21개의 (x, y). -> {'index': True/False, ...}"""
    w = points[WRIST]
    return {name: dist(w, points[tip]) > dist(w, points[pip]) * EXTEND_RATIO
            for name, (pip, tip) in FINGERS.items()}


def classify(points):
    """-> 'rock' / 'scissors' / 'paper' / None(애매함)"""
    ext = extended_fingers(points)
    up = sum(ext.values())
    if up == 0:
        return 'rock'
    if up == 4:
        return 'paper'
    if ext['index'] and ext['middle'] and not ext['ring'] and not ext['pinky']:
        return 'scissors'
    return None


def fuse(cnn_cls, cnn_prob, rule_cls, trust=0.9):
    """학습 모델(cnn) 판정과 손가락 규칙(rule) 판정을 합친다. -> (최종 클래스, 근거)
    근거: 'both' 둘이 같음 / 'cnn' 규칙이 애매하거나 모델 확신이 trust 이상 / 'rule' 규칙 채택"""
    if rule_cls is None:
        return cnn_cls, 'cnn'
    if rule_cls == cnn_cls:
        return cnn_cls, 'both'
    if cnn_prob >= trust:
        return cnn_cls, 'cnn'
    return rule_cls, 'rule'
