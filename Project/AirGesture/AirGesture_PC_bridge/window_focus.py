"""Restore a known application window; report Windows focus denial honestly."""
def focus_window(hwnd):
    import win32api,win32con,win32gui,win32process
    win32gui.ShowWindow(hwnd,win32con.SW_RESTORE)
    try:win32gui.SetForegroundWindow(hwnd)
    except Exception:pass
    if win32gui.GetForegroundWindow()==hwnd:return True
    current=win32api.GetCurrentThreadId()
    foreground=win32gui.GetForegroundWindow()
    thread=win32process.GetWindowThreadProcessId(foreground)[0] if foreground else current
    attached=False
    try:
        if thread!=current:
            win32process.AttachThreadInput(current,thread,True);attached=True
        win32gui.BringWindowToTop(hwnd)
        win32gui.SetForegroundWindow(hwnd)
        return win32gui.GetForegroundWindow()==hwnd
    except Exception:return False
    finally:
        if attached:win32process.AttachThreadInput(current,thread,False)


def focus_edge(profile):
    import psutil,win32gui,win32process
    target=str(profile.resolve()).lower()
    pids=set()
    for process in psutil.process_iter(['pid','name','cmdline']):
        try:
            if process.info['name'].lower()=='msedge.exe' and any(
                arg.lower()=='--user-data-dir='+target for arg in process.info['cmdline'] or []):
                pids.add(process.info['pid'])
        except (psutil.Error,AttributeError):pass
    handles=[]
    win32gui.EnumWindows(lambda h,_: handles.append(h) if win32gui.IsWindowVisible(h) and win32process.GetWindowThreadProcessId(h)[1] in pids else None,None)
    return focus_window(handles[0]) if handles else False


def focus_ppt_show():
    import psutil,win32gui,win32process
    pids={p.info['pid'] for p in psutil.process_iter(['pid','name'])
          if (p.info['name'] or '').lower()=='powerpnt.exe'}
    handles=[]
    win32gui.EnumWindows(lambda h,_: handles.append(h) if win32gui.IsWindowVisible(h)
        and win32gui.GetClassName(h).lower()=='screenclass'
        and win32process.GetWindowThreadProcessId(h)[1] in pids else None,None)
    return focus_window(handles[0]) if len(handles)==1 else False
