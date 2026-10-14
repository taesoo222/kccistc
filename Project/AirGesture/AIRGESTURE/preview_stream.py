"""Authenticated MJPEG from camera capture, independent of hand inference."""
import hmac
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import cv2

class PreviewStream:
    def __init__(self,camera,token,host='0.0.0.0',port=8767,fps=25,mirror=True):
        self.stopped=threading.Event()
        self.condition=threading.Condition()
        self.jpeg=None
        self.sequence=0
        owner=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+token):
                    self.send_error(401); return
                if self.path!='/stream.mjpg': self.send_error(404); return
                self.connection.settimeout(2)
                self.send_response(200)
                self.send_header('Content-Type','multipart/x-mixed-replace; boundary=frame')
                self.send_header('Cache-Control','no-store')
                self.end_headers()
                sequence=-1
                try:
                    while not owner.stopped.is_set():
                        with owner.condition:
                            changed=owner.condition.wait_for(lambda:owner.sequence!=sequence or owner.stopped.is_set(),1)
                            sequence,jpeg=owner.sequence,owner.jpeg
                        if not changed or jpeg is None: continue
                        self.wfile.write(b'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: '+str(len(jpeg)).encode()+b'\r\n\r\n'+jpeg+b'\r\n')
                except (OSError,TimeoutError): pass
        self.server=ThreadingHTTPServer((host,port),Handler)
        self.server.daemon_threads=True
        self.server_thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.server_thread.start()
        def encode():
            sequence=0
            period=1/min(30,max(1,fps))
            deadline=time.monotonic()
            while not self.stopped.is_set():
                sequence,frame=camera.snapshot(sequence)
                if frame is None: break
                h,w=frame.shape[:2]
                frame=cv2.resize(frame,(320,max(1,round(h*320/w))))
                if mirror: frame=cv2.flip(frame,1)
                ok,jpeg=cv2.imencode('.jpg',frame,[cv2.IMWRITE_JPEG_QUALITY,65])
                if ok:
                    with self.condition:
                        self.jpeg=jpeg.tobytes()
                        self.sequence+=1
                        self.condition.notify_all()
                # Include capture/resize/encode time in the frame budget.
                # Skip missed deadlines instead of sending catch-up bursts.
                deadline+=period
                now=time.monotonic()
                if deadline<now:
                    deadline+=((now-deadline)//period+1)*period
                self.stopped.wait(max(0,deadline-time.monotonic()))
        self.encoder=threading.Thread(target=encode,daemon=True)
        self.encoder.start()
    def close(self):
        self.stopped.set()
        with self.condition: self.condition.notify_all()
        self.server.shutdown()
        self.server.server_close()
        self.encoder.join(timeout=3)
