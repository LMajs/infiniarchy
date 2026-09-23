#!/usr/bin/env python3
"""Real-input test of chaining: drag windows edge to edge, drag the chain,
right-click a window to detach. Uses throwaway foot windows on workspace 9 and
a flat lens (restored afterwards). Your own windows are never touched."""

import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAP = 40


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def status():
    return json.loads(sh("omarchy-shell", "shell", "call", "io.github.lmajs.infiniarchy", "status", ""))


def keys(*chords):
    subprocess.run([sys.executable, str(HERE / "press-keys.py"), "--settle", "0.4", *chords])


def pointer(*args):
    subprocess.run([sys.executable, str(HERE / "pointer.py"), *map(str, args)])


def item(st, cls):
    return next(i for i in st["items"] if i["cls"] == cls)


def to_screen(st, x, y):
    # lens is flat: screen = canvas * zoom + pan; recover pan from any item
    ref = st["items"][0]
    z = st["zoom"]
    pan_x = ref["sx"] - (ref["x"] + ref["w"] / 2) * z
    pan_y = ref["sy"] - (ref["y"] + ref["h"] / 2) * z
    return round(x * z + pan_x), round(y * z + pan_y)


def drag_to(cls, tx, ty):
    """Drag window `cls` so its top-left lands at canvas (tx, ty)."""
    st = status()
    it = item(st, cls)
    sx, sy = it["sx"], it["sy"]
    ex, ey = to_screen(st, tx + it["w"] / 2, ty + it["h"] / 2)
    pointer("drag", sx, sy, ex, ey)
    time.sleep(0.6)


def real_windows():
    return {c["class"]: (c["workspace"]["id"], c["floating"], tuple(c["at"]))
            for c in json.loads(sh("hyprctl", "-j", "clients"))}


def main():
    lens = json.loads(sh("infiniarchy", "--json", "config", "get", "lens")).get("lens", 0.55)
    before = real_windows()
    for n in (1, 2, 3):
        sh("hyprctl", "dispatch", f"hl.dsp.exec_cmd(\"foot --app-id canvas-chain-{n} sleep 600\", {{ workspace = '9 silent' }})")
    time.sleep(2.5)
    sh("infiniarchy", "config", "set", "lens", "0")
    ok = True
    try:
        keys("RIGHTALT+Q")
        time.sleep(1.3)
        st = status()
        p1 = item(st, "canvas-chain-1")
        drag_to("canvas-chain-2", p1["x"] + p1["w"] + GAP + 6, p1["y"] + 10)
        st = status()
        p2 = item(st, "canvas-chain-2")
        print("1) chain-2 dropped at", (p2["x"], p2["y"]), "links:", len(st["links"]))
        drag_to("canvas-chain-3", p2["x"] + 8, p2["y"] + p2["h"] + GAP - 5)
        st = status()
        p3 = item(st, "canvas-chain-3")
        print("2) chain-3 dropped at", (p3["x"], p3["y"]), "links:", len(st["links"]))
        ok &= len(st["links"]) == 2
        subprocess.run(["grim", "/tmp/chains-linked.png"])

        before_pos = {c: (item(st, c)["x"], item(st, c)["y"]) for c in ("canvas-chain-1", "canvas-chain-2", "canvas-chain-3")}
        drag_to("canvas-chain-1", before_pos["canvas-chain-1"][0] - 300, before_pos["canvas-chain-1"][1] + 200)
        st = status()
        after_pos = {c: (item(st, c)["x"], item(st, c)["y"]) for c in before_pos}
        deltas = {c: (after_pos[c][0] - before_pos[c][0], after_pos[c][1] - before_pos[c][1]) for c in before_pos}
        print("3) dragged chain-1; deltas:", deltas)
        ok &= len(set(deltas.values())) == 1 and deltas["canvas-chain-1"] != (0, 0)

        c3 = item(st, "canvas-chain-3")
        pointer("click", c3["sx"], c3["sy"], "right")
        time.sleep(0.6)
        st = status()
        print("4) right-clicked chain-3 → links now:", len(st["links"]), "(overlay open:", st["opened"], ")")
        ok &= len(st["links"]) == 1 and st["opened"]
        keys("ESC")
        time.sleep(0.8)
    finally:
        sh("infiniarchy", "config", "set", "lens", str(lens))
        for c in json.loads(sh("hyprctl", "-j", "clients")):
            if c["class"].startswith("canvas-chain"):
                sh("hyprctl", "dispatch", f"hl.dsp.window.close({{ window = 'address:{c['address']}' }})")
        time.sleep(0.6)
    after = real_windows()
    untouched = all(after.get(k) == v for k, v in before.items() if not k.startswith("canvas-chain"))
    print("your windows untouched:", untouched)
    print("PASS" if ok and untouched else "FAIL")


if __name__ == "__main__":
    main()
