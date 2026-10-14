"""Control the one running desktop PowerPoint slide show via COM."""
import threading

_lock = threading.Lock()


def move_slide(app, command):
    if command not in ("NEXT", "PREVIOUS"):
        raise ValueError("Unsupported PowerPoint command")
    shows = app.SlideShowWindows
    if shows.Count > 1:
        raise RuntimeError("Keep only one PowerPoint slide show open.")
    if shows.Count == 1:
        window = shows.Item(1)
    else:
        if app.Presentations.Count == 0:
            raise RuntimeError('Open a PowerPoint file first.')
        window = app.ActiveWindow
    view = window.View
    current = int(view.Slide.SlideIndex)
    total = int(window.Presentation.Slides.Count)
    target = max(1, min(total, current + (1 if command == "NEXT" else -1)))
    if target != current:
        view.GotoSlide(target)
    actual = int(view.Slide.SlideIndex)
    if actual != target:
        raise RuntimeError("PowerPoint did not move to the requested slide")
    return {"ok": True, "target": "powerpoint", "slide": actual, "total": total,
            "detail": f"Slide {actual}/{total}"}


def execute(command):
    if not _lock.acquire(timeout=0.5):
        raise RuntimeError("PowerPoint is busy; command was not executed")
    try:
        import pythoncom
        import win32com.client
        pythoncom.CoInitialize()
        try:
            try:
                app = win32com.client.GetActiveObject("PowerPoint.Application")
            except Exception as error:
                raise RuntimeError("Start desktop PowerPoint and its slide show first.") from error
            return move_slide(app, command)
        finally:
            pythoncom.CoUninitialize()
    except ImportError as error:
        raise RuntimeError("Install PC dependencies: python -m pip install -r requirements.txt") from error
    finally:
        _lock.release()


def start_show(app):
    if app.SlideShowWindows.Count > 1:
        raise RuntimeError("PowerPoint 발표는 하나만 켜 두세요.")
    if app.SlideShowWindows.Count == 1:
        window = app.SlideShowWindows.Item(1)
    else:
        if app.Presentations.Count == 0:
            raise RuntimeError("먼저 PPT 파일을 선택해 주세요.")
        window = app.ActivePresentation.SlideShowSettings.Run()
    return {"ok": True, "target": "powerpoint", "detail": "PowerPoint 발표 시작 완료. 손동작으로 다음/이전을 제어하세요.",
            "slide": int(window.View.Slide.SlideIndex),
            "total": int(window.Presentation.Slides.Count)}


def manage(action):
    """Invoked only by a local PC page button, never a remote gesture."""
    if not _lock.acquire(timeout=0.5):
        raise RuntimeError("PowerPoint가 처리 중입니다. 파일 선택 창을 닫고 다시 시도하세요.")
    try:
        import pythoncom
        import win32com.client
        pythoncom.CoInitialize()
        try:
            try:
                app = win32com.client.GetActiveObject("PowerPoint.Application")
            except Exception:
                try:
                    app = win32com.client.Dispatch("PowerPoint.Application")
                except Exception as error:
                    raise RuntimeError("PC에 데스크톱 PowerPoint가 설치되어 있는지 확인해 주세요.") from error
            app.Visible = True
            if action == 'recent':
                if app.SlideShowWindows.Count == 0 and app.Presentations.Count == 0:
                    try:
                        from .recent_ppt import recent_presentation
                    except ImportError:
                        from recent_ppt import recent_presentation
                    path=recent_presentation()
                    previous_security=app.AutomationSecurity
                    try:
                        app.AutomationSecurity=3
                        app.Presentations.Open(path, True, False, True)
                    finally:
                        app.AutomationSecurity=previous_security
                result=start_show(app)
                try:
                    try:from .window_focus import focus_ppt_show
                    except ImportError:from window_focus import focus_ppt_show
                    focused=focus_ppt_show()
                    if not focused:raise RuntimeError('Focus denied')
                except Exception:
                    result['detail'] += ' (Windows가 창 전환을 막으면 작업 표시줄에서 PowerPoint를 눌러 주세요.)'
                return result
            if action == "start":
                return start_show(app)
            if action != "open":
                raise ValueError("Unknown PowerPoint action")
            if app.SlideShowWindows.Count:
                raise RuntimeError("기존 발표를 Esc로 종료한 후 새 파일을 선택하세요.")
            dialog = app.FileDialog(3)
            dialog.Title = "AirGesture - Choose a PowerPoint file"
            dialog.AllowMultiSelect = False
            dialog.Filters.Clear()
            dialog.Filters.Add("PowerPoint", "*.pptx;*.ppt")
            if dialog.Show() != -1:
                return {"ok": True, "detail": "파일 선택을 취소했습니다."}
            path = str(dialog.SelectedItems.Item(1))
            presentation = app.Presentations.Open(path, True, False, True)
            return {"ok": True, "detail": f"{presentation.Name} 열기 완료. 발표 시작을 누르세요."}
        finally:
            pythoncom.CoUninitialize()
    except ImportError as error:
        raise RuntimeError("PowerPoint integration package is missing; restart AIRGESTURE_PC.cmd") from error
    finally:
        _lock.release()
