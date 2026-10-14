"""Latest-only authenticated preview client; never blocks the Tk thread."""
import threading
import time
from urllib.request import Request,build_opener,ProxyHandler

class DirectPreview:
    def __init__(self,token):
        self.token=token
        self.lock=threading.Lock()
        self.stop=threading.Event()
        self.target=None
        self.frame=None
        self.received=0
        self.sequence=0
        threading.Thread(target=self.run,daemon=True).start()
    def configure(self,recognition,age):
        target=None
        if age is not None and age<2.5 and recognition.get('preview_transport')=='mjpeg':
            host=recognition.get('stream_host','')
            if host:target=(host,recognition.get('stream_port',8767))
        with self.lock:
            if target!=self.target:
                self.frame=None;self.received=0
            self.target=target
    def snapshot(self):
        with self.lock:return self.frame,self.received,self.sequence
    def run(self):
        opener=build_opener(ProxyHandler({}))
        while not self.stop.is_set():
            with self.lock:target=self.target
            if target is None:self.stop.wait(.1);continue
            host,port=target
            if ':' in host:host='['+host+']'
            try:
                req=Request(f'http://{host}:{port}/stream.mjpg',headers={'Authorization':'Bearer '+self.token})
                with opener.open(req,timeout=2) as reply:
                    while not self.stop.is_set():
                        with self.lock:
                            if target!=self.target:break
                        line=reply.readline(256)
                        if not line:break
                        if line.strip()!=b'--frame':continue
                        length=0
                        for _ in range(16):
                            line=reply.readline(256)
                            if line==b'\r\n':break
                            if line.lower().startswith(b'content-length:'):length=int(line.split(b':',1)[1])
                        if not 0<length<=2_000_000:raise ValueError('Invalid JPEG size')
                        frame=reply.read(length)
                        if len(frame)!=length:break
                        with self.lock:
                            if target==self.target:
                                self.frame=frame;self.received=time.monotonic();self.sequence+=1
            except (OSError,ValueError):pass
            self.stop.wait(.2)
    def close(self):self.stop.set()
