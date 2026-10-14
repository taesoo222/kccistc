"""Windows companion: direct Pi preview + authenticated mouse receiver (8766).
Existing media/PPT bridge on 8765 remains a separate process.
"""
import argparse
import ctypes
import hmac
import io
import json
import math
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, build_opener, ProxyHandler

class PointerReceiver:
    """Serial state application and disconnect watchdog, injectable OS backend."""
    def __init__(self, backend):
        self.backend=backend
        self.lock=threading.Lock()
        self.session=None
        self.sequence=-1
        self.last_seen=0
        self.left=False
        self.right_clicks=self.wheel=0
        self.armed=False
        self.enabled=False
    @staticmethod
    def validate(data):
        if not isinstance(data,dict): raise ValueError('Expected object')
        if not isinstance(data.get('session'),str) or not 1<=len(data['session'])<=64: raise ValueError('Invalid session')
        for key in ('sequence','right_clicks','wheel'):
            if type(data.get(key)) is not int or abs(data[key])>2**53: raise ValueError('Invalid counter')
        if data['sequence']<0 or data['right_clicks']<0: raise ValueError('Negative counter')
        for key in ('active','left'):
            if type(data.get(key)) is not bool: raise ValueError('Invalid flag')
        for key in ('x','y'):
            value=data.get(key)
            if value is not None and (type(value) not in (int,float) or not math.isfinite(value) or not 0<=value<=1):
                raise ValueError('Invalid coordinate')
        if (data.get('x') is None)!=(data.get('y') is None): raise ValueError('Coordinates must be paired')
    def release(self):
        if self.left: self.backend.button(False)
        self.left=False
    def set_enabled(self, enabled):
        with self.lock:
            self.enabled=enabled
            self.armed=False
            self.release()
    def apply(self,data,now=None):
        self.validate(data)
        now=time.monotonic() if now is None else now
        with self.lock:
            new_session=data['session']!=self.session
            if new_session and self.session is not None and now-self.last_seen<.5:
                raise ValueError('Another controller is active')
            if new_session:
                self.release()
                self.session=data['session']
                self.sequence=-1
                self.armed=False
            if data['sequence']<=self.sequence: return
            expired=now-self.last_seen>.4
            self.sequence=data['sequence']
            self.last_seen=now
            if expired or not data['active'] or not self.enabled:
                self.release()
                self.armed=False
            # Reconnect/enable while pinched never starts an unintended drag.
            if not self.armed:
                self.right_clicks=data['right_clicks']
                self.wheel=data['wheel']
                if self.enabled and data['active'] and not data['left']: self.armed=True
                return
            if data['x'] is not None: self.backend.move(data['x'],data['y'])
            if data['left']!=self.left:
                self.backend.button(data['left'])
                self.left=data['left']
            count=data['right_clicks']-self.right_clicks
            if 0<count<=2:
                for _ in range(count): self.backend.right_click()
            wheel=data['wheel']-self.wheel
            if abs(wheel)<=20 and wheel: self.backend.scroll(wheel)
            self.right_clicks=data['right_clicks']
            self.wheel=data['wheel']
    def watchdog(self,now=None):
        now=time.monotonic() if now is None else now
        with self.lock:
            if now-self.last_seen>.4:
                self.release()
                self.armed=False

class WindowsMouse:
    def __init__(self):
        self.user=ctypes.windll.user32
        self.user.SetProcessDPIAware()
    def move(self,x,y):
        self.user.SetCursorPos(round(x*(self.user.GetSystemMetrics(0)-1)),round(y*(self.user.GetSystemMetrics(1)-1)))
    def button(self,down): self.user.mouse_event(0x0002 if down else 0x0004,0,0,0,0)
    def right_click(self):
        self.user.mouse_event(0x0008,0,0,0,0)
        self.user.mouse_event(0x0010,0,0,0,0)
    def scroll(self,steps): self.user.mouse_event(0x0800,0,0,ctypes.c_uint32(steps*120),0)


def make_server(receiver,token,host,port):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_POST(self):
            self.connection.settimeout(1)
            if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+token):
                self.send_error(401); return
            if self.path!='/pointer': self.send_error(404); return
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 0<size<=4096: raise ValueError('Payload too large')
                receiver.apply(json.loads(self.rfile.read(size)))
            except (ValueError,TypeError,KeyError,UnicodeError):
                self.send_error(400); return
            self.send_response(204)
            self.send_header('Content-Length','0')
            self.end_headers()
    server=ThreadingHTTPServer((host,port),Handler)
    server.daemon_threads=True
    return server


def main():
    import tkinter as tk
    from PIL import Image,ImageTk
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pi',required=True,help='Pi IP address')
    p.add_argument('--config',type=Path,default=Path(__file__).with_name('bridge_config.json'))
    p.add_argument('--port',type=int,default=8766)
    p.add_argument('--stream-port',type=int,default=8767)
    p.add_argument('--host',default='0.0.0.0')
    args=p.parse_args()
    token=json.loads(args.config.read_text(encoding='utf-8-sig'))['token']
    if not isinstance(token,str) or len(token)<16: raise ValueError('Token must be at least 16 characters')
    receiver=PointerReceiver(WindowsMouse())
    server=make_server(receiver,token,args.host,args.port)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    stopped=threading.Event()
    latest_lock=threading.Lock()
    latest=[None,0.0,0]
    def preview():
        opener=build_opener(ProxyHandler({}))
        while not stopped.is_set():
            try:
                req=Request(f'http://{args.pi}:{args.stream_port}/stream.mjpg',headers={'Authorization':'Bearer '+token})
                with opener.open(req,timeout=2) as response:
                    while not stopped.is_set():
                        line=response.readline(256)
                        if not line: break
                        if line.strip()!=b'--frame': continue
                        length=0
                        while True:
                            line=response.readline(256)
                            if line in (b'\r\n',b'\n',b''): break
                            if line.lower().startswith(b'content-length:'): length=int(line.split(b':',1)[1])
                        if not 0<length<=2_000_000: raise ValueError('Invalid frame length')
                        data=response.read(length)
                        if len(data)!=length: break
                        with latest_lock:
                            latest[:]=[data,time.monotonic(),latest[2]+1]
            except Exception:
                pass
            stopped.wait(.5)
    threading.Thread(target=preview,daemon=True).start()
    def watchdog():
        while not stopped.wait(.05): receiver.watchdog()
    threading.Thread(target=watchdog,daemon=True).start()
    root=tk.Tk()
    root.title('AirGesture | Direct camera')
    root.attributes('-topmost',True)
    root.configure(bg='#101827')
    root.geometry(f'420x410+{max(0,root.winfo_screenwidth()-440)}+20')
    view=tk.Label(root,bg='#101827',text='Connecting to Pi camera...',fg='white')
    view.pack(fill='both',expand=True)
    status=tk.StringVar(value='Mouse paused | F8 toggles control | Esc pauses')
    tk.Label(root,textvariable=status,bg='#101827',fg='#8ee3c2').pack(pady=5)
    button=tk.Button(root,text='Enable mouse (F8)',command=lambda:toggle())
    button.pack(fill='x',padx=12,pady=5)
    tk.Label(root,text='Index: move   Pinch: click / drag\nMiddle pinch: right click   Two fingers: scroll',bg='#101827',fg='white').pack(pady=5)
    def toggle():
        receiver.set_enabled(not receiver.enabled)
        button.configure(text='Pause mouse (F8)' if receiver.enabled else 'Enable mouse (F8)')
    root.bind('<Escape>',lambda _:receiver.set_enabled(False))
    shown=-1
    f8_was=False
    rate_time=time.monotonic()
    rate_frames=0
    rate=0.0
    def tick():
        nonlocal shown,f8_was,rate_time,rate_frames,rate
        down=bool(ctypes.windll.user32.GetAsyncKeyState(0x77)&0x8000)
        if down and not f8_was: toggle()
        f8_was=down
        # Global Escape works even if the controlled app has focus.
        if ctypes.windll.user32.GetAsyncKeyState(0x1B)&0x8000: receiver.set_enabled(False)
        with latest_lock: data,received,seq=latest
        now=time.monotonic()
        if data and seq!=shown:
            try:
                im=Image.open(io.BytesIO(data))
                im.thumbnail((max(100,view.winfo_width()),max(80,view.winfo_height())))
                photo=ImageTk.PhotoImage(im)
                view.configure(image=photo,text='')
                view.image=photo
                shown=seq
                rate_frames+=1
            except (OSError,ValueError): pass
        if now-rate_time>=1:
            rate=rate_frames/(now-rate_time)
            rate_frames=0
            rate_time=now
        connected=received>0 and now-received<2
        if not connected:
            view.configure(image='',text='Camera disconnected — reconnecting...')
        mouse_live=now-receiver.last_seen<.4
        status.set(f'Camera {rate:.0f} FPS' + (' | LIVE' if connected else ' | OFFLINE') +
                   (' | Mouse ON' if receiver.enabled else ' | Mouse PAUSED') +
                   ('' if mouse_live else ' | No input'))
        button.configure(text='Pause mouse (F8)' if receiver.enabled else 'Enable mouse (F8)')
        root.after(15,tick)
    def close():
        receiver.set_enabled(False)
        stopped.set()
        server.shutdown()
        server.server_close()
        root.destroy()
    root.protocol('WM_DELETE_WINDOW',close)
    tick()
    try: root.mainloop()
    finally:
        receiver.set_enabled(False)
        stopped.set()

if __name__=='__main__': main()
