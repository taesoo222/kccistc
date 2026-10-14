"""Click-through translucent topmost Windows recognition HUD."""
import argparse
import json
from pathlib import Path
import queue
import threading
import time
import base64
import ctypes
from direct_preview import DirectPreview
from io import BytesIO
from urllib.request import Request,build_opener,ProxyHandler
from status_state import overlay_lines,swipe_display


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=8765)
    parser.add_argument('--instance',required=True)
    parser.add_argument('--preview',action='store_true',help='Show a framed preview for layout verification')
    args=parser.parse_args()
    rootdir=Path(__file__).resolve().parent
    token=(rootdir/'bridge_key.txt').read_text().strip()
    config=json.loads((rootdir/'desktop_config.json').read_text(encoding='utf-8-sig'))
    opacity=max(.25,min(1.0,float(config.get('overlay_opacity',.98))))
    import tkinter as tk
    from PIL import Image,ImageTk,ImageOps
    import win32gui,win32con
    root=tk.Tk();root.withdraw();root.title('AirGesture Status Overlay')
    root.overrideredirect(not args.preview);root.configure(bg='#111827')
    root.attributes('-topmost',True);root.attributes('-alpha',opacity)
    width,height=360,460
    root.geometry(f'{width}x{height}+{max(0,root.winfo_screenwidth()-width-24)}+40')
    header=tk.Frame(root,bg='#111827');header.pack(fill='x',padx=12,pady=(10,8))
    title=tk.Label(header,text='AIRGESTURE',font=('Malgun Gothic',10,'bold'),bg='#111827',fg='#94a3b8')
    title.pack(side='left')
    version=tk.Label(header,text='HUD 3',font=('Malgun Gothic',9),bg='#111827',fg='#64748b');version.pack(side='right')
    camera_frame=tk.Frame(root,width=336,height=252,bg='#0b1118')
    camera_frame.pack(padx=12);camera_frame.pack_propagate(False)
    camera=tk.Label(camera_frame,bg='#0b1118',fg='#cbd5e1',text='웹캠 연결 대기')
    camera.pack(fill='both',expand=True)
    info=tk.Frame(root,bg='#111827');info.pack(fill='x',padx=12,pady=(8,4))
    mode_label=tk.Label(info,bg='#111827',fg='#ffffff',font=('Malgun Gothic',14,'bold'));mode_label.pack(side='left')
    fps_label=tk.Label(info,bg='#111827',fg='#94a3b8',font=('Malgun Gothic',10));fps_label.pack(side='right')
    pose_label=tk.Label(root,bg='#111827',fg='#cbd5e1',anchor='w',font=('Malgun Gothic',11));pose_label.pack(fill='x',padx=12,pady=(0,8))
    card=tk.Frame(root,bg='#1e293b');card.pack(fill='x',padx=12)
    state_label=tk.Label(card,bg='#1e293b',fg='#ffffff',anchor='w',font=('Malgun Gothic',14,'bold'));state_label.pack(fill='x',padx=10,pady=(8,2))
    hint_label=tk.Label(card,bg='#1e293b',fg='#cbd5e1',anchor='w',justify='left',wraplength=312,font=('Malgun Gothic',10));hint_label.pack(fill='x',padx=10,pady=(0,8))
    result_label=tk.Label(root,bg='#111827',fg='#94a3b8',anchor='w',font=('Malgun Gothic',10),wraplength=336,justify='left');result_label.pack(fill='x',padx=12,pady=(8,10))
    root.update_idletasks()
    hwnd=win32gui.GetParent(root.winfo_id()) or root.winfo_id()
    style=win32gui.GetWindowLong(hwnd,win32con.GWL_EXSTYLE)
    extra=win32con.WS_EX_LAYERED
    if not args.preview:extra|=win32con.WS_EX_TRANSPARENT|win32con.WS_EX_NOACTIVATE|win32con.WS_EX_TOOLWINDOW
    win32gui.SetWindowLong(hwnd,win32con.GWL_EXSTYLE,style|extra)
    updates=queue.Queue(maxsize=1);stop=threading.Event()
    direct=DirectPreview(token)
    mouse_requests=queue.Queue()
    def mouse_control():
        opener=build_opener(ProxyHandler({}))
        while not stop.is_set():
            try:enabled=mouse_requests.get(timeout=.1)
            except queue.Empty:continue
            try:
                req=Request(f'http://127.0.0.1:{args.port}/api/mouse',json.dumps({'enabled':enabled}).encode(),
                    headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
                with opener.open(req,timeout=1) as reply:reply.read()
            except OSError:pass
    threading.Thread(target=mouse_control,daemon=True).start()
    mouse_enabled=False
    f8_was=False
    esc_was=False
    shown=-1
    displayed=0
    display_fps=0.0
    fps_since=time.monotonic()
    heading="AIRGESTURE"
    def receive():
        opener=build_opener(ProxyHandler({}));last_good=time.monotonic()
        while not stop.is_set():
            try:
                req=Request(f'http://127.0.0.1:{args.port}/api/status',headers={'Authorization':'Bearer '+token})
                with opener.open(req,timeout=1) as reply:data=json.load(reply)
                if data.get('instance')!=args.instance:
                    stop.set();return
                last_good=time.monotonic()
            except Exception:
                data={'age':None,'visible':True}
                if time.monotonic()-last_good>10:stop.set();return
            try:updates.get_nowait()
            except queue.Empty:pass
            updates.put_nowait(data)
            stop.wait(.05)
    def render():
        nonlocal mouse_enabled,f8_was,esc_was,shown,displayed,display_fps,fps_since,heading,height
        render_started=time.monotonic()
        f8=bool(ctypes.windll.user32.GetAsyncKeyState(0x77)&0x8000)
        esc=bool(ctypes.windll.user32.GetAsyncKeyState(0x1B)&0x8000)
        if f8 and not f8_was:
            mouse_enabled=not mouse_enabled;mouse_requests.put(mouse_enabled)
        if esc and not esc_was:
            mouse_enabled=False;mouse_requests.put(False)
        f8_was,esc_was=f8,esc
        if stop.is_set():root.destroy();return
        try:
            data=updates.get_nowait()
            age=data.get('age')
            recognition=data.get('recognition',{})
            direct.configure(recognition,age)
            mouse_enabled=data.get('mouse_enabled',False)
            frame=recognition.get('frame','')
            if frame and age is not None and age<2.5:
                try:
                    picture=Image.open(BytesIO(base64.b64decode(frame)))
                    if picture.format!='JPEG' or picture.width>640 or picture.height>480:
                        raise ValueError('Unsupported preview dimensions')
                    picture=ImageOps.pad(picture,(336,252),color='#0b1118')
                    photo=ImageTk.PhotoImage(picture)
                    camera.configure(image=photo,text='');camera.image=photo
                except Exception:
                    camera.configure(image='',text='웹캠 영상 수신 오류');camera.image=None
            elif recognition.get('preview_transport')!='mjpeg':
                camera.configure(image='',text='웹캠 연결 대기\nPi 인식 프로그램을 실행하세요');camera.image=None
            lines=list(overlay_lines(data))
            heading=lines[0]
            mode_label.configure(text=heading)
            pose_label.configure(text=lines[1])
            state,_,hint=lines[2].partition('\n')
            if recognition.get('mode')=='MOUSE':hint='마우스 '+('ON' if mouse_enabled else 'OFF')+' · F8 / ESC'
            tone=swipe_display(data)[1]
            state_label.configure(text=state,fg=tone)
            hint_label.configure(text=hint)
            result_label.configure(text=lines[3])
            root.update_idletasks()
            height=max(440,root.winfo_reqheight())
            result_age=data.get('result_age')
            failed=data.get('result',{}).get('ok') is False and (result_age is None or result_age<6)
            result_label.configure(fg='#fbbf24' if data.get('pending') else '#fca5a5' if failed else '#94a3b8')
            if data.get('visible',True):
                root.deiconify()
                win32gui.SetWindowPos(hwnd,win32con.HWND_TOPMOST,
                    max(0,root.winfo_screenwidth()-width-24),40,width,height,
                    win32con.SWP_NOACTIVATE|win32con.SWP_SHOWWINDOW)
            else:root.withdraw()
        except queue.Empty:pass
        raw,received,sequence=direct.snapshot()
        if raw and time.monotonic()-received<2:
            if sequence!=shown:
                try:
                    picture=Image.open(BytesIO(raw))
                    if picture.format!='JPEG' or picture.width>640 or picture.height>640:raise ValueError('Invalid frame')
                    picture=ImageOps.pad(picture,(336,252),color='#0b1118')
                    photo=ImageTk.PhotoImage(picture)
                    camera.configure(image=photo,text='');camera.image=photo
                    shown=sequence
                    displayed+=1
                except (OSError,ValueError):pass
        elif direct.target is not None:
            camera.configure(image='',text='직접 영상 연결 대기');camera.image=None
        elapsed=time.monotonic()-fps_since
        if elapsed>=1:
            display_fps=displayed/elapsed
            displayed=0;fps_since=time.monotonic()
        fps_label.configure(text=f'{display_fps:.0f} FPS')
        # Poll faster than incoming video; only decode a new frame once.
        root.after(max(1,16-int((time.monotonic()-render_started)*1000)),render)
    threading.Thread(target=receive,daemon=True).start()
    root.after(100,render)
    try:root.mainloop()
    finally:
        stop.set()
        direct.close()


if __name__=='__main__':main()
