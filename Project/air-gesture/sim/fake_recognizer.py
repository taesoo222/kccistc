"""Stand-in for the recognizer: type a key + Enter to send a gesture event over UDP.

    python fake_recognizer.py                 # sends to 127.0.0.1:5005
    python fake_recognizer.py --host 192.168.0.20

    m  MEDIA_ENTER     v  VOL_ENTER     p  PP_ENTER
    +  ROTATE_CW       -  ROTATE_CCW    f  OPEN_TO_FIST
    x  EXIT            q  quit
Several keys on one line are sent in order, e.g. "mv++" = media, volume, up, up.
"""
import argparse
import json
import socket
import time

KEYS = {
    "m": "MEDIA_ENTER", "v": "VOL_ENTER", "p": "PP_ENTER",
    "+": "ROTATE_CW", "-": "ROTATE_CCW", "f": "OPEN_TO_FIST", "x": "EXIT",
}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--gap", type=float, default=0.1, help="seconds between events on one line")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(__doc__)
    while True:
        line = input("> ").strip()
        if line == "q":
            break
        for ch in line:
            g = KEYS.get(ch)
            if g is None:
                print(f"  unknown key {ch!r}")
                continue
            sock.sendto(json.dumps({"g": g, "t": time.time()}).encode(), (args.host, args.port))
            print(f"  sent {g}")
            time.sleep(args.gap)
