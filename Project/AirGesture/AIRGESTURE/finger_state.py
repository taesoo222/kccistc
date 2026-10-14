import math
from config import FINGER_OPEN_ANGLE, THUMB_OPEN_ANGLE


def angle_deg(a, b, c):
    bax = a.x - b.x
    bay = a.y - b.y
    bcx = c.x - b.x
    bcy = c.y - b.y

    dot = bax * bcx + bay * bcy
    mag1 = math.hypot(bax, bay)
    mag2 = math.hypot(bcx, bcy)
    denom = mag1 * mag2

    if denom < 1e-8:
        return 0.0

    cos_theta = max(-1.0, min(1.0, dot / denom))
    return math.degrees(math.acos(cos_theta))


class FingerStateDetector:
    def detect(self, lm):
        # 엄지: 2(MCP)-3(IP)-4(TIP)
        # 나머지: MCP-PIP-TIP
        angles = {
            "thumb": angle_deg(lm[2], lm[3], lm[4]),
            "index": angle_deg(lm[5], lm[6], lm[8]),
            "middle": angle_deg(lm[9], lm[10], lm[12]),
            "ring": angle_deg(lm[13], lm[14], lm[16]),
            "pinky": angle_deg(lm[17], lm[18], lm[20]),
        }

        states = {
            "thumb": angles["thumb"] >= THUMB_OPEN_ANGLE,
            "index": angles["index"] >= FINGER_OPEN_ANGLE,
            "middle": angles["middle"] >= FINGER_OPEN_ANGLE,
            "ring": angles["ring"] >= FINGER_OPEN_ANGLE,
            "pinky": angles["pinky"] >= FINGER_OPEN_ANGLE,
        }

        return {
            "states": states,
            "angles": angles,
            "open_count": sum(states.values()),
        }
