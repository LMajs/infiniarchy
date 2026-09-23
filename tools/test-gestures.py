#!/usr/bin/env python3
"""Real-input test of the mouse scheme with throwaway windows on workspace 9:

  L1  R1        L1 is linked to R1; R1-R2-R3 are a vertical chain.
      R2        Right-drag selects R1..R3, right-click cuts them loose from L1,
      R3        left-drag moves the selection, right-click unlinks a single
                window, middle-click closes one, middle-drag pans.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAYOUT = Path.home() / ".local/state/infiniarchy/layout.json"
SEED = {"L1": (0, 5000), "R1": (940, 5000), "R2": (940, 5600), "R3": (940, 6200)}
W, H = 900, 560


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def status():
    return json.loads(sh("omarchy-shell", "shell", "call", "io.github.lmajs.infiniarchy", "status", ""))


def keys(*chords):
    subprocess.run([sys.executable, str(HERE / "press-keys.py"), "--settle", "0.4", *chords])


def pointer(*args):
    subprocess.run([sys.executable, str(HERE / "pointer.py"), *map(str, args)])


def screen(st, x, y):
    ref = st["items"][0]
    z = st["zoom"]
    return (round(x * z + ref["sx"] - (ref["x"] + ref["w"] / 2) * z),
            round(y * z + ref["sy"] - (ref["y"] + ref["h"] / 2) * z))


def by_cls(st):
    return {i["cls"].replace("canvas-g-", ""): i for i in st["items"] if i["cls"].startswith("canvas-g-")}


def link_names(st, addr_name):
    return sorted(tuple(sorted((addr_name.get(a, "?"), addr_name.get(b, "?")))) for a, b in st["links"]
                  if a in addr_name or b in addr_name)


def check(label, cond):
    print(("  ok   " if cond else "  FAIL ") + label)
    return cond


def main():
    lens = json.loads(sh("infiniarchy", "--json", "config", "get", "lens")).get("lens", 0.55)
    mine = {c["address"]: (c["workspace"]["id"], c["floating"], tuple(c["at"])) for c in json.loads(sh("hyprctl", "-j", "clients"))}

    d = json.loads(LAYOUT.read_text())
    d["windows"] = {k: v for k, v in d["windows"].items() if not str(v.get("cls", "")).startswith("canvas-g-")}
    for n, (x, y) in SEED.items():
        d["windows"][f"0xseed{n}"] = {"x": x, "y": y, "w": W, "h": H, "cls": f"canvas-g-{n}", "title": "", "seen": int(time.time() * 1000)}
    LAYOUT.write_text(json.dumps(d, indent=1))
    time.sleep(0.5)
    for n in SEED:
        sh("hyprctl", "dispatch", f"hl.dsp.exec_cmd(\"foot --app-id canvas-g-{n} sleep 600\", {{ workspace = '9 silent' }})")
        time.sleep(0.6)
    time.sleep(2)
    sh("infiniarchy", "config", "set", "lens", "0")
    ok = True
    try:
        keys("RIGHTALT+Q")
        time.sleep(1.3)
        st = status()
        g = by_cls(st)
        name = {v["a"]: k for k, v in g.items()}
        ok &= check("windows placed at seeded spots", all((g[n]["x"], g[n]["y"]) == SEED[n] for n in SEED))

        # Link them the way the screenshot shows (written like the plugin would).
        d = json.loads(LAYOUT.read_text())
        d["links"] = [k for k in d.get("links", []) if k[0] not in name and k[1] not in name]
        d["links"] += [[g["L1"]["a"], g["R1"]["a"]], [g["R1"]["a"], g["R2"]["a"]], [g["R2"]["a"], g["R3"]["a"]]]
        LAYOUT.write_text(json.dumps(d, indent=1))
        time.sleep(0.8)
        st = status()
        ok &= check("3 links: L1-R1, R1-R2, R2-R3", link_names(st, name) == [("L1", "R1"), ("R1", "R2"), ("R2", "R3")])

        # Right-drag from the gap left of R1 to below-right of R3.
        x0, y0 = screen(st, 920, 4990)
        x1, y1 = screen(st, 940 + W + 30, 6200 + H + 30)
        pointer("drag", x0, y0, x1, y1, "right")
        time.sleep(0.5)
        st = status()
        picked = sorted(name[a] for a in st["picked"] if a in name)
        ok &= check(f"right-drag selected R1,R2,R3 (got {picked})", picked == ["R1", "R2", "R3"])
        subprocess.run(["grim", "/tmp/gestures-selected.png"])

        pointer("click", g["R2"]["sx"], g["R2"]["sy"], "right")
        time.sleep(0.5)
        st = status()
        ok &= check(f"right-click on selection cut it loose from L1 ({link_names(st, name)}, toast '{st['toast']}')",
                    link_names(st, name) == [("R1", "R2"), ("R2", "R3")])
        ok &= check("canvas still open", st["opened"])

        g = by_cls(st)
        before = {n: (g[n]["x"], g[n]["y"]) for n in g}
        pointer("drag", g["R1"]["sx"], g["R1"]["sy"], g["R1"]["sx"] + 90, g["R1"]["sy"] + 30)
        time.sleep(0.6)
        st = status()
        g = by_cls(st)
        delta = {n: (g[n]["x"] - before[n][0], g[n]["y"] - before[n][1]) for n in g}
        ok &= check(f"left-drag moved the selection together, L1 stayed ({delta})",
                    delta["L1"] == (0, 0) and delta["R1"] == delta["R2"] == delta["R3"] != (0, 0))
        subprocess.run(["grim", "/tmp/gestures-moved.png"])

        keys("ESC")
        time.sleep(0.4)
        st = status()
        ok &= check("Esc cleared the selection, canvas open", not st["picked"] and st["opened"])

        g = by_cls(st)
        pointer("click", g["R3"]["sx"], g["R3"]["sy"], "right")
        time.sleep(0.5)
        st = status()
        ok &= check(f"right-click on single R3 unlinked it from all ({link_names(st, name)})", link_names(st, name) == [("R1", "R2")])

        g = by_cls(st)
        zoom0, sx0 = st["zoom"], g["R1"]["sx"]
        pointer("drag", g["R2"]["sx"], g["R2"]["sy"], g["R2"]["sx"] - 120, g["R2"]["sy"] - 40, "middle")
        time.sleep(0.5)
        st = status()
        g2 = by_cls(st)
        ok &= check(f"middle-drag on a window panned (screen x {sx0} -> {g2['R1']['sx']}), canvas positions unchanged",
                    abs(g2["R1"]["sx"] - (sx0 - 120)) <= 3 and (g2["R1"]["x"], g2["R1"]["y"]) == (g["R1"]["x"], g["R1"]["y"]))

        pointer("click", g2["L1"]["sx"], g2["L1"]["sy"], "middle")
        time.sleep(1.2)
        alive = [c["class"] for c in json.loads(sh("hyprctl", "-j", "clients"))]
        ok &= check(f"middle-click closed L1 (toast '{status()['toast']}')", "canvas-g-L1" not in alive and "canvas-g-R1" in alive)
        keys("ESC")
        time.sleep(0.8)
    finally:
        sh("infiniarchy", "config", "set", "lens", str(lens))
        for c in json.loads(sh("hyprctl", "-j", "clients")):
            if c["class"].startswith("canvas-g-"):
                sh("hyprctl", "dispatch", f"hl.dsp.window.close({{ window = 'address:{c['address']}' }})")
        time.sleep(0.8)
        d = json.loads(LAYOUT.read_text())
        d["windows"] = {k: v for k, v in d["windows"].items() if not str(v.get("cls", "")).startswith("canvas-g-")}
        LAYOUT.write_text(json.dumps(d, indent=1))
    after = {c["address"]: (c["workspace"]["id"], c["floating"], tuple(c["at"])) for c in json.loads(sh("hyprctl", "-j", "clients"))}
    ok &= check("your windows untouched", all(after.get(a) == v for a, v in mine.items() if a in after) and set(mine) <= set(after))
    print("PASS" if ok else "FAIL")


if __name__ == "__main__":
    main()
