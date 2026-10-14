import unittest
from media_commands import MediaCommandDetector
from mode_manager import ModeManager
from test_controls import fingers

class ContinuousMediaTests(unittest.TestCase):
    def feed(self,d,pose,start,end,blocked=False):
        return [r for i in range(round((end-start)/.05)+1)
                if (r:=d.update(pose,start+i*.05,blocked))]
    def test_same_command_after_neutral_without_v(self):
        d=MediaCommandDetector()
        self.assertEqual(self.feed(d,'OPEN_PALM',0,1),['PLAY'])
        self.assertEqual(self.feed(d,'UNKNOWN',1.05,1.4),[])
        self.assertEqual(self.feed(d,'OPEN_PALM',1.45,2.5),['PLAY'])
    def test_held_pose_and_short_glitch_do_not_repeat(self):
        d=MediaCommandDetector()
        self.assertEqual(self.feed(d,'FIST',0,2),['PAUSE'])
        self.feed(d,'UNKNOWN',2.05,2.15)
        self.assertEqual(self.feed(d,'FIST',2.2,4),[])
    def test_lost_hand_rearms_same_command(self):
        d=MediaCommandDetector()
        self.assertEqual(self.feed(d,'FIST',0,1),['PAUSE'])
        self.feed(d,'NONE',1.05,1.5,True)
        self.assertEqual(self.feed(d,'FIST',1.55,2.5),['PAUSE'])
    def test_mode_stays_media_until_four_finger_exit(self):
        m=ModeManager();m.update(fingers('index','middle'),now=0)
        m.update(fingers('index','middle'),now=1.01)
        m.update(fingers(),now=1.1);m.update(fingers(),now=1.5)
        for i,pose in enumerate([fingers(),fingers('thumb','index','middle','ring','pinky'),None,fingers(),fingers('index')]):
            m.update(pose,hand_present=pose is not None,now=2+i)
            self.assertEqual(m.mode,'MEDIA')
            self.assertEqual(m.commands_enabled,pose is not None)
        four=fingers('index','middle','ring','pinky')
        m.update(four,now=7);m.update(four,now=8.3)
        self.assertEqual(m.mode,'MAIN')

if __name__=='__main__':unittest.main()
