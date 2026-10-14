import unittest
from types import SimpleNamespace as P
from mode_manager import ModeManager
from main_return_pose import main_return_pose


def pose(matched=True):
    return {'states':dict(thumb=False,index=True,middle=True,ring=True,pinky=True),
            'main_return':matched}


class ReturnTests(unittest.TestCase):
    def test_return_then_direct_reentry_both_modes(self):
        for start in ('MEDIA', 'PPT'):
            for destination, ring in (('MEDIA', False), ('PPT', True)):
                m=ModeManager(); m.mode=start
                m.update(pose(),now=0)
                self.assertEqual(m.update(pose(),now=1.21),f'{start}->MAIN')
                m.update(pose(),now=2.0)
                self.assertEqual(m.mode,'MAIN')
                self.assertFalse(m.commands_enabled)
                select={'states':dict(thumb=False,index=True,middle=True,ring=ring,pinky=False),
                        'main_return':False}
                self.assertIsNone(m.update(select,now=2.1))
                self.assertFalse(m.release_gate)
                self.assertIsNone(m.update(select,now=2.9))
                self.assertEqual(m.update(select,now=3.11),f'MAIN->{destination}')
                self.assertTrue(m.release_gate)
                self.assertFalse(m.commands_enabled)

    def test_reentry_requires_one_continuous_selector(self):
        m=ModeManager(); m.mode='MAIN'; m.release_gate=True
        two={'states':dict(thumb=False,index=True,middle=True,ring=False,pinky=False)}
        three={'states':dict(thumb=False,index=True,middle=True,ring=True,pinky=False)}
        m.update(two,now=0)
        m.update(three,now=.8)
        self.assertIsNone(m.update(three,now=1.1))
        self.assertEqual(m.update(three,now=1.81),'MAIN->PPT')

    def test_jitter_pauses_instead_of_resetting_and_blocks_commands(self):
        m=ModeManager(); m.mode='MEDIA'
        for i in range(26):
            m.update(pose(i != 10),now=i*.05)
            self.assertEqual(m.mode,'MEDIA')
            self.assertFalse(m.commands_enabled)
        self.assertEqual(m.update(pose(),now=1.35),'MEDIA->MAIN')

    def test_sustained_mismatch_and_tracking_loss_reset(self):
        for lost in (False,True):
            m=ModeManager(); m.mode='PPT'
            m.update(pose(),now=0); m.update(pose(),now=.8)
            m.update(None if lost else pose(False),hand_present=not lost,now=1.1)
            m.update(pose(),now=1.2)
            self.assertEqual(m.get_candidate_progress(1.2),0)
            self.assertIsNone(m.update(pose(),now=1.6))

    def test_return_allowed_during_release_gate(self):
        m=ModeManager(); m.mode='MEDIA'; m.release_gate=True
        m.update(pose(),now=0)
        self.assertEqual(m.update(pose(),now=1.21),'MEDIA->MAIN')

    def test_thumb_position_and_small_finger_tolerance(self):
        fingers=pose(); fingers['states']['thumb']=True
        fingers['states']['pinky']=False
        fingers['angles']={'pinky':148}
        lm=[P(x=.5,y=.5) for _ in range(21)]
        lm[5]=P(x=.3,y=.5); lm[17]=P(x=.7,y=.5); lm[4]=P(x=.45,y=.55)
        self.assertTrue(main_return_pose(fingers,lm)['matched'])
        # An outward thumb is an open palm, even if its angle classifier says closed.
        lm[4]=P(x=.05,y=.5); fingers['states']['thumb']=False
        self.assertFalse(main_return_pose(fingers,lm)['matched'])
        lm[4]=P(x=.45,y=.55); fingers['angles']['pinky']=90
        self.assertFalse(main_return_pose(fingers,lm)['matched'])

    def test_mirror_scale_invariance(self):
        fingers=pose()
        lm=[P(x=.5,y=.5) for _ in range(21)]
        lm[5]=P(x=.3,y=.5); lm[17]=P(x=.7,y=.5); lm[4]=P(x=.45,y=.55)
        for scale in (.6,1,1.5):
            mirrored=[P(x=1-p.x*scale,y=p.y*scale) for p in lm]
            self.assertTrue(main_return_pose(fingers,mirrored)['matched'])

if __name__=='__main__': unittest.main()
