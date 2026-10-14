import unittest
from types import SimpleNamespace
from palm_swipe import PalmDisplacementDetector

def hand(x):
    return [SimpleNamespace(x=x+(i%5)*.01,y=.5,z=0) for i in range(21)]

class DisplacementTests(unittest.TestCase):
    def run_path(self,path):
        d=PalmDisplacementDetector(.08)
        return [event for i,x in enumerate(path) if (event:=d.update(hand(x),'UNKNOWN',i/30))]
    def test_left_and_right(self):
        for sign,label in [(1,'SWIPE_RIGHT'),(-1,'SWIPE_LEFT')]:
            path=[.5]*6+[.5+sign*i*.01 for i in range(21)]+[.5+sign*.2]*15
            self.assertEqual(self.run_path(path),[label])
    def test_static_jitter(self):
        self.assertEqual(self.run_path([.5+(-1)**i*.008 for i in range(90)]),[])
    def test_tracking_jump_one_frame(self):
        self.assertEqual(self.run_path([.5]*10+[.8]+[.5]*30),[])
    def test_return_does_not_emit_opposite(self):
        path=[.5]*6+[.5+i*.01 for i in range(21)]+[.7]*10+[.7-i*.01 for i in range(21)]+[.5]*8
        self.assertEqual(self.run_path(path),['SWIPE_RIGHT'])
    def test_repeated_right_after_center(self):
        cycle=[.5]*6+[.5+i*.01 for i in range(21)]+[.7]*10+[.7-i*.01 for i in range(21)]+[.5]*8
        self.assertEqual(self.run_path(cycle*2),['SWIPE_RIGHT']*2)

if __name__=='__main__':unittest.main()
