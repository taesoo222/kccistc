"""MAIN-only pose check; static/MLP gesture inputs remain unchanged."""
import math


def main_return_pose(fingers, landmarks, aspect_ratio=0.75):
    states = fingers['states']
    angles = fingers.get('angles', {})
    four = all(states[name] or angles.get(name, 0) >= 145.0
               for name in ('index', 'middle', 'ring', 'pinky'))
    # Thumb tip must be near the palm base segment, not spread outside it.
    a, b, tip = landmarks[5], landmarks[17], landmarks[4]
    vx, vy = b.x-a.x, (b.y-a.y)*aspect_ratio
    tx, ty = tip.x-a.x, (tip.y-a.y)*aspect_ratio
    width2 = vx*vx + vy*vy
    folded = not states['thumb']
    if width2 > 1e-6:
        along = (tx*vx + ty*vy)/width2
        closest = max(0.0, min(1.0, along))
        distance = math.hypot(tx-closest*vx, ty-closest*vy)/math.sqrt(width2)
        folded = -0.15 <= along <= 1.25 and distance <= 0.75
    return {'matched': four and folded, 'four': four, 'thumb_folded': folded}
