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

---

## Version 2: `rps_tflite.py` (cvzone + your own TFLite model)

Same game flow, but recognition follows the class reference code:
cvzone `HandDetector` bbox → crop (+30 px on left/top/right) → pad to a white square
→ TFLite classifier (`0 scissors, 1 rock, 2 paper`).

```bash
pip install ai-edge-litert cvzone
python rps_tflite.py --model sample_01.tflite   # model file is not committed (*.tflite ignored)
```

Class order is fixed in `common.py` (`CLASSES`). The crop / square preprocessing also lives
there and is shared by the game, `collect.py` and training, so train and inference stay identical.

## Adding training data from the current camera

```bash
# 1) on the Pi (or any PC with the same camera): collect
python collect.py --out data_new
#    1 = scissors, 2 = rock, 3 = paper  (toggle continuous save), 0/SPACE pause, q quit
#    files: data_new/<class>/<sessionID>_<n>.jpg

# 2) on a PC / Colab: train MobileNetV3-Small on old + new data
pip install -r requirements-train.txt
python train_mobilenet.py --data dataset_old data_new --out rps_model.tflite

# 3) back on the Pi
python rps_tflite.py --model rps_model.tflite
```

- The validation split is done per capture session (the sessionID in the file name), because
  consecutive frames are near-duplicates and a random split would inflate val accuracy.
  Run `collect.py` several times (different lighting/place/person) to get several sessions.
- Training prints a confusion matrix; collect more images of the classes that get confused.
- `--quant dynamic` (default) quantizes weights only; the game code needs no change.
  Full int8 quantization is not offered: with TF 2.21 + ai-edge-litert 2.2.0 the resulting
  MobileNetV3 model failed to load in the XNNPACK delegate (checked on x86).
