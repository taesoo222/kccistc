"""Runs on the Pi: serves the player page to the PC and forwards gesture commands.

    recognizer --UDP JSON--> [this server: MediaController] --WebSocket--> PC browser (player.html)

    python server.py                       # page on http://<pi-ip>:8080
    python server.py --http-port 9000 --udp-port 5005 -v
"""
import argparse
import asyncio
import json
import logging
from pathlib import Path

from aiohttp import WSMsgType, web

from media_controller import MediaController

log = logging.getLogger("server")
WEB_DIR = Path(__file__).parent / "web"
TICK_S = 0.1


class PlayerHub:
    """Connected player pages. Commands go to every page; normally there is one."""

    def __init__(self):
        self.clients = set()
        self.controller = None
        self._tasks = set()  # keep send tasks referenced until they finish

    def send(self, cmd):
        data = json.dumps(cmd)
        for ws in list(self.clients):
            task = asyncio.get_running_loop().create_task(self._send_one(ws, data))
            self._tasks.add(task)
            task.add_done_callback(self._tasks.discard)

    async def _send_one(self, ws, data):
        try:
            await ws.send_str(data)
        except Exception as e:  # page closed mid-send
            log.debug("send failed: %s", e)
            self.clients.discard(ws)

    async def handle_ws(self, request):
        ws = web.WebSocketResponse(heartbeat=10)
        await ws.prepare(request)
        self.clients.add(ws)
        log.info("player connected: %s", request.remote)
        await ws.send_str(json.dumps({"cmd": "mode", "mode": self.controller.state}))
        try:
            async for msg in ws:
                if msg.type != WSMsgType.TEXT:
                    continue
                try:
                    status = json.loads(msg.data)
                except ValueError:
                    continue
                if status.get("type") == "status":
                    self.controller.on_player_status(status)
        finally:
            self.clients.discard(ws)
            log.info("player disconnected: %s", request.remote)
        return ws


class GestureUdp(asyncio.DatagramProtocol):
    def __init__(self, controller):
        self.controller = controller

    def datagram_received(self, data, addr):
        try:
            ev = json.loads(data)
        except ValueError:
            log.warning("bad datagram from %s: %r", addr, data[:80])
            return
        log.debug("event %s", ev)
        self.controller.on_event(ev)


async def ticker(controller):
    while True:
        await asyncio.sleep(TICK_S)
        controller.tick()


async def main(args):
    hub = PlayerHub()
    controller = MediaController(hub.send)
    hub.controller = controller

    app = web.Application()
    app.router.add_get("/ws", hub.handle_ws)
    app.router.add_get("/", lambda r: web.FileResponse(WEB_DIR / "player.html"))
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, args.http_host, args.http_port).start()

    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(
        lambda: GestureUdp(controller), local_addr=(args.udp_host, args.udp_port))

    log.info("player page: http://<pi-ip>:%d   gestures: udp %s:%d",
             args.http_port, args.udp_host, args.udp_port)
    await ticker(controller)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--http-host", default="0.0.0.0")
    p.add_argument("--http-port", type=int, default=8080)
    p.add_argument("--udp-host", default="127.0.0.1", help="use 0.0.0.0 if the recognizer runs on another machine")
    p.add_argument("--udp-port", type=int, default=5005)
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(name)s %(levelname)s %(message)s")
    try:
        asyncio.run(main(args))
    except KeyboardInterrupt:
        pass
