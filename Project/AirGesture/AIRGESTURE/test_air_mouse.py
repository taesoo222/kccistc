import json
import threading
import time
import unittest
from types import SimpleNamespace
from unittest.mock import Mock
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from air_mouse import AirMouse
from mode_manager import ModeManager
from pc_companion import PointerReceiver,make_server
from pointer_bridge import PointerBridge
from test_controls import fingers


def hand():
    lm=[SimpleNamespace(x=.5,y=.5) for _ in range(21)]
    lm[5].x=.35;lm[17].x=.65
    lm[4].x=.15;lm[4].y=.65
    lm[8].x=.55;lm[8].y=.25
    lm[12].x=.75;lm[12].y=.25
    return lm

class MouseTests(unittest.TestCase):
    def ready(self):
        m=AirMouse();lm=hand();pose=fingers('index')
        for t in (0,.1,.2,.23): m.update(lm,pose,True,t)
        return m,lm,pose
    def test_mode_entry_and_release_gate(self):
        m=ModeManager();m.update(fingers('index'),now=0)
        self.assertEqual(m.update(fingers('index'),now=1.01),'MAIN->MOUSE')
        self.assertFalse(m.commands_enabled)
        m.update(fingers(),now=1.1);m.update(fingers(),now=1.5)
        self.assertTrue(m.commands_enabled)
    def test_move_clamp_and_smoothing(self):
        m,lm,p=self.ready();before=m.position
        lm[8].x=2
        result=m.update(lm,p,True,.26)
        self.assertGreater(result['x'],before[0]);self.assertLessEqual(result['x'],1)
    def test_pinch_drag_release_and_loss(self):
        m,lm,p=self.ready()
        lm[4].x=lm[8].x;lm[4].y=lm[8].y
        self.assertTrue(m.update(lm,p,True,.26)['left'])
        self.assertTrue(m.update(lm,p,True,.29)['left'])
        self.assertFalse(m.update(None,None,False,.32)['left'])
        self.assertFalse(m.update(lm,p,True,.35)['active'])
    def test_right_pinch_once(self):
        m,lm,p=self.ready();lm[4].x=lm[12].x;lm[4].y=lm[12].y
        for t in (.26,.29,.32): r=m.update(lm,p,True,t)
        self.assertEqual(r['right_clicks'],1)
        self.assertFalse(r['left'])
    def test_scroll_no_cursor_motion(self):
        m,lm,p=self.ready();start=m.position
        p=fingers('index','middle');m.update(lm,p,True,.26)
        lm[8].y-=.15;lm[12].y-=.15
        r=m.update(lm,p,True,.29)
        self.assertGreater(r['wheel'],0);self.assertEqual(m.position,start)
    def test_frame_gap_releases(self):
        m,lm,p=self.ready();lm[4].x=lm[8].x;lm[4].y=lm[8].y
        m.update(lm,p,True,.26)
        self.assertFalse(m.update(lm,p,True,1)['left'])

class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.os=Mock();self.r=PointerReceiver(self.os);self.r.set_enabled(True)
        self.d=dict(session='test',sequence=0,active=True,x=.5,y=.5,left=False,right_clicks=0,wheel=0)
        self.r.apply(self.d,now=1)
    def send(self,t=1.1,**changes):
        self.d.update(sequence=self.d['sequence']+1,**changes);self.r.apply(self.d,now=t)
    def test_button_edge_duplicate_and_watchdog(self):
        self.send(left=True);self.r.apply(self.d,now=1.2)
        self.os.button.assert_called_once_with(True)
        self.r.watchdog(now=1.6)
        self.assertEqual(self.os.button.call_args.args,(False,))
        self.send(t=1.7,left=True)
        self.assertFalse(self.r.left)
    def test_pausing_releases_and_requires_open_hand(self):
        self.send(left=True);self.r.set_enabled(False)
        self.assertFalse(self.r.left)
        self.r.set_enabled(True);self.send(t=1.2,left=True)
        self.assertFalse(self.r.left)
    def test_reject_invalid_coordinates(self):
        for value in (float('nan'),float('inf'),2,'0.5',True):
            with self.assertRaises(ValueError): self.r.apply(dict(self.d,x=value))
    def test_counters_not_replayed(self):
        self.send(right_clicks=1,wheel=-2);self.send(t=1.2)
        self.os.right_click.assert_called_once()
        self.os.scroll.assert_called_once_with(-2)
    def test_session_takeover_rejected(self):
        with self.assertRaises(ValueError): self.r.apply(dict(self.d,session='other'),now=1.2)
    def test_http_auth_and_pointer_transport(self):
        token='test-secret-token-1234';server=make_server(self.r,token,'127.0.0.1',0)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}'
        bridge=None
        try:
            with self.assertRaises(HTTPError) as error:
                urlopen(Request(url+'/pointer',b'{}'),timeout=1)
            self.assertEqual(error.exception.code,401)
            bridge=PointerBridge(url,token)
            bridge.publish(dict(self.d,active=False,left=False))
            deadline=time.monotonic()+2
            while bridge.status!='CONNECTED' and time.monotonic()<deadline: time.sleep(.01)
            self.assertEqual(bridge.status,'CONNECTED')
        finally:
            if bridge: bridge.close()
            server.shutdown();server.server_close()

class StreamTests(unittest.TestCase):
    def test_direct_stream_auth_dimensions_and_frames(self):
        import cv2
        import numpy as np
        from preview_stream import PreviewStream
        class Camera:
            def snapshot(self,after=0):
                return after+1,np.zeros((480,640,3),dtype=np.uint8)
        stream=PreviewStream(Camera(),'test-secret-token',host='127.0.0.1',port=0,fps=30)
        url=f'http://127.0.0.1:{stream.server.server_port}/stream.mjpg'
        try:
            with self.assertRaises(HTTPError) as error: urlopen(url,timeout=2)
            self.assertEqual(error.exception.code,401)
            req=Request(url,headers={'Authorization':'Bearer test-secret-token'})
            with urlopen(req,timeout=2) as response:
                start=time.monotonic()
                for _ in range(8):
                    line=response.readline()
                    while line.strip()!=b'--frame': line=response.readline()
                    headers={}
                    while True:
                        line=response.readline()
                        if line==b'\r\n': break
                        key,value=line.decode().split(':',1);headers[key]=value.strip()
                    frame=cv2.imdecode(np.frombuffer(response.read(int(headers['Content-Length'])),dtype=np.uint8),1)
                    self.assertEqual(frame.shape[:2],(240,320))
                self.assertLess(time.monotonic()-start,1.2)
        finally: stream.close()

if __name__=='__main__': unittest.main()
