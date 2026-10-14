from pathlib import Path
import urllib.request
import cv2
import mediapipe as mp

from config import (
    MODEL_PATH, MODEL_URL, NUM_HANDS,
    MIN_HAND_DETECTION_CONFIDENCE,
    MIN_HAND_PRESENCE_CONFIDENCE,
    MIN_TRACKING_CONFIDENCE,
)

HAND_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,4),
    (0,5),(5,6),(6,7),(7,8),
    (5,9),(9,10),(10,11),(11,12),
    (9,13),(13,14),(14,15),(15,16),
    (13,17),(17,18),(18,19),(19,20),
    (0,17),
]

def ensure_model():
    p = Path(MODEL_PATH)
    if p.exists():
        return str(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    print("[INFO] MediaPipe Hand Landmarker 모델 다운로드 중...")
    urllib.request.urlretrieve(MODEL_URL, p)
    return str(p)

class HandTracker:
    def __init__(self):
        model_path = ensure_model()
        options = mp.tasks.vision.HandLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=model_path),
            running_mode=mp.tasks.vision.RunningMode.VIDEO,
            num_hands=NUM_HANDS,
            min_hand_detection_confidence=MIN_HAND_DETECTION_CONFIDENCE,
            min_hand_presence_confidence=MIN_HAND_PRESENCE_CONFIDENCE,
            min_tracking_confidence=MIN_TRACKING_CONFIDENCE,
        )
        self.landmarker = mp.tasks.vision.HandLandmarker.create_from_options(options)

    def process(self, frame_bgr, timestamp_ms):
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
        return self.landmarker.detect_for_video(mp_image, timestamp_ms)

    def close(self):
        self.landmarker.close()

def landmark_to_pixel(lm, w, h):
    x = max(0, min(w-1, int(lm.x * w)))
    y = max(0, min(h-1, int(lm.y * h)))
    return x, y

def draw_hand(frame, result, draw=True):
    if not result.hand_landmarks:
        return frame, None

    h, w = frame.shape[:2]
    landmarks = result.hand_landmarks[0]
    points = [landmark_to_pixel(lm, w, h) for lm in landmarks]

    if draw:
        for a, b in HAND_CONNECTIONS:
            cv2.line(frame, points[a], points[b], (0,255,0), 2)

        for i, (x, y) in enumerate(points):
            radius = 6 if i in (4,8) else 4
            color = (0,0,255) if i == 8 else ((255,0,255) if i == 4 else (255,255,0))
            cv2.circle(frame, (x,y), radius, color, -1)

    handedness = "Unknown"
    score = 0.0
    if result.handedness and result.handedness[0]:
        c = result.handedness[0][0]
        handedness = c.category_name or "Unknown"
        score = float(c.score or 0.0)

    return frame, {
        "landmarks": landmarks,
        "points": points,
        "index_tip": points[8],
        "thumb_tip": points[4],
        "handedness": handedness,
        "score": score,
    }
