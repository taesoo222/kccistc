"""Nonblocking Pi-to-PC transport; never retry potentially executed commands."""
import json
from pathlib import Path
import queue
import threading
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, ProxyHandler
import uuid

DEFAULT_CONFIG = Path(__file__).resolve().parent / "bridge_config.json"
COMMANDS = {"PLAY", "PAUSE", "VOLUME_UP", "VOLUME_DOWN", "NEXT", "PREVIOUS", "VIDEO_NEXT", "VIDEO_PREVIOUS", "MODE_MOUSE", "MODE_MAIN", "MODE_MEDIA", "MODE_PPT"}


class CommandBridge:
    def __init__(self, config_path=DEFAULT_CONFIG):
        data = json.loads(Path(config_path).read_text(encoding="utf-8"))
        self.url = data["pc_url"].rstrip("/")
        parsed = urlsplit(self.url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.path or parsed.username or parsed.query or parsed.fragment:
            raise ValueError("pc_url must be http://PC_IP:8765")
        self.token = data["token"]
        if not isinstance(self.token, str) or len(self.token) < 16:
            raise ValueError("Invalid bridge key")
        self.pending = queue.Queue(maxsize=4)
        self.results = queue.Queue()
        self.stopped = threading.Event()
        self.status = "CONNECTING"
        self.opener = build_opener(ProxyHandler({}))
        self.worker = threading.Thread(target=self._run, daemon=True)
        self.worker.start()
        self.telemetry_lock=threading.Lock()
        self.latest_state=None
        self.state_generation=0
        self.telemetry_worker=threading.Thread(target=self._telemetry_run,daemon=True)
        self.telemetry_worker.start()

    def publish_state(self,state):
        with self.telemetry_lock:
            self.latest_state=dict(state)
            self.state_generation+=1

    def _telemetry_run(self):
        opener=build_opener(ProxyHandler({}))
        sent_generation=-1
        while not self.stopped.is_set():
            with self.telemetry_lock:
                data=self.latest_state;generation=self.state_generation
            if data is not None and generation!=sent_generation:
                try:
                    req=Request(self.url+'/api/telemetry',data=json.dumps(data).encode(),
                        headers={'Authorization':'Bearer '+self.token,'Content-Type':'application/json'})
                    with opener.open(req,timeout=1) as response:response.read()
                    sent_generation=generation
                except Exception:pass  # Status display must never block gesture commands.
            self.stopped.wait(.05)

    def request(self, path, data=None):
        payload = json.dumps(data).encode() if data is not None else None
        request = Request(self.url + path, data=payload,
                          headers={"Authorization": "Bearer " + self.token,
                                   "Content-Type": "application/json"})
        try:
            with self.opener.open(request, timeout=45.0) as response:
                return json.load(response)
        except HTTPError as error:
            try:
                return json.loads(error.read().decode())
            except (ValueError, UnicodeDecodeError):
                return {"ok": False, "detail": f"PC HTTP error {error.code}"}

    def send(self, command):
        if command not in COMMANDS:
            raise ValueError("Unknown bridge command")
        try:
            self.pending.put_nowait((time.monotonic(), uuid.uuid4().hex, command))
            return True
        except queue.Full:
            self.results.put((command, {"ok": False, "detail": "Command queue full; input dropped"}))
            return False

    def cancel_pending(self, preserve_mode=True):
        kept=[]
        while True:
            try:
                item = self.pending.get_nowait()
                _, _, command = item
                if preserve_mode and command.startswith('MODE_'):
                    kept.append(item)
                    continue
                self.results.put((command, {"ok": False, "detail": "Pending command cancelled"}))
            except queue.Empty:
                break
        for item in kept:
            try:self.pending.put_nowait(item)
            except queue.Full: self.results.put((item[2], {'ok':False,'detail':'Mode queue full'}))

    def drain_results(self):
        items = []
        while True:
            try:
                items.append(self.results.get_nowait())
            except queue.Empty:
                return items

    def _run(self):
        try:
            result = self.request("/api/health")
            self.status = "CONNECTED" if result.get("ok") else "ERROR (see terminal)"
            self.results.put(("CONNECT", result))
        except Exception as error:
            self.status = "OFFLINE (check PC/IP/key)"
            self.results.put(("CONNECT", {"ok": False, "detail": str(error)}))
        while not self.stopped.is_set():
            try:
                created, event_id, command = self.pending.get(timeout=0.1)
            except queue.Empty:
                continue
            if not command.startswith('MODE_') and time.monotonic() - created > 0.8:
                self.results.put((command, {"ok": False, "detail": "Stale command dropped"}))
                continue
            try:
                result = self.request("/api/command", {"id": event_id, "command": command})
                self.status = f"OK: {command}" if result.get("ok") else "ERROR (see terminal)"
            except Exception as error:
                result = {"ok": False, "detail": f"PC connection failed: {error}"}
                self.status = "OFFLINE (check PC/IP/key)"
            self.results.put((command, result))

    def close(self):
        self.stopped.set()
        self.cancel_pending(preserve_mode=False)
        self.worker.join(timeout=0.2)
        self.telemetry_worker.join(timeout=0.2)
