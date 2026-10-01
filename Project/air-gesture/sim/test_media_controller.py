"""Unit tests for the media-controller state machine.

    cd Project/air-gesture && python -m unittest discover -s sim
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from media_controller import (EXIT, FIST, IDLE, MEDIA, MEDIA_ENTER, OPEN_PALM,  # noqa: E402
                              PLAYPAUSE, PP_ENTER, ROTATE_CCW, ROTATE_CW,
                              VOL_ENTER, VOLUME, MediaController)


class FakeClock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


class MediaControllerTest(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.sent = []
        self.mc = MediaController(self.sent.append, clock=self.clock, wall=self.clock)

    def ev(self, g, advance=1.0, **kw):
        self.clock.now += advance
        self.mc.on_event({"g": g, **kw})

    def cmds(self, name):
        return [c for c in self.sent if c["cmd"] == name]

    def test_enter_modes(self):
        self.ev(MEDIA_ENTER)
        self.assertEqual(self.mc.state, MEDIA)
        self.ev(VOL_ENTER)
        self.assertEqual(self.mc.state, VOLUME)
        self.ev(PP_ENTER)
        self.assertEqual(self.mc.state, PLAYPAUSE)
        self.assertEqual([c["mode"] for c in self.cmds("mode")], [MEDIA, VOLUME, PLAYPAUSE])

    def test_gestures_ignored_outside_their_mode(self):
        self.ev(VOL_ENTER)            # not in MEDIA yet
        self.ev(ROTATE_CW)
        self.ev(OPEN_PALM)
        self.ev(FIST)
        self.assertEqual(self.mc.state, IDLE)
        self.assertEqual(self.sent, [])
        self.ev(MEDIA_ENTER)
        self.ev(ROTATE_CW)            # MEDIA, but not VOLUME
        self.assertEqual(self.cmds("volume"), [])

    def test_volume_fixed_step(self):
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        self.ev(ROTATE_CW)
        self.ev(ROTATE_CW)
        self.ev(ROTATE_CCW)
        self.assertEqual([c["value"] for c in self.cmds("volume")], [60, 70, 60])
        self.assertEqual(self.mc.state, VOLUME)  # stays for further steps

    def test_volume_clamped(self):
        self.mc.on_player_status({"volume": 95})
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        self.ev(ROTATE_CW)
        self.ev(ROTATE_CW)            # already 100: nothing sent
        self.assertEqual([c["value"] for c in self.cmds("volume")], [100])

    def test_volume_cooldown(self):
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        self.ev(ROTATE_CW)
        self.ev(ROTATE_CW, advance=0.3)   # repeated within 0.7 s -> ignored
        self.ev(ROTATE_CW, advance=0.5)   # 0.8 s after the first -> applied
        self.assertEqual([c["value"] for c in self.cmds("volume")], [60, 70])

    def test_volume_follows_player_status(self):
        self.mc.on_player_status({"volume": 30})
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        self.ev(ROTATE_CCW)
        self.assertEqual(self.cmds("volume")[-1]["value"], 20)

    def test_fist_pauses_and_returns_to_media(self):
        self.ev(MEDIA_ENTER)
        self.ev(PP_ENTER)
        self.ev(FIST)
        self.assertEqual(self.cmds("pause"), [{"cmd": "pause"}])
        self.assertEqual(self.cmds("play"), [])
        self.assertEqual(self.mc.state, MEDIA)

    def test_open_palm_plays_and_returns_to_media(self):
        self.ev(MEDIA_ENTER)
        self.ev(PP_ENTER)
        self.ev(OPEN_PALM)
        self.assertEqual(self.cmds("play"), [{"cmd": "play"}])
        self.assertEqual(self.cmds("pause"), [])
        self.assertEqual(self.mc.state, MEDIA)

    def test_one_action_per_entry(self):
        self.ev(MEDIA_ENTER)
        self.ev(PP_ENTER)
        self.ev(FIST)
        self.ev(OPEN_PALM)                 # back in MEDIA: ignored
        self.assertEqual(self.cmds("play"), [])

    def test_playpause_cooldown(self):
        self.ev(MEDIA_ENTER)
        self.ev(PP_ENTER)
        self.ev(FIST)
        self.ev(PP_ENTER, advance=0.1)
        self.ev(OPEN_PALM, advance=0.1)    # 0.2 s after the pause
        self.assertEqual(self.cmds("play"), [])
        self.ev(PP_ENTER)
        self.ev(OPEN_PALM)                 # well after the cooldown
        self.assertEqual(self.cmds("play"), [{"cmd": "play"}])

    def test_exit_steps_back(self):
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        self.ev(EXIT)
        self.assertEqual(self.mc.state, MEDIA)
        self.ev(EXIT)
        self.assertEqual(self.mc.state, IDLE)

    def test_timeouts(self):
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        self.clock.now += 2.1
        self.mc.tick()
        self.assertEqual(self.mc.state, MEDIA)
        self.clock.now += 4.9
        self.mc.tick()
        self.assertEqual(self.mc.state, MEDIA)
        self.clock.now += 0.2
        self.mc.tick()
        self.assertEqual(self.mc.state, IDLE)

    def test_activity_keeps_mode_alive(self):
        self.ev(MEDIA_ENTER)
        self.ev(VOL_ENTER)
        for _ in range(5):
            self.ev(ROTATE_CW, advance=1.5)
            self.mc.tick()
        self.assertEqual(self.mc.state, VOLUME)

    def test_stale_event_dropped(self):
        self.clock.now += 1
        self.mc.on_event({"g": MEDIA_ENTER, "t": self.clock.now - 1.0})
        self.assertEqual(self.mc.state, IDLE)
        self.mc.on_event({"g": MEDIA_ENTER, "t": self.clock.now - 0.1})
        self.assertEqual(self.mc.state, MEDIA)


if __name__ == "__main__":
    unittest.main()
