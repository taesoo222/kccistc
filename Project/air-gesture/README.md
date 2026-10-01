# air-gesture — media controller (apply layer)

Turns recognized gestures into YouTube playback control on a PC, using the
**YouTube IFrame Player API**. The Pi serves the player page; the PC only needs
a browser.

```
camera -> Pi: recognizer --UDP JSON--> server.py (MediaController) --WebSocket--> PC browser: player.html
```

## Layout

```
src/media_controller.py   state machine: gesture events -> player commands (no I/O)
src/server.py             HTTP (player page) + WebSocket (to page) + UDP (from recognizer)
src/web/player.html       IFrame player, executes commands, mode/volume overlay
sim/fake_recognizer.py    type keys to send gesture events (no camera needed)
sim/test_media_controller.py
```

## Run

```bash
# on the Pi
pip install -r requirements.txt
cd src && python server.py            # add -v for debug logs

# on the PC (same LAN): open http://<pi-ip>:8080 and click once to start

# on the Pi, second terminal (until the real recognizer is ready)
python sim/fake_recognizer.py         # e.g. "mv++" then "pf"
```

Tests: `python -m unittest discover -s sim`

## Gesture event contract (recognizer -> UDP 127.0.0.1:5005)

One JSON datagram per **completed** gesture: `{"g": "<NAME>", "t": <time.time()>}`.
`t` is optional; events older than 0.3 s are dropped.

| `g`            | Meaning                                   | Valid in   |
|----------------|-------------------------------------------|------------|
| `MEDIA_ENTER`  | enter media controller                    | IDLE       |
| `VOL_ENTER`    | enter volume mode                         | MEDIA, PLAYPAUSE |
| `PP_ENTER`     | enter play/pause mode                     | MEDIA, VOLUME |
| `ROTATE_CW`    | inverted-L rotated right (user's view) -> volume +10 | VOLUME |
| `ROTATE_CCW`   | inverted-L rotated left -> volume -10     | VOLUME     |
| `OPEN_TO_FIST` | open hand -> fist: play/pause, back to MEDIA | PLAYPAUSE |
| `EXIT`         | one level up (optional)                   | any but IDLE |

Events outside their mode are ignored. Rotation direction is defined from the
**user's** point of view; the recognizer must correct for camera mirroring.

## Behaviour (defaults in `media_controller.Config`)

- Volume: fixed step 10, clamped 0..100, 0.7 s cooldown between steps.
  Steps start from the volume the page reports, so manual slider changes are respected.
- Play/pause: page checks `getPlayerState()` and calls `playVideo()`/`pauseVideo()`; 1 s cooldown.
- Timeouts: VOLUME/PLAYPAUSE -> MEDIA after 2 s idle, MEDIA -> IDLE after 5 s.

## Notes

- Browsers block playback with sound until the page has been clicked once; hence the start overlay.
- Some videos forbid embedding (player error 101/150).
- `setVolume` changes the player volume, not the Windows system volume.
