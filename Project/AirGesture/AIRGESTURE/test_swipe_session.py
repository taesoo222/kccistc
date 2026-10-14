import math
import unittest
from gesture_controller import GestureController
from test_controls import hand, fingers
from wrist_swipe import WristSwipeDetector

PALM = fingers('thumb','index','middle','ring','pinky')


class SwipeSessionTests(unittest.TestCase):
    def setUp(self):
        self.c=GestureController();self.c.modes.mode='MEDIA';self.now=0

    def feed(self, pose=PALM, angles=None, frames=1, score=None):
        states=[]
        for a in angles if angles is not None else [0]*frames:
            lm=hand(a)
            if pose is not None and pose['states']['thumb']:
                lm[4].x=.1;lm[4].y=.6
            states.append(self.c.update(pose,lm if pose is not None else None,
                                        volume_probability=score,now=self.now))
            self.now+=1/30
        return states

    def enter(self):
        pose=fingers('middle','ring','pinky')
        for i in range(12):
            lm=hand();lm[4].x=lm[8].x;lm[4].y=lm[8].y
            state=self.c.update(pose,lm,now=self.now)
            self.now+=1/30
            self.assertIsNone(state['command'])
        self.assertTrue(self.c.swipe.active)
        self.feed(frames=12)  # First open palm establishes neutral after OK.

    def test_palm_restores_play_and_never_arms_swipe(self):
        states=self.feed(frames=90)
        self.assertFalse(self.c.swipe.active)
        self.assertEqual([s['command'] for s in states if s['command']],['PLAY'])

    def test_ok_enters_swipe_without_play(self):
        self.enter()
        states=self.feed(angles=range(0,45,4))
        self.assertEqual([s['command'] for s in states if s['command']],['VIDEO_NEXT'])

    def test_ok_geometry_rejects_volume_and_unpinched_palm(self):
        from ok_pose import is_ok_pose
        lm=hand();lm[4].x=lm[8].x;lm[4].y=lm[8].y
        self.assertTrue(is_ok_pose(fingers('middle','ring','pinky'),lm))
        self.assertFalse(is_ok_pose(fingers('thumb','index'),lm))
        lm[4].x=.1
        self.assertFalse(is_ok_pose(PALM,lm))

    def test_volume_is_blocked_in_swipe(self):
        self.enter()
        states=self.feed(fingers('thumb','index'),frames=25,score=.99)
        self.assertFalse(any(s['command'] or s['volume_lock'] for s in states))

    def ok_frames(self,count):
        result=[]
        for _ in range(count):
            lm=hand();lm[4].x=lm[8].x;lm[4].y=lm[8].y
            result.append(self.c.update(fingers('middle','ring','pinky'),lm,now=self.now))
            self.now+=1/30
        return result

    def test_fist_and_hand_loss_preserve_latch(self):
        self.enter()
        states=self.feed(fingers(),frames=60)+self.feed(None,frames=30)
        self.now+=2
        states+=self.feed(frames=30)
        self.assertTrue(self.c.swipe.active)
        self.assertFalse(any(s['command'] for s in states))

    def test_second_ok_exits_and_palm_plays(self):
        self.enter()
        self.ok_frames(12)
        self.assertFalse(self.c.swipe.active)
        states=self.feed(frames=40)
        self.assertEqual([s['command'] for s in states if s['command']],['PLAY'])

    def test_held_ok_and_disappearance_never_retoggle(self):
        states=self.ok_frames(90)
        self.assertTrue(self.c.swipe.active)
        self.feed(None,frames=30)
        states+=self.ok_frames(90)
        self.assertTrue(self.c.swipe.active)
        self.assertFalse(any(s['command'] for s in states))
        self.feed(frames=2)
        self.ok_frames(40)
        self.assertTrue(self.c.swipe.active)
        self.feed(frames=12)
        self.ok_frames(60)
        self.assertFalse(self.c.swipe.active)

    def test_partial_main_pose_preserves_latch_completed_main_clears(self):
        self.enter()
        self.feed(fingers('index','middle','ring','pinky'),frames=4)
        self.feed(frames=12)
        self.assertTrue(self.c.swipe.active)
        self.feed(fingers('index','middle','ring','pinky'),frames=45)
        self.assertEqual(self.c.modes.mode,'MAIN')
        self.assertFalse(self.c.swipe.active)

    def test_ppt_continuous_outward_waves_without_center_hold(self):
        self.c.modes.mode='PPT'
        self.enter()
        # Three 1-second oscillations without pauses in the center.
        angles=[40*math.sin(2*math.pi*i/30) for i in range(91)]
        states=self.feed(angles=angles)
        events=[s['command'] for s in states if s['command']]
        self.assertEqual(events,['NEXT','PREVIOUS']*3)

    def test_return_to_center_never_reverse_fires(self):
        self.c.modes.mode='PPT';self.enter()
        one=list(range(0,41,4))+list(range(40,-1,-4))
        states=self.feed(angles=one*3)
        self.assertEqual([s['command'] for s in states if s['command']],['NEXT']*3)

    def test_jitter_and_stationary_pose_do_not_repeat(self):
        self.c.modes.mode='PPT';self.enter()
        states=self.feed(angles=[(-1)**i*3 for i in range(90)])
        self.assertFalse(any(s['command'] for s in states))
        self.feed(angles=range(0,41,4))
        states=self.feed(angles=[40]*90)
        self.assertFalse(any(s['command'] for s in states))


if __name__=='__main__':unittest.main()
