"""One page per hand wave, with neutral return required before another page."""
import math
from collections import deque

from control_settings import (
    WAVE_ANGLE_DEGREES, WAVE_NEUTRAL_DEGREES, WAVE_ARM_SECONDS,
    WAVE_WINDOW_SECONDS, WAVE_MIN_SPEED, WAVE_COOLDOWN_SECONDS,
    MAX_FRAME_GAP_SECONDS,
)


def wrap(angle):
    return (angle + 180.0) % 360.0 - 180.0


class WristSwipeDetector:
    def __init__(self, angle_degrees=WAVE_ANGLE_DEGREES, continuous=False):
        self.continuous = continuous
        self.trigger_angle = min(angle_degrees, 18.0) if continuous else angle_degrees
        self.cooldown_until = 0.0
        self.reset()

    def reset(self):
        self.invalid_since = None
        self.baseline = None
        self.calibration = deque()
        self.history = deque()
        self.filtered = None
        self.last_time = None
        self.neutral_since = None
        self.armed = False
        self.tilt = 0.0

    @property
    def status(self):
        if self.baseline is None:
            return "HOLD PALM STILL"
        return "READY: WAVE LEFT/RIGHT" if self.armed else ("RETURN TO CENTER" if self.continuous else "RETURN TO CENTER AND HOLD")

    @staticmethod
    def hand_angle(lm, aspect_ratio):
        # Fit the average direction of FOUR fingers from MCP joints to DIP
        # joints. No wrist position or absolute screen movement is used.
        dx = sum(lm[b].x - lm[a].x for a, b in ((5, 7), (9, 11), (13, 15), (17, 19))) / 4
        dy = sum(lm[b].y - lm[a].y for a, b in ((5, 7), (9, 11), (13, 15), (17, 19))) / 4 * aspect_ratio
        palm_width = math.hypot(lm[5].x - lm[17].x, (lm[5].y - lm[17].y) * aspect_ratio)
        if not all(math.isfinite(v) for v in (dx, dy, palm_width)):
            return None
        if palm_width < 0.015 or math.hypot(dx, dy) < palm_width * 0.35:
            return None
        return math.degrees(math.atan2(dx, -dy))

    def update(self, lm, gesture, now, aspect_ratio=0.75):
        if gesture != "OPEN_PALM" or lm is None:
            # Preserve a short classification dropout, without inventing motion
            # samples. FIST/OK still clear motion immediately.
            if self.continuous and lm is not None and gesture == "UNKNOWN":
                if self.invalid_since is None:
                    self.invalid_since = now
                if now - self.invalid_since <= 0.18:
                    return None
            self.history.clear()
            self.calibration.clear()
            self.neutral_since = None
            if self.last_time is not None and now - self.last_time > MAX_FRAME_GAP_SECONDS:
                self.reset()
            return None
        if self.invalid_since is not None and now - self.invalid_since > 0.18:
            self.history.clear()
            self.calibration.clear()
        self.invalid_since = None
        angle = self.hand_angle(lm, aspect_ratio)
        if angle is None:
            return self.update(None, "UNKNOWN", now, aspect_ratio)
        if self.last_time is not None and now - self.last_time > MAX_FRAME_GAP_SECONDS:
            self.reset()
        dt = now - self.last_time if self.last_time is not None else 0.0
        if self.filtered is not None and abs(wrap(angle - self.filtered)) > 55:
            # Sudden tracking jumps cannot produce a page event.
            self.reset()
            return None
        alpha = 1 - math.exp(-max(dt, 0.001) / 0.045)
        self.filtered = angle if self.filtered is None else self.filtered + alpha * wrap(angle - self.filtered)
        self.last_time = now
        if self.baseline is None:
            self.calibration.append((now, self.filtered))
            while self.calibration and now - self.calibration[0][0] > WAVE_ARM_SECONDS + 0.1:
                self.calibration.popleft()
            offsets = [wrap(value - self.filtered) for _, value in self.calibration]
            if max(offsets) - min(offsets) > (10 if self.continuous else 6):
                self.calibration.clear()
                return None
            if self.calibration and now - self.calibration[0][0] >= WAVE_ARM_SECONDS:
                self.baseline = self.filtered
                self.armed = now >= self.cooldown_until
            return None

        previous_tilt = self.tilt
        self.tilt = wrap(self.filtered - self.baseline)
        if not self.armed:
            if self.continuous:
                # Crossing neutral rearms without a center hold. Merely
                # returning from an extreme cannot trigger the opposite side.
                at_center = abs(self.tilt) <= WAVE_NEUTRAL_DEGREES
                crossed = previous_tilt * self.tilt < 0
                if at_center or crossed:
                    self.armed = True
                    self.history.clear()
                    self.history.append((now, self.tilt if at_center else 0.0))
                return None
            if abs(self.tilt) <= WAVE_NEUTRAL_DEGREES and now >= self.cooldown_until:
                if self.neutral_since is None:
                    self.neutral_since = now
                elif now - self.neutral_since >= WAVE_ARM_SECONDS:
                    self.armed = True
                    self.history.clear()
            else:
                self.neutral_since = None
            return None

        # Idle frames at center must not dilute the speed of a new wave.
        if self.continuous and abs(self.tilt) < 3.0:
            self.history.clear()
        self.history.append((now, self.tilt))
        while self.history and now - self.history[0][0] > (0.80 if self.continuous else WAVE_WINDOW_SECONDS):
            self.history.popleft()
        if now < self.cooldown_until or len(self.history) < 3 or abs(self.tilt) < self.trigger_angle:
            return None
        elapsed = now - self.history[0][0]
        change = self.tilt - self.history[0][1]
        if elapsed <= 0 or abs(change) < self.trigger_angle * 0.75:
            return None
        if abs(change) / elapsed < (35.0 if self.continuous else WAVE_MIN_SPEED) or change * self.tilt <= 0:
            return None
        self.armed = False
        self.neutral_since = None
        self.cooldown_until = now + (0.12 if self.continuous else WAVE_COOLDOWN_SECONDS)
        self.history.clear()
        return "SWIPE_RIGHT" if self.tilt > 0 else "SWIPE_LEFT"
