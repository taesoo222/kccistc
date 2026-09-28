# rps_rpi5 — webcam rock-paper-scissors on Raspberry Pi 5

The webcam frame goes through MediaPipe **HandLandmarker** (21 hand landmarks),
then `gesture.py` classifies the pose with rules (no training needed):

| Pose | Rule (index, middle, ring, pinky) |
|------|-----------------------------------|
| rock     | all 4 folded |
| paper    | all 4 extended |
| scissors | index + middle extended, ring + pinky folded |

A finger counts as "extended" when `dist(wrist, tip) > 1.15 * dist(wrist, PIP)`,
so it does not depend on which way the hand is rotated. The thumb is ignored.

## Setup (Raspberry Pi OS 64-bit)

```bash
sudo apt install -y python3-venv python3-picamera2   # picamera2 only for the Pi camera module
cd Project/rps_rpi5
python3 -m venv --system-site-packages .venv          # system-site-packages lets the venv see picamera2
source .venv/bin/activate
pip install -r requirements.txt
```

`hand_landmarker.task` (~7.5 MB) downloads automatically on first run.

## Run

```bash
python rps_game.py            # USB webcam (/dev/video0)
python rps_game.py --camera 1 # a different USB webcam
python rps_game.py --picam    # Raspberry Pi camera module (CSI)
```

Keys: `SPACE` start round (3-2-1, then show your hand), `r` reset score, `q`/`ESC` quit.
Needs a desktop session (the window uses `cv2.imshow`).

## Test (no camera needed)

```bash
python test_gesture.py
```

## Tuning

- A finger is misread → change `EXTEND_RATIO` in `gesture.py`.
- The "now:" line on screen shows the live classification; `-` means no hand or an unclear pose.
- Slow → lower resolution with `--width 320 --height 240`.
