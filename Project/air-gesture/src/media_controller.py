"""Media-controller state machine: gesture events in, player commands out.

Pure logic with no I/O, so it can be unit-tested with a fake clock.
The recognizer only reports *what it sees*; this module decides what that
means in the current mode.

    IDLE --MEDIA_ENTER--> MEDIA --VOL_ENTER--> VOLUME     ROTATE_CW / ROTATE_CCW -> volume +/- one step
                            |   --PP_ENTER---> PLAYPAUSE  OPEN_TO_FIST -> toggle, back to MEDIA
    VOLUME/PLAYPAUSE --EXIT or idle timeout--> MEDIA --EXIT or idle timeout--> IDLE

Commands sent to the player page (dicts, JSON-encoded by the server):
    {"cmd": "mode",   "mode": "VOLUME"}
    {"cmd": "volume", "value": 40}
    {"cmd": "toggle"}
"""
import logging
import time
from dataclasses import dataclass

log = logging.getLogger(__name__)

IDLE, MEDIA, VOLUME, PLAYPAUSE = "IDLE", "MEDIA", "VOLUME", "PLAYPAUSE"

# Gesture event names agreed with the recognizer. One event per completed gesture.
MEDIA_ENTER = "MEDIA_ENTER"
VOL_ENTER = "VOL_ENTER"
PP_ENTER = "PP_ENTER"
ROTATE_CW = "ROTATE_CW"        # clockwise from the user's point of view -> volume up
ROTATE_CCW = "ROTATE_CCW"      # counter-clockwise -> volume down
OPEN_TO_FIST = "OPEN_TO_FIST"
EXIT = "EXIT"


@dataclass
class Config:
    volume_step: int = 10
    volume_cooldown_s: float = 0.7    # one rotation = one step, even if the recognizer repeats it
    toggle_cooldown_s: float = 1.0
    submode_timeout_s: float = 2.0    # VOLUME / PLAYPAUSE -> MEDIA
    media_timeout_s: float = 5.0      # MEDIA -> IDLE
    stale_event_s: float = 0.3        # drop events whose "t" is older than this


class MediaController:
    def __init__(self, send, cfg=None, clock=time.monotonic, wall=time.time):
        self.send = send
        self.cfg = cfg or Config()
        self.clock = clock
        self.wall = wall

        self.state = IDLE
        self.volume = 50              # last known player volume (0..100)
        self._last_volume_step = float("-inf")
        self._last_toggle = float("-inf")
        self.last_activity = clock()

        self._dispatch = {
            (IDLE, MEDIA_ENTER): lambda ev, now: self._set_state(MEDIA),
            (MEDIA, MEDIA_ENTER): lambda ev, now: None,  # just refreshes the timeout
            (MEDIA, VOL_ENTER): lambda ev, now: self._set_state(VOLUME),
            (PLAYPAUSE, VOL_ENTER): lambda ev, now: self._set_state(VOLUME),
            (MEDIA, PP_ENTER): lambda ev, now: self._set_state(PLAYPAUSE),
            (VOLUME, PP_ENTER): lambda ev, now: self._set_state(PLAYPAUSE),
            (VOLUME, ROTATE_CW): lambda ev, now: self._step_volume(+1, now),
            (VOLUME, ROTATE_CCW): lambda ev, now: self._step_volume(-1, now),
            (PLAYPAUSE, OPEN_TO_FIST): self._on_toggle,
            (MEDIA, EXIT): lambda ev, now: self._set_state(IDLE),
            (VOLUME, EXIT): lambda ev, now: self._set_state(MEDIA),
            (PLAYPAUSE, EXIT): lambda ev, now: self._set_state(MEDIA),
        }

    # ---- inputs -------------------------------------------------------

    def on_event(self, ev):
        """Handle one gesture event dict, e.g. {"g": "ROTATE_CW", "t": 1727750000.12}."""
        g = ev.get("g")
        t = ev.get("t")
        if t is not None and self.wall() - t > self.cfg.stale_event_s:
            log.debug("drop stale event %s", ev)
            return
        handler = self._dispatch.get((self.state, g))
        if handler is None:
            log.debug("ignore %s in %s", g, self.state)
            return
        now = self.clock()
        self.last_activity = now
        handler(ev, now)

    def on_player_status(self, status):
        """Sync with what the page reports, e.g. {"volume": 30, "state": 1}.

        Keeps steps relative to the real volume even if someone used the
        player's own slider.
        """
        if "volume" in status:
            self.volume = int(status["volume"])

    def tick(self):
        """Call periodically (a few times per second) to apply idle timeouts."""
        now = self.clock()
        idle = now - self.last_activity
        if self.state in (VOLUME, PLAYPAUSE) and idle > self.cfg.submode_timeout_s:
            self._set_state(MEDIA)
            self.last_activity = now  # MEDIA timeout counts from here
        elif self.state == MEDIA and idle > self.cfg.media_timeout_s:
            self._set_state(IDLE)

    # ---- actions ------------------------------------------------------

    def _set_state(self, new):
        if new == self.state:
            return
        log.info("%s -> %s", self.state, new)
        self.state = new
        self.send({"cmd": "mode", "mode": new})

    def _step_volume(self, direction, now):
        if now - self._last_volume_step < self.cfg.volume_cooldown_s:
            log.debug("volume step ignored (cooldown)")
            return
        self._last_volume_step = now
        new = min(100, max(0, self.volume + direction * self.cfg.volume_step))
        if new == self.volume:
            return  # already at 0 or 100
        self.volume = new
        self.send({"cmd": "volume", "value": new})

    def _on_toggle(self, ev, now):
        if now - self._last_toggle >= self.cfg.toggle_cooldown_s:
            self._last_toggle = now
            # The page checks getPlayerState() and plays or pauses accordingly.
            self.send({"cmd": "toggle"})
        self._set_state(MEDIA)
