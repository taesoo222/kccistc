"""One command per deliberate hold; neutral release rearms repeated commands."""
from control_settings import (PLAY_HOLD_SECONDS, PAUSE_HOLD_SECONDS,
                              MEDIA_SWITCH_SECONDS, MEDIA_COOLDOWN_SECONDS,
                              MAX_FRAME_GAP_SECONDS)


class MediaCommandDetector:
    def __init__(self):
        self.last_command = None
        self.cooldown_until = 0.0
        self.last_time = None
        self.release_since = None
        self.cancel_pending()

    def cancel_pending(self):
        self.candidate = None
        self.since = None
        self.progress = 0.0

    def update(self, gesture, now, blocked=False):
        if self.last_time is not None and now - self.last_time > MAX_FRAME_GAP_SECONDS:
            self.cancel_pending()
            self.last_command = None
            self.release_since = None
        self.last_time = now
        command = {"OPEN_PALM": "PLAY", "FIST": "PAUSE"}.get(gesture)
        # A brief classification glitch must not retrigger a held command.
        # A deliberate neutral pose / hand withdrawal does rearm it, without
        # changing MEDIA mode or requiring its V selection pose again.
        if blocked or command is None:
            if self.release_since is None:
                self.release_since = now
            if now - self.release_since >= 0.25:
                self.last_command = None
            self.cancel_pending()
            return None
        self.release_since = None
        if now < self.cooldown_until or command == self.last_command:
            self.cancel_pending()
            return None
        if command != self.candidate:
            self.candidate, self.since = command, now
        hold = PLAY_HOLD_SECONDS if command == "PLAY" else PAUSE_HOLD_SECONDS
        if self.last_command is not None:
            hold = max(hold, MEDIA_SWITCH_SECONDS)
        self.progress = min(1.0, (now - self.since) / hold)
        if now - self.since < hold:
            return None
        self.last_command = command
        self.cooldown_until = now + MEDIA_COOLDOWN_SECONDS
        self.cancel_pending()
        return command
