"""Windows PC receiver. YouTube uses the local web page; PPT uses desktop COM."""
import argparse
from collections import OrderedDict
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import socket
import threading
import time
import webbrowser
import subprocess
import sys
import uuid
from pointer_receiver import PointerReceiver, WindowsMouse
from urllib.parse import urlsplit, parse_qs

try:
    from . import powerpoint_control
except ImportError:
    import powerpoint_control

ROOT = Path(__file__).resolve().parent
COMMANDS = {"PLAY", "PAUSE", "VOLUME_UP", "VOLUME_DOWN", "NEXT", "PREVIOUS", "VIDEO_NEXT", "VIDEO_PREVIOUS", "MODE_MOUSE", "MODE_MEDIA", "MODE_PPT", "MODE_MAIN"}
try:
    from .desktop_control import DesktopControl
    from .status_state import StatusState
except ImportError:
    from desktop_control import DesktopControl
    from status_state import StatusState


class Broker:
    def __init__(self, desktop=None):
        self.desktop=desktop or DesktopControl(ROOT)
        self.command_lock=threading.Lock()
        self.cache=OrderedDict()
        self.last_result={"detail":"Select MEDIA or PPT on the camera"}
        self.status=StatusState()

    def execute(self,event_id,command):
        if not self.command_lock.acquire(timeout=0.15):
            return {"ok":False,"detail":"App is opening/processing. Wait, then repeat your gesture."}
        try:
            if event_id in self.cache:
                previous,result=self.cache[event_id]
                return result if previous==command else {"ok":False,"detail":"Duplicate id mismatch"}
            try:
                self.status.begin(command)
                result=self.desktop.execute(command)
            except Exception as error:
                result={"ok":False,"detail":str(error)[:500]}
            self.last_result={**result,"command":command}
            self.status.finish(command,result)
            self.cache[event_id]=(command,result)
            while len(self.cache)>256:self.cache.popitem(last=False)
            print(json.dumps(self.last_result,ensure_ascii=True),flush=True)
            return result
        finally:self.command_lock.release()

    def poll(self,client,ready):
        return {"ok":True,"event":None,"last_result":self.last_result}

    def acknowledge(self,*args):
        return False


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, token, broker=None):
        self.token = token
        self.instance=uuid.uuid4().hex
        self.pointer=None
        self.broker = broker or Broker()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, code, data, mime="application/json; charset=utf-8"):
        body = json.dumps(data).encode() if not isinstance(data, bytes) else data
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def authenticated(self):
        expected = "Bearer " + self.server.token
        if not hmac.compare_digest(self.headers.get("Authorization", ""), expected):
            self.reply(401, {"ok": False, "detail": "Incorrect bridge key"})
            return False
        origin = self.headers.get("Origin")
        if origin and origin != "http://" + self.headers.get("Host", ""):
            self.reply(403, {"ok": False, "detail": "Origin rejected"})
            return False
        return True

    def local_page(self):
        port = self.server.server_address[1]
        return (self.client_address[0] in ("127.0.0.1", "::1") and
                self.headers.get("Host") in (f"127.0.0.1:{port}", f"localhost:{port}"))

    def do_GET(self):
        parsed = urlsplit(self.path)
        if parsed.path in ("/", "/player.js"):
            if not self.local_page():
                return self.reply(403, {"detail": "Open the player on this PC at http://127.0.0.1:8765"})
            if parsed.path == "/":
                body = (ROOT / "index.html").read_text(encoding="utf-8").replace("__BRIDGE_TOKEN__", self.server.token)
                return self.reply(200, body.encode(), "text/html; charset=utf-8")
            return self.reply(200, (ROOT / "player.js").read_bytes(), "text/javascript; charset=utf-8")
        if not self.authenticated():
            return
        if parsed.path == '/api/status':
            return self.reply(200,{'ok':True,'instance':self.server.instance,'mouse_enabled':bool(self.server.pointer and self.server.pointer.enabled),**self.server.broker.status.snapshot()})
        if parsed.path == "/api/poll":
            query = parse_qs(parsed.query)
            client = query.get("client", [""])[0]
            if not client or len(client) > 80:
                return self.reply(400, {"detail": "Invalid client id"})
            return self.reply(200, self.server.broker.poll(client, query.get("ready", ["0"])[0] == "1"))
        if parsed.path == "/api/health":
            return self.reply(200, {"ok": True, "detail": "PC receiver connected (OVERLAY_V3)",
                                    "version": "OVERLAY_V3", "commands": sorted(COMMANDS)})
        self.reply(404, {"detail": "Not found"})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            maximum=140000 if self.path=='/api/telemetry' else 4096
            if not 0 < length <= maximum:
                raise ValueError("Invalid body size")
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError("Expected JSON object")
        except (ValueError, UnicodeDecodeError) as error:
            return self.reply(400, {"ok": False, "detail": str(error)})
        if not self.authenticated():
            return
        if self.path == '/pointer':
            if self.server.pointer is None:return self.reply(503,{'ok':False})
            try:self.server.pointer.apply(data)
            except (ValueError,TypeError,KeyError) as error:return self.reply(400,{'ok':False,'detail':str(error)})
            return self.reply(200,{'ok':True})
        if self.path == '/api/mouse':
            if not self.local_page():return self.reply(403,{'ok':False})
            if self.server.pointer is None:return self.reply(503,{'ok':False})
            if type(data.get('enabled')) is not bool:return self.reply(400,{'ok':False})
            self.server.pointer.set_enabled(data['enabled'])
            return self.reply(200,{'ok':True})
        if self.path == '/api/telemetry':
            data['stream_host']=self.client_address[0]
            try:self.server.broker.status.update(data)
            except ValueError as error:return self.reply(400,{'ok':False,'detail':str(error)})
            return self.reply(200,{'ok':True})
        if self.path == '/api/overlay':
            if not self.local_page():return self.reply(403,{'ok':False,'detail':'Use the local PC page'})
            if not isinstance(data.get('visible'),bool):return self.reply(400,{'ok':False,'detail':'Expected visible boolean'})
            with self.server.broker.status.lock:self.server.broker.status.visible=data['visible']
            return self.reply(200,{'ok':True})
        if self.path in ("/api/ppt/open", "/api/ppt/start"):
            if not self.local_page():
                return self.reply(403, {"ok": False, "detail": "Use the PC page to open/start PowerPoint"})
            try:
                result = powerpoint_control.manage(self.path.rsplit("/", 1)[1])
                return self.reply(200, result)
            except Exception as error:
                return self.reply(409, {"ok": False, "detail": str(error)[:240]})
        if self.path == "/api/command":
            command, event_id = data.get("command"), data.get("id")
            if not isinstance(command, str) or command not in COMMANDS or not isinstance(event_id, str) or not 1 <= len(event_id) <= 80:
                return self.reply(400, {"ok": False, "detail": "Invalid command/id"})
            result = self.server.broker.execute(event_id, command)
            return self.reply(200 if result["ok"] else 409, result)
        if self.path == "/api/ack":
            ok = self.server.broker.acknowledge(data.get("client"), data.get("id"), data.get("ok") is True, data.get("detail", ""))
            return self.reply(200, {"ok": ok})
        self.reply(404, {"detail": "Not found"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--open-browser", action="store_true")
    parser.add_argument('--no-overlay',action='store_true')
    args = parser.parse_args()
    key_file = ROOT / "bridge_key.txt"
    if not key_file.exists():
        key_file.write_text(secrets.token_hex(16), encoding="ascii")
    token = key_file.read_text(encoding="ascii").strip()
    if len(token) < 16 or not token.isalnum():
        raise ValueError("bridge_key.txt must contain at least 16 letters/numbers")
    try:
        server = BridgeServer((args.host, args.port), token)
    except OSError as error:
        if error.errno in (48, 98, 10048) or getattr(error, 'winerror', None) == 10048:
            print(f"Port {args.port} is already in use. Close the old PC receiver terminal, then run AIRGESTURE_PC.cmd again.")
            return
        raise
    print(f"AIRGESTURE OVERLAY_V3 | {ROOT}", flush=True)
    print(f"PC PLAYER: http://127.0.0.1:{args.port}", flush=True)
    print(f"PC IP candidates: {', '.join(socket.gethostbyname_ex(socket.gethostname())[2])}", flush=True)
    print(f"BRIDGE KEY: {token}", flush=True)
    print("Keep this terminal open. Allow Python on your private network if Windows asks.", flush=True)
    if args.open_browser:
        webbrowser.open(f"http://127.0.0.1:{args.port}")
    pointer_stop=threading.Event()
    if sys.platform=='win32':
        server.pointer=PointerReceiver(WindowsMouse())
        def pointer_watchdog():
            while not pointer_stop.wait(.05):server.pointer.watchdog()
        threading.Thread(target=pointer_watchdog,daemon=True).start()
    overlay=None
    overlay_log=None
    if not args.no_overlay and sys.platform=='win32':
        pythonw=Path(sys.executable).with_name('pythonw.exe')
        overlay_log=(ROOT/'overlay_error.log').open('a',encoding='utf8')
        overlay=subprocess.Popen([str(pythonw if pythonw.exists() else sys.executable),
            str(ROOT/'overlay.py'),'--port',str(args.port),'--instance',server.instance],
            cwd=ROOT,stdout=subprocess.DEVNULL,stderr=overlay_log,
            creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopped")
    finally:
        pointer_stop.set()
        if server.pointer:server.pointer.set_enabled(False)
        server.server_close()
        if overlay and overlay.poll() is None:overlay.terminate()
        if overlay_log:overlay_log.close()
        server.broker.desktop.close()


if __name__ == "__main__":
    main()
