"""Run on Raspberry Pi once, then enter the PC address and printed bridge key."""
import json
from urllib.request import Request, build_opener, ProxyHandler
from command_bridge import DEFAULT_CONFIG


def main():
    address = input("Windows PC IPv4 address (example 192.168.0.10): ").strip()
    if not address or any(c not in "0123456789." for c in address):
        raise ValueError("Enter the IPv4 address shown by the PC, not the Raspberry Pi address")
    token = input("BRIDGE KEY shown in PC terminal: ").strip()
    if len(token) < 16 or not token.isalnum():
        raise ValueError("Copy the complete BRIDGE KEY from the PC terminal")
    url = f"http://{address}:8765"
    request = Request(url + "/api/health", headers={"Authorization": "Bearer " + token})
    opener = build_opener(ProxyHandler({}))
    with opener.open(request, timeout=4) as response:
        result = json.load(response)
    if not result.get("ok"):
        raise RuntimeError("PC connection check failed")
    DEFAULT_CONFIG.write_text(json.dumps({"pc_url": url, "token": token}, indent=2), encoding="utf-8")
    print(f"PC connected. Saved {DEFAULT_CONFIG.name}. Configuration only; camera is not running. Now run: python main.py --camera 0 --headless --fps 30 --preview-fps 25")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Setup failed: {error}\nCheck PC receiver, same network, IP, key, and Windows firewall.")
        raise SystemExit(1)
