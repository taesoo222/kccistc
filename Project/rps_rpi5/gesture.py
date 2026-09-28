"""Rule-based rock/paper/scissors classifier on MediaPipe hand landmarks.

Landmark indices follow the MediaPipe 21-point hand model:
  0 wrist, 5/9/13/17 finger MCPs, 6/10/14/18 PIPs, 8/12/16/20 tips.
Only index..pinky are used; the thumb is ignored because its pose is
ambiguous between rock and scissors.
"""
from math import dist

WRIST = 0
FINGERS = {  # name: (pip, tip)
    "index": (6, 8),
    "middle": (10, 12),
    "ring": (14, 16),
    "pinky": (18, 20),
}
# A finger counts as extended when its tip is this much farther from the
# wrist than its PIP joint. Distance-based, so hand rotation does not matter.
EXTEND_RATIO = 1.15

ROCK, PAPER, SCISSORS = "rock", "paper", "scissors"


def extended_fingers(points):
    """points: sequence of 21 (x, y) tuples. Returns dict finger -> bool."""
    w = points[WRIST]
    return {
        name: dist(w, points[tip]) > dist(w, points[pip]) * EXTEND_RATIO
        for name, (pip, tip) in FINGERS.items()
    }


def classify(points):
    """Returns ROCK, PAPER, SCISSORS or None when the pose is unclear."""
    ext = extended_fingers(points)
    up = sum(ext.values())
    if up == 0:
        return ROCK
    if up == 4:
        return PAPER
    if ext["index"] and ext["middle"] and not ext["ring"] and not ext["pinky"]:
        return SCISSORS
    return None


BEATS = {ROCK: SCISSORS, PAPER: ROCK, SCISSORS: PAPER}


def judge(player, computer):
    """Returns 'win', 'lose' or 'draw' from the player's point of view."""
    if player == computer:
        return "draw"
    return "win" if BEATS[player] == computer else "lose"
