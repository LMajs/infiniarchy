#!/usr/bin/env python3
"""List one Chromium window's tabs over the local debugging port, and screenshot
them, without activating a tab or opening a window.

  browser_tabs.py list ADDRESS     JSON for the Hyprland window
  browser_tabs.py activate TARGET  switch to that tab inside its window
"""

import base64
import glob
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import urllib.request
from pathlib import Path

HOME = Path.home()
SHOTS = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "infiniarchy" / "tab-shots"
PORT_FILES = [
    HOME / ".config/BraveSoftware/Brave-Browser/DevToolsActivePort",
    HOME / ".config/chromium/DevToolsActivePort",
    HOME / ".config/google-chrome/DevToolsActivePort",
]
BROWSER = ("brave", "chrome", "chromium")


def browser_port():
    for path in PORT_FILES:
        try:
            port = int(path.read_text().splitlines()[0].strip())
            if port > 0:
                return port
        except (OSError, ValueError, IndexError):
            pass
    try:
        with socket.create_connection(("127.0.0.1", 9222), 0.3):
            return 9222
    except OSError:
        return None


def get_json(port, path):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=3) as resp:
        return json.loads(resp.read().decode())


def _recv(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("debugging port closed the connection")
        buf += chunk
    return buf


def cdp(ws_url, method, params=None, timeout=8):
    host_path = ws_url.split("://", 1)[1]
    host, path = host_path.split("/", 1)
    hostname, port = host.rsplit(":", 1)
    sock = socket.create_connection((hostname, int(port)), timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall(
        f"GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode()
    )
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += _recv(sock, 1)
    if b" 101 " not in buf.split(b"\r\n", 1)[0]:
        raise ConnectionError("debugging port refused the connection")
    payload = json.dumps({"id": 1, "method": method, "params": params or {}}).encode()
    mask = os.urandom(4)
    header = bytes([0x81, 0x80 | len(payload)]) if len(payload) < 126 else bytes([0x81, 0xFE]) + struct.pack(">H", len(payload))
    sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
    sock.settimeout(timeout)
    result = None
    while result is None:
        b0, b1 = _recv(sock, 2)
        ln = b1 & 0x7F
        if ln == 126:
            ln = struct.unpack(">H", _recv(sock, 2))[0]
        elif ln == 127:
            ln = struct.unpack(">Q", _recv(sock, 8))[0]
        data = _recv(sock, ln)
        if b0 & 0x0F != 1:
            continue
        msg = json.loads(data.decode())
        if msg.get("id") == 1:
            if "error" in msg:
                raise RuntimeError(msg["error"].get("message", "devtools call failed"))
            result = msg.get("result", {})
    sock.close()
    return result


def hypr_clients():
    out = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout
    return json.loads(out or "[]")


def is_browser(cls):
    name = str(cls or "").lower()
    return any(part in name for part in BROWSER)


def window_tabs(port):
    pages = [t for t in get_json(port, "/json/list") if t.get("type") == "page" and t.get("webSocketDebuggerUrl")]
    groups = {}
    for page in pages:
        try:
            info = cdp(page["webSocketDebuggerUrl"], "Browser.getWindowForTarget")
        except (OSError, RuntimeError, ValueError):
            continue
        bounds = info.get("bounds") or {}
        group = groups.setdefault(info.get("windowId"), {"bounds": bounds, "tabs": []})
        group["bounds"] = bounds or group["bounds"]
        group["tabs"].append(page)
    return groups


def match_group(groups, client, clients):
    # Wayland does not report window bounds in compositor coordinates, so the
    # window title (the active tab's title) is what ties a Hyprland window to
    # a debugging-port window. Bounds are only a tie-break.
    def titled(group):
        title = client.get("title") or ""
        return any(t.get("title") and t["title"] in title for t in group["tabs"])

    named = [g for g in groups.values() if titled(g)]
    pool = named or (list(groups.values()) if len(groups) == 1 and sum(1 for c in clients if is_browser(c.get("class"))) == 1 else [])
    if not pool:
        return None
    if len(pool) == 1:
        return pool[0]
    cx = client["at"][0] + client["size"][0] / 2
    cy = client["at"][1] + client["size"][1] / 2
    def dist(group):
        b = group["bounds"] or {}
        if not b.get("width"):
            return 1e18
        return (b.get("left", 0) + b["width"] / 2 - cx) ** 2 + (b.get("top", 0) + b["height"] / 2 - cy) ** 2
    return min(pool, key=dist)


def shot(page):
    SHOTS.mkdir(parents=True, exist_ok=True)
    name = hashlib.sha1(page["id"].encode()).hexdigest()[:16] + ".jpg"
    path = SHOTS / name
    try:
        data = cdp(page["webSocketDebuggerUrl"], "Page.captureScreenshot",
                   {"format": "jpeg", "quality": 55}, timeout=6)
        path.write_bytes(base64.b64decode(data["data"]))
        return str(path)
    except (OSError, RuntimeError, ValueError, KeyError):
        return ""


def list_tabs(address):
    port = browser_port()
    if not port:
        return {"ok": False, "error": "no-port",
                "message": "Brave or Chromium is not listening on the debugging port. Relaunch it with --remote-debugging-port=9222"}
    clients = [c for c in hypr_clients() if c.get("address") == address and is_browser(c.get("class"))]
    if not clients:
        return {"ok": False, "error": "not-a-browser", "message": "That window is not a supported browser."}
    group = match_group(window_tabs(port), clients[0], hypr_clients())
    if not group:
        return {"ok": False, "error": "no-match", "message": "Could not match this window to an open browser window."}
    tabs = []
    for page in group["tabs"][:40]:
        tabs.append({
            "id": page["id"],
            "title": page.get("title") or page.get("url") or "Tab",
            "url": page.get("url") or "",
            "favicon": page.get("faviconUrl") or "",
            "image": shot(page),
        })
    return {"ok": True, "tabs": tabs}


def activate(target):
    port = browser_port()
    if not port:
        return {"ok": False, "error": "no-port"}
    for page in get_json(port, "/json/list"):
        if page.get("id") != target or not page.get("webSocketDebuggerUrl"):
            continue
        cdp(page["webSocketDebuggerUrl"], "Target.activateTarget", {"targetId": target})
        # Activating raises the browser's own window; the caller focuses the Hyprland one.
        return {"ok": True}
    return {"ok": False, "error": "gone", "message": "That tab is no longer open."}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "list" and len(sys.argv) == 3:
        print(json.dumps(list_tabs(sys.argv[2])))
    elif cmd == "activate" and len(sys.argv) == 3:
        print(json.dumps(activate(sys.argv[2])))
    elif cmd == "clear":
        for path in glob.glob(str(SHOTS / "*.jpg")):
            os.remove(path)
        print(json.dumps({"ok": True}))
    else:
        print(json.dumps({"ok": False, "error": "usage"}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
