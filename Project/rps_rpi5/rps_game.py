"""Webcam rock-paper-scissors for Raspberry Pi 5.

Keys: SPACE start round, r reset score, q / ESC quit.
"""
import argparse
import random
import time
import urllib.request
from collections import Counter
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

from gesture import PAPER, ROCK, SCISSORS, classify, judge

MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
             "hand_landmarker/float16/1/hand_landmarker.task")
MODEL_PATH = Path(__file__).with_name("hand_landmarker.task")

COUNTDOWN_S = 3.0   # "rock, paper, scissors" count
CAPTURE_S = 0.6     # vote window after the count
RESULT_S = 2.5      # how long the result stays on screen

HAND_EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8),
              (5, 9), (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15),
              (15, 16), (13, 17), (17, 18), (18, 19), (19, 20), (0, 17)]


class Camera:
    """USB webcam through OpenCV, or the Pi camera module through Picamera2."""

    def __init__(self, picam, index, width, height):
        self.picam = None
        if picam:
            from picamera2 import Picamera2
            self.picam = Picamera2()
            # "RGB888" in libcamera terms is B,G,R byte order, i.e. OpenCV BGR.
            cfg = self.picam.create_preview_configuration(
                main={"format": "RGB888", "size": (width, height)})
            self.picam.configure(cfg)
            self.picam.start()
        else:
            self.cap = cv2.VideoCapture(index, cv2.CAP_V4L2)
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            if not self.cap.isOpened():
                raise SystemExit(f"cannot open /dev/video{index}")

    def read(self):
        if self.picam:
            return self.picam.capture_array()
        ok, frame = self.cap.read()
        return frame if ok else None

    def close(self):
        if self.picam:
            self.picam.stop()
        else:
            self.cap.release()


def load_landmarker():
    if not MODEL_PATH.exists():
        print(f"downloading {MODEL_URL}")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    opts = vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return vision.HandLandmarker.create_from_options(opts)


def text(img, s, org, scale=1.0, color=(255, 255, 255), thick=2):
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 0, 0), thick + 3, cv2.LINE_AA)
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_SIMPLEX, scale, color, thick, cv2.LINE_AA)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--picam", action="store_true", help="use Pi camera module (Picamera2)")
    ap.add_argument("--camera", type=int, default=0, help="USB webcam index")
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--height", type=int, default=480)
    args = ap.parse_args()

    cam = Camera(args.picam, args.camera, args.width, args.height)
    landmarker = load_landmarker()

    state, t_state = "idle", 0.0
    votes = Counter()
    player = computer = outcome = None
    score = Counter()
    t0 = time.monotonic()
    fps, t_prev = 0.0, t0

    try:
        while True:
            frame = cam.read()
            if frame is None:
                continue
            frame = cv2.flip(frame, 1)  # mirror so it feels natural
            h, w = frame.shape[:2]
            now = time.monotonic()

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            res = landmarker.detect_for_video(
                mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
                int((now - t0) * 1000))

            gesture = None
            if res.hand_landmarks:
                lm = res.hand_landmarks[0]
                pts = [(p.x * w, p.y * h) for p in lm]
                gesture = classify(pts)
                for a, b in HAND_EDGES:
                    cv2.line(frame, tuple(map(int, pts[a])), tuple(map(int, pts[b])), (0, 255, 0), 2)

            # --- game state machine ---
            elapsed = now - t_state
            if state == "countdown":
                n = int(COUNTDOWN_S - elapsed) + 1
                if elapsed >= COUNTDOWN_S:
                    state, t_state, votes = "capture", now, Counter()
                else:
                    text(frame, str(n), (w // 2 - 20, h // 2), 3.0, (0, 255, 255), 5)
            if state == "capture":
                if gesture:
                    votes[gesture] += 1
                text(frame, "SHOW!", (w // 2 - 80, h // 2), 2.0, (0, 0, 255), 4)
                if now - t_state >= CAPTURE_S:
                    player = votes.most_common(1)[0][0] if votes else None
                    computer = random.choice([ROCK, PAPER, SCISSORS])
                    outcome = judge(player, computer) if player else "no hand"
                    if player:
                        score[outcome] += 1
                    state, t_state = "result", now
            if state == "result":
                text(frame, f"YOU: {player or '?'}", (20, h - 90), 1.0)
                text(frame, f"CPU: {computer}", (20, h - 55), 1.0)
                color = {"win": (0, 255, 0), "lose": (0, 0, 255)}.get(outcome, (0, 255, 255))
                text(frame, outcome.upper(), (w // 2 - 70, h // 2), 2.0, color, 4)
                if now - t_state >= RESULT_S:
                    state = "idle"
            if state == "idle":
                text(frame, "SPACE: play  r: reset  q: quit", (20, h - 20), 0.6)

            fps = 0.9 * fps + 0.1 / max(now - t_prev, 1e-6)
            t_prev = now
            text(frame, f"W {score['win']}  L {score['lose']}  D {score['draw']}", (20, 35), 0.9)
            text(frame, f"now: {gesture or '-'}", (20, 70), 0.7, (200, 200, 200))
            text(frame, f"{fps:4.1f} fps", (w - 130, 35), 0.7, (200, 200, 200))
            cv2.imshow("Rock Paper Scissors", frame)

            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break
            if key == ord(" ") and state == "idle":
                state, t_state = "countdown", now
            if key == ord("r"):
                score.clear()
    finally:
        landmarker.close()
        cam.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
