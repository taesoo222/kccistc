import unittest
from unittest.mock import Mock
import queue
from gesture_controller import GestureController
from command_bridge import CommandBridge
from test_controls import hand, fingers


class AutoTests(unittest.TestCase):
    def test_media_right_wave_next_and_return_no_extra_next(self):
        c=GestureController(); c.modes.mode='MEDIA'
        palm=fingers('thumb','index','middle','ring','pinky')
        events=[]
        for i in range(12):
            lm=hand();lm[4].x=lm[8].x;lm[4].y=lm[8].y
            c.update(fingers('middle','ring','pinky'),lm,now=i/30)
        angles=[0]*15+list(range(0,45,4))+[40]*12+list(range(40,-5,-4))+[0]*15
        for i,angle in enumerate(angles):
            lm=hand(angle); lm[4].x=.1;lm[4].y=.6
            state=c.update(palm,lm,now=(i+12)/30)
            if state['command']:events.append(state['command'])
        self.assertEqual(events.count('VIDEO_NEXT'),1)
        self.assertNotIn('NEXT',events)
        self.assertNotIn('PREVIOUS',events)

    def test_mode_command_survives_hand_loss_cancellation(self):
        b=CommandBridge.__new__(CommandBridge)
        b.pending=queue.Queue(maxsize=4); b.results=queue.Queue()
        b.pending.put((1,'mode','MODE_MEDIA'));b.pending.put((1,'play','PLAY'))
        b.cancel_pending()
        self.assertEqual(b.pending.get()[2],'MODE_MEDIA')
        self.assertEqual(b.results.get()[0],'PLAY')
        b.pending.put((1,'mode','MODE_PPT')); b.cancel_pending(preserve_mode=False)
        self.assertTrue(b.pending.empty())

if __name__=='__main__':unittest.main()
