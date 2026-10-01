"""WebSocket test: type a command here, the browser page runs it on the YouTube player.

Stands in for the Pi so the WebSocket path can be checked on one PC.

    pip install aiohttp
    python ws_test_server.py
    -> open http://localhost:8080 in a browser, click the video once, then type commands here
"""
import asyncio
import json
from pathlib import Path

from aiohttp import WSMsgType, web

PAGE = Path(__file__).with_name("ws_test.html")
PORT = 8080
HELP = """commands:
  play / pause
  +  /  -        volume +10 / -10
  vol <0-100>    set volume
  q              quit"""

clients = set()


def parse(line):
    """Turn a typed line into a command dict, or None if it is not a command."""
    if line in ("play", "pause"):
        return {"cmd": line}
    if line in ("+", "-"):
        return {"cmd": "volume_step", "delta": 10 if line == "+" else -10}
    parts = line.split()
    if len(parts) == 2 and parts[0] == "vol" and parts[1].isdigit():
        return {"cmd": "volume", "value": min(100, int(parts[1]))}
    return None


async def ws_handler(request):
    ws = web.WebSocketResponse(heartbeat=10)
    await ws.prepare(request)
    clients.add(ws)
    print(f"\n[connected] browser connected (total {len(clients)})")
    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                print(f"\n[browser -> server] {msg.data}")
    finally:
        clients.discard(ws)
        print(f"\n[disconnected] browser left (total {len(clients)})")
    return ws


async def console():
    loop = asyncio.get_running_loop()
    print(HELP)
    while True:
        line = (await loop.run_in_executor(None, input, "> ")).strip()
        if line == "q":
            return
        if not line:
            continue
        cmd = parse(line)
        if cmd is None:
            print("  unknown command")
            continue
        if not clients:
            print("  no browser connected - open the page first")
            continue
        data = json.dumps(cmd)
        for ws in list(clients):
            await ws.send_str(data)
        print(f"  [server -> browser] {data}")


async def main():
    app = web.Application()
    app.router.add_get("/", lambda r: web.FileResponse(PAGE))
    app.router.add_get("/ws", ws_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    # localhost only for this test, so Windows Firewall does not get involved
    await web.TCPSite(runner, "127.0.0.1", PORT).start()
    print(f"open http://localhost:{PORT}")
    try:
        await console()
    finally:
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
