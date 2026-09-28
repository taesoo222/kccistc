"""Sanity checks for gesture.classify with synthetic hand poses (no camera)."""
from gesture import PAPER, ROCK, SCISSORS, classify, judge


def hand(extended):
    """Upright hand, wrist at (0, 0), fingers pointing to -y."""
    pts = [(0.0, 0.0)] * 21
    for i, name in enumerate(["index", "middle", "ring", "pinky"]):
        x = -30 + 20 * i
        mcp, pip, dip, tip = 5 + 4 * i, 6 + 4 * i, 7 + 4 * i, 8 + 4 * i
        pts[mcp] = (x, -80)
        pts[pip] = (x, -115)
        if name in extended:
            pts[dip], pts[tip] = (x, -140), (x, -160)
        else:  # curled back toward the palm
            pts[dip], pts[tip] = (x, -100), (x, -75)
    return pts


def test_classify():
    assert classify(hand(set())) == ROCK
    assert classify(hand({"index", "middle", "ring", "pinky"})) == PAPER
    assert classify(hand({"index", "middle"})) == SCISSORS
    assert classify(hand({"index"})) is None


def test_rotation_invariant():
    # Same scissors hand turned 90 degrees (fingers pointing right).
    pts = [(-y, x) for x, y in hand({"index", "middle"})]
    assert classify(pts) == SCISSORS


def test_judge():
    assert judge(ROCK, SCISSORS) == "win"
    assert judge(ROCK, PAPER) == "lose"
    assert judge(PAPER, PAPER) == "draw"


if __name__ == "__main__":
    test_classify(); test_rotation_invariant(); test_judge()
    print("ok")
