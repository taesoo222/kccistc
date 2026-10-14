import argparse
import base64
import json
from urllib.parse import urlsplit
from preview_stream import PreviewStream
from air_mouse import AirMouse
from pointer_bridge import PointerBridge
import time
import cv2

from camera import Camera
from hand_tracker import HandTracker, draw_hand
from finger_state import FingerStateDetector
from gesture_controller import GestureController
from volume_classifier import VolumeReadyMLP, DEFAULT_MODEL
from config import CAMERA_INDEX, FRAME_WIDTH, FRAME_HEIGHT, TARGET_FPS, MIRROR
from command_bridge import CommandBridge, DEFAULT_CONFIG
from wrist_swipe import WristSwipeDetector
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description="AirGesture: stable media commands and wrist-wave PPT")
    p.add_argument("--camera", type=int, default=CAMERA_INDEX)
    p.add_argument("--width", type=int, default=FRAME_WIDTH)
    p.add_argument("--height", type=int, default=FRAME_HEIGHT)
    p.add_argument("--fps", type=int, default=TARGET_FPS)
    p.add_argument("--preview-fps", type=int, choices=range(1, 31), default=25,
                   metavar="1-30", help="Overlay FPS cap; independent of camera FPS")
    p.add_argument("--no-mirror", action="store_true")
    p.add_argument("--rule-only", action="store_true")
    p.add_argument("--volume-model", default=str(DEFAULT_MODEL))
    p.add_argument("--bridge-config", type=Path, default=DEFAULT_CONFIG)
    p.add_argument("--no-bridge", action="store_true", help="Recognition only; do not send PC commands")
    p.add_argument('--headless', action='store_true', help='No local OpenCV/X11 window')
    p.add_argument('--legacy-preview', action='store_true', help='Also send JPEG telemetry for the original overlay (up to 20 FPS)')
    p.add_argument('--stream-port', type=int, default=8767)
    p.add_argument('--no-stream', action='store_true')
    p.add_argument('--swipe-log', type=Path, help='Write a swipe tuning log (CSV) to this file')
    p.add_argument('--pointer-url', help='PC mouse receiver, default: configured PC bridge URL')
    return p.parse_args()


def load_classifier(args):
    if args.rule_only:
        print("[MLP] Disabled: original rules only")
        return None
    try:
        model = VolumeReadyMLP(args.volume_model)
        print(f"[MLP] Loaded {model.path} (threshold={model.threshold:.2f})")
        return model
    except (OSError, ValueError, KeyError) as error:
        print(f"[MLP] Model unavailable; using original rules: {error}")
        return None



def draw_status_panel(frame, lines):
    """Keep status text outside the video, at a readable fixed font size."""
    panel_width, padding, row_height = 460, 20, 32
    font, scale = cv2.FONT_HERSHEY_SIMPLEX, 0.62
    rows = []
    for index, line in enumerate(lines):
        current = ""
        for word in line.split():
            candidate = f"{current} {word}".strip()
            if current and cv2.getTextSize(candidate, font, scale, 1)[0][0] > panel_width - 2 * padding:
                rows.append((index, current))
                current = word
            else:
                current = candidate
        rows.append((index, current))
    height = max(frame.shape[0], 600, 70 + len(rows) * row_height)
    top = (height - frame.shape[0]) // 2
    canvas = cv2.copyMakeBorder(frame, top, height-frame.shape[0]-top, 0, panel_width,
                                cv2.BORDER_CONSTANT, value=(28, 28, 28))
    left = frame.shape[1]
    cv2.rectangle(canvas, (left, 0), (canvas.shape[1]-1, height-1), (28, 28, 28), -1)
    cv2.putText(canvas, "AIRGESTURE STATUS", (left+padding, 32), font,
                0.70, (240, 240, 240), 1, cv2.LINE_AA)
    cv2.line(canvas, (left+padding, 47), (canvas.shape[1]-padding, 47), (85, 85, 85), 1)
    for row, (index, text) in enumerate(rows):
        color = (100, 225, 255) if index == 6 else (240, 240, 240)
        cv2.putText(canvas, text, (left+padding, 78+row*row_height), font,
                    scale, color, 1, cv2.LINE_AA)
    return canvas


def main():
    args = parse_args()
    model = load_classifier(args)
    bridge = None
    if not args.no_bridge and args.bridge_config.exists():
        try:
            bridge = CommandBridge(args.bridge_config)
        except (OSError, ValueError, KeyError) as error:
            print(f"[PC] Configuration error: {error}")
    controller = GestureController()
    swipe_log = None
    if args.swipe_log:
        swipe_log = open(args.swipe_log, 'w', encoding='utf-8')
        swipe_log.write('time,pose,s,center,offset,speed,state,event\n')
        WristSwipeDetector.debug = lambda *row: swipe_log.write(','.join(str(v) for v in row) + '\n')
        print(f'[SWIPE LOG] {args.swipe_log}')
    fingers = FingerStateDetector()
    camera = tracker = stream = pointer = None
    mouse = AirMouse()
    camera_sequence = 0
    window = "AirGesture - Media / Wrist Wave PPT"
    last_command, command_time = "NONE", -10.0
    preview_time=-10.0
    last_swipe, last_swipe_time, swipe_seq, force_publish = '', -10.0, 0, False
    start = time.monotonic()
    last_timestamp = -1
    previous, fps = time.perf_counter(), 0.0
    print("1 finger 1.0s -> MOUSE | 2 fingers -> MEDIA | 3 fingers -> PPT")
    print("Thumb closed + other 4 fingers 1.2s -> MAIN")
    print("After selecting a mode, release the selection pose for 0.35s.")
    print("MEDIA: palm 0.4s=PLAY; fist=PAUSE; volume step=10.")
    print("SWIPE: OK 0.35s=enter; MEDIA thumb+index+pinky 0.4s=exit only; PPT fist 0.35s=exit; cooldown 0.8s.")
    print("[PC] Bridge enabled" if bridge else "[PC] Recognition only. Run python configure_bridge.py to connect the PC.")
    print("Q / ESC / Ctrl+C to quit.")
    try:
        camera = Camera(args.camera, args.width, args.height, args.fps)
        if not args.no_stream or not args.no_bridge:
            if args.bridge_config.exists():
                settings = json.loads(args.bridge_config.read_text(encoding='utf-8'))
                token = settings['token']
                if not isinstance(token, str) or len(token) < 16:
                    raise ValueError('Bridge token must be at least 16 characters')
                if not args.no_stream:
                    stream = PreviewStream(camera, token, port=args.stream_port,
                                           fps=args.preview_fps, mirror=MIRROR and not args.no_mirror)
                    print(f'[PREVIEW] Direct camera stream on port {args.stream_port}')
                if not args.no_bridge:
                    host = urlsplit(settings['pc_url']).hostname
                    pointer = PointerBridge(args.pointer_url or settings['pc_url'], token)
            else:
                print('[PREVIEW] Configure bridge_config.json to enable authenticated streaming')
        tracker = HandTracker()
        if not args.headless:
            cv2.namedWindow(window, cv2.WINDOW_NORMAL)
            cv2.resizeWindow(window, args.width + 460, max(args.height, 600))
        while True:
            camera_sequence, frame = camera.snapshot(camera_sequence)
            if frame is None:
                print("[CAMERA] Frame read failed")
                break
            if MIRROR and not args.no_mirror:
                frame = cv2.flip(frame, 1)
            now = time.monotonic()
            if bridge:
                for command, reply in bridge.drain_results():
                    print(f"[PC] {command}: {reply.get('detail', '')}", flush=True)
                    if not reply.get("ok") and command == controller.media.last_command:
                        # A failed PLAY/PAUSE must be allowed again after a
                        # deliberate hold. Never automatically retry an event.
                        controller.media.last_command = None
                        controller.media.cancel_pending()
                        controller.media.cooldown_until = now + 1.0
            timestamp = max(last_timestamp + 1, int((now - start) * 1000))
            last_timestamp = timestamp
            result = tracker.process(frame, timestamp)
            frame, hand = draw_hand(frame, result, draw=not args.headless)
            finger_result, landmarks, score = None, None, None
            if hand is not None:
                landmarks = hand["landmarks"]
                finger_result = fingers.detect(landmarks)
                if model is not None:
                    try:
                        score = model.predict_landmarks(landmarks, frame.shape[1], frame.shape[0])
                    except ValueError:
                        pass
            state = controller.update(finger_result, landmarks, score,
                                      model.threshold if model else 0.8, now,
                                      frame.shape[0] / frame.shape[1])
            pointer_state = mouse.update(landmarks, finger_result,
                                         state['mode'] == 'MOUSE' and state['enabled'], now,
                                         frame.shape[0] / frame.shape[1])
            if pointer:
                pointer.publish(pointer_state)
            if state["mode_event"]:
                if bridge:
                    bridge.cancel_pending(preserve_mode=False)
                    bridge.send('MODE_' + state['mode'])
                print(f"[MODE] {state['mode_event']}")
                last_command = "NONE"
            if state.get("swipe_event"):
                last_swipe, last_swipe_time, force_publish = state["swipe_event"], now, True
                swipe_seq += 1
                print(f"[SWIPE] {last_swipe}", flush=True)
            if state["command"]:
                last_command, command_time = state["command"], now
                print(f"[COMMAND] {last_command}", flush=True)
                if bridge:
                    bridge.send(last_command)
            elif hand is None and bridge:
                bridge.cancel_pending()
            current = time.perf_counter()
            instant = 1 / max(current - previous, 1e-6)
            fps = instant if fps == 0 else fps * 0.9 + instant * 0.1
            previous = current
            modes, media = controller.modes, controller.media
            publish_gap = 1 / args.preview_fps if args.legacy_preview else (.1 if state['swipe_active'] else .2)
            if bridge and (force_publish or now-preview_time >= publish_gap):
                preview_time=now
                force_publish=False
                encoded_ok, encoded = False, None
                if args.legacy_preview:
                    small=cv2.resize(frame,(320,240))
                    encoded_ok,encoded=cv2.imencode('.jpg',small,[cv2.IMWRITE_JPEG_QUALITY,55])
                bridge.publish_state({'mode':state['mode'],'gesture':state['gesture'],
                    'hand':hand is not None,'enabled':state['enabled'],'volume_lock':state['volume_lock'],
                    'swipe_active':state['swipe_active'],'swipe_status':state['swipe_status'],
                    'last_swipe':last_swipe if now-last_swipe_time < 1.5 else '',
                    'swipe_seq':swipe_seq,'swipe_tilt':state['swipe_tilt'],
                    'last_command':last_command if now-command_time < 1.5 else '',
                    'release_gate':modes.release_gate,'selector':modes.get_candidate_label(),
                    'progress':modes.get_candidate_progress(now),'bridge_status':bridge.status,
                    'preview_transport':'mjpeg' if stream else 'legacy', 'stream_port':args.stream_port,
                    'pointer_status':pointer.status if pointer else 'OFF',
                    'frame':base64.b64encode(encoded).decode('ascii') if encoded_ok else ''})
            lock = "RELEASE SELECT POSE" if modes.release_gate else (
                "VOLUME LOCK" if state["volume_lock"] else
                "ENABLED" if state["enabled"] else "BLOCKED")
            lines = [
                f"MODE: {state['mode']} | {lock}",
                f"FPS: {fps:.1f} | HAND: {'FOUND' if hand else 'NOT FOUND'}",
                f"POSE: {state['gesture']}",
                f"SELECT: {modes.get_candidate_label()} {100*modes.get_candidate_progress(now):.0f}%",
                (f"RETURN: 4 fingers={'YES' if controller.return_pose['four'] else 'NO'} "
                 f"thumb folded={'YES' if controller.return_pose['thumb_folded'] else 'NO'}")
                if controller.return_pose else "RETURN: NO HAND",
                f"MEDIA: {media.candidate or '-'} {100*media.progress:.0f}%",
                f"WAVE: {state['swipe_status']}",
                f"COMMAND: {last_command if now-command_time < 1.5 else '-'}",
                f"MLP: {score:.3f} / {model.threshold:.2f}" if score is not None else
                ("MLP: WAITING" if model else "MLP: RULE ONLY"),
                "1: MOUSE | 2: MEDIA | 3: PPT",
                "MOUSE: pinch index=drag/click; middle=right",
                "MOUSE: two fingers move up/down=scroll",
                "Thumb closed + 4 fingers (1.2s): MAIN",
                "Q / ESC: quit",
                f"PC: {bridge.status}" if bridge else "PC: NOT CONNECTED (recognition only)",
            ]
            if args.headless:
                continue
            display = draw_status_panel(frame, lines)
            cv2.imshow(window, display)
            if cv2.waitKey(1) & 0xFF in (ord("q"), ord("Q"), 27):
                break
            if cv2.getWindowProperty(window, cv2.WND_PROP_VISIBLE) < 1:
                break
    except KeyboardInterrupt:
        print("\n[EXIT] Stopped")
    finally:
        if swipe_log:
            swipe_log.close()
        if pointer:
            pointer.close()
        if stream:
            stream.close()
        if bridge:
            bridge.close()
        if tracker is not None:
            tracker.close()
        if camera is not None:
            camera.release()
        if not args.headless:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
