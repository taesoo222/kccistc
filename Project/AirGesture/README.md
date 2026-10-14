# AirGesture

A system that recognizes hand gestures with a camera on a Raspberry Pi and uses
them to control video playback and PowerPoint slides on a Windows PC.

- Period: until 2026.10 (team project, KCCI Seoul Technical Education Center)

## System Architecture

```
USB webcam (640x480)
   │
Raspberry Pi ── OpenCV capture ── MediaPipe Hands (21 joint landmarks)
   │
   ├─ Rule-based check : finger extended / bent from joint angles
   └─ MLP correction   : 63 → 64 → 32 → 1, probability of the VOLUME_READY pose
   │
Gesture and mode decision (MAIN / MEDIA / PPT)
   │  HTTP (Bearer token authentication)
Windows PC ── server.py ── YouTube playback control, PowerPoint slide control, status overlay
```

| Folder | Runs on | Contents |
|---|---|---|
| `AIRGESTURE/` | Raspberry Pi | Hand tracking, gesture decision, sending commands to the PC |
| `AirGesture_PC_bridge/` | Windows PC | Receiving commands, YouTube and PowerPoint control, overlay |
| `experiments/swipe_mlp/` | - | Swipe MLP classification experiment (not used in the final version) |

## Key Techniques

- **Joint-angle rule**: a finger counts as extended when its joint angle exceeds
  145° for the thumb (MCP-IP-TIP) or 155° for the other fingers (MCP-PIP-TIP).
- **MLP correction**: a 63-dimensional landmark-input MLP catches volume poses
  that the angle rule misses (probability ≥ 0.8). Inputs are translated to the
  wrist, normalized by hand size, and standardized to reduce the effect of hand
  position and camera distance. The 6,209 parameters are evaluated with NumPy
  matrix multiplication only, so it runs in real time on the Pi without
  TensorFlow.
- **Wrist swipe**: the hand tilt is the average MCP → DIP direction of four
  fingers; the change in tilt and its speed decide next / previous.

## Results

| Metric | Result |
|---|---|
| Processing speed | 16.3 fps on average (target 15 fps) |
| False input | 1 duplicate execution in 80 command gestures |
| Recognition stability | 98.7% success at 50 cm–1.5 m, at the center and corners of the frame |
| Volume gesture recognition | 75% with rules only → 88% with rules + MLP correction |

Limitation: Air Drawing was dropped from the final version because finger
jitter could not be compensated well enough.

## How to Run

### 1. Windows PC

Requires Python 3 for Windows, Microsoft Edge, and desktop PowerPoint.

```bat
cd AirGesture_PC_bridge
python -m pip install -r requirements.txt
python -m playwright install
python server.py
```

Note the **PC IP** and **BRIDGE KEY** printed in the terminal. The key file
(`bridge_key.txt`) is created automatically on the first run.

### 2. Raspberry Pi

```bash
cd AIRGESTURE
python -m pip install -r requirements.txt
python configure_bridge.py      # enter the PC IP and BRIDGE KEY → creates bridge_config.json
python main.py --camera 0 --headless
```

- The hand landmark model (`models/hand_landmarker.task`) is downloaded
  automatically on the first run.
- `--rule-only`: run with the angle rules only, without the MLP correction
- `--no-bridge`: run recognition only, without the PC

### 3. Tests

```bash
cd AIRGESTURE
python -m unittest discover -p "test_*.py"
```

`test_air_mouse.py` imports `pointer_receiver.py` from `AirGesture_PC_bridge/`,
so run the tests from a full checkout of this folder.
