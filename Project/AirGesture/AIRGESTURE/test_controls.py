import math
import unittest
from types import SimpleNamespace

from gesture_controller import GestureController
from media_commands import MediaCommandDetector
from mode_manager import ModeManager
from motion_detector import MotionDetector
from wrist_swipe import WristSwipeDetector


def fingers(*opened):
    return {"states": {name: name in opened for name in ("thumb", "index", "middle", "ring", "pinky")}}


def hand(angle=0, shift=0, scale=1):
    points = [SimpleNamespace(x=0.5, y=0.8, z=0) for _ in range(21)]
    points[4] = SimpleNamespace(x=0.48, y=0.62, z=0)
    theta = math.radians(angle)
    for a, b, x in ((5, 7, -0.09), (9, 11, -0.03), (13, 15, 0.03), (17, 19, 0.09)):
        for idx, y in ((a, 0), (b, -0.18)):
            rx = (x * math.cos(theta) - y * math.sin(theta)) * scale
            ry = (x * math.sin(theta) + y * math.cos(theta)) * scale
            points[idx] = SimpleNamespace(x=0.5 + rx + shift, y=0.6 + ry / 0.75, z=0)
    return points


class ModeTests(unittest.TestCase):
    def test_two_media_three_ppt_and_four_main(self):
        for pose, mode in ((fingers("index", "middle"), "MEDIA"),
                           (fingers("index", "middle", "ring"), "PPT")):
            m = ModeManager()
            m.update(pose, now=0)
            self.assertEqual(m.update(pose, now=1.01), f"MAIN->{mode}")
            m.update(fingers(), now=1.1)
            m.update(fingers(), now=1.46)
            self.assertTrue(m.commands_enabled)
            three = fingers("index", "middle", "ring")
            m.update(three, now=2)
            m.update(three, now=4)
            self.assertEqual(m.mode, mode)
            four = fingers("index", "middle", "ring", "pinky")
            m.update(four, now=5)
            self.assertFalse(m.commands_enabled)
            self.assertIsNone(m.update(four, now=6.1))
            self.assertEqual(m.update(four, now=6.21), f"{mode}->MAIN")

    def test_palm_not_exit_and_lost_hand_breaks_hold(self):
        m = ModeManager()
        m.mode = "MEDIA"
        palm = fingers("thumb", "index", "middle", "ring", "pinky")
        m.update(palm, now=0)
        m.update(palm, now=2)
        self.assertEqual(m.mode, "MEDIA")
        four = fingers("index", "middle", "ring", "pinky")
        m.update(four, now=3)
        m.update(None, hand_present=False, now=4)
        self.assertIsNone(m.update(four, now=4.5))
        self.assertEqual(m.mode, "MEDIA")


class MediaTests(unittest.TestCase):
    def feed(self, detector, pose, start, end, blocked=False):
        return [event for i in range(round((end-start)/0.05)+1)
                if (event := detector.update(pose, start+i*0.05, blocked))]

    def test_hold_once_then_delayed_opposite(self):
        d = MediaCommandDetector()
        self.assertEqual(self.feed(d, "OPEN_PALM", 0, 1), ["PLAY"])
        self.assertEqual(self.feed(d, "FIST", 1.05, 1.5), [])
        self.assertEqual(self.feed(d, "FIST", 1.55, 2.5), ["PAUSE"])
        self.assertEqual(self.feed(d, "FIST", 2.55, 4), [])

    def test_jitter_unknown_barrier_and_missing_frames_cancel(self):
        d = MediaCommandDetector()
        for i in range(40):
            self.assertIsNone(d.update("FIST" if i % 2 else "OPEN_PALM", i*0.05))
        self.feed(d, "FIST", 2, 2.3)
        self.assertIsNone(d.update("UNKNOWN", 2.35))
        self.assertEqual(self.feed(d, "FIST", 2.4, 2.7), [])
        self.assertEqual(self.feed(d, "FIST", 2.75, 3.5, blocked=True), [])
        self.assertIsNone(d.update("FIST", 4))
        self.assertIsNone(d.update("FIST", 5))


class WaveTests(unittest.TestCase):
    def setUp(self):
        self.d = WristSwipeDetector()
        self.now = 0.0

    def feed(self, angles, translation=False, gesture="OPEN_PALM"):
        events = []
        for angle in angles:
            lm = hand(angle, shift=self.now * 0.1 if translation else 0)
            event = self.d.update(lm, gesture, self.now)
            self.now += 1/30
            if event:
                events.append(event)
        return events

    def test_translation_and_wrist_point_alone_never_swipe(self):
        self.assertEqual(self.feed([0]*120, translation=True), [])
        for i in range(60):
            lm = hand()
            lm[0].x = i / 10
            self.assertIsNone(self.d.update(lm, "OPEN_PALM", self.now))
            self.now += 1/30

    def test_wave_return_suppression_and_rearm(self):
        self.feed([0]*15)
        self.assertEqual(self.feed(list(range(0, 45, 4))), ["SWIPE_RIGHT"])
        self.assertEqual(self.feed([40]*12 + list(range(40,-5,-4))), [])
        self.feed([0]*30)
        self.assertEqual(self.feed(list(range(0,-45,-4))), ["SWIPE_LEFT"])

    def test_slow_tilt_and_jitter_not_swipe(self):
        self.feed([0]*15)
        self.assertEqual(self.feed([i*0.3 for i in range(150)]), [])
        self.d.reset()
        self.assertEqual(self.feed([(-1)**i*2 for i in range(100)]), [])

    def test_short_pose_glitch_does_not_enable_reverse_return(self):
        self.feed([0]*15)
        self.feed(list(range(0,45,4)))
        self.feed([40]*3, gesture="UNKNOWN")
        self.assertEqual(self.feed(list(range(40,-5,-4))), [])

    def test_angle_translation_scale_invariance(self):
        for angle in (-40, 0, 40):
            expected = WristSwipeDetector.hand_angle(hand(angle), 0.75)
            actual = WristSwipeDetector.hand_angle(hand(angle, shift=0.2, scale=0.6), 0.75)
            self.assertAlmostEqual(actual, expected)


class PipelineTests(unittest.TestCase):
    def test_volume_blocks_media_and_stops_on_lost_hand(self):
        c = GestureController()
        c.modes.mode = "MEDIA"
        ready = fingers("thumb", "index")
        for i in range(15):
            state = c.update(ready, hand(), now=i*0.05)
            self.assertNotIn(state["command"], ("PLAY", "PAUSE"))
        self.assertTrue(c.motion.volume_active)
        state = c.update(None, None, now=0.75)
        self.assertFalse(state["enabled"])
        self.assertFalse(c.motion.volume_active)
        self.assertIsNone(state["command"])

    def test_exit_candidate_cancels_media_command(self):
        c = GestureController()
        c.modes.mode = "MEDIA"
        palm = fingers("thumb", "index", "middle", "ring", "pinky")
        four = fingers("index", "middle", "ring", "pinky")
        for i in range(7):
            c.update(palm, hand(), now=i*0.05)
        for i in range(7, 33):
            state = c.update(four, hand(), now=i*0.05)
            self.assertIsNone(state["command"])
        self.assertEqual(c.modes.mode, "MAIN")

    def test_rotation_not_emitted_during_volume_release_grace(self):
        m = MotionDetector()
        m.volume_active = True
        self.assertIsNone(m.update(hand(30), "UNKNOWN", now=1))
        self.assertTrue(m.volume_active)
        self.assertIsNone(m.prev_rotation_angle)


if __name__ == "__main__":
    unittest.main()
