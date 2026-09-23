#!/usr/bin/env python3
"""Real-input test of the flat view: scroll into the curved overview until it
snaps to a flat 1:1 view, pan there, then scroll out back to the curved view.
  tools/test-flat-view.py [recording.mp4]"""

import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def status():
    return json.loads(sh("omarchy-shell", "shell", "call", "io.github.lmajs.infiniarchy", "status", ""))


def keys(*chords):
    subprocess.run([sys.executable, str(HERE / "press-keys.py"), "--settle", "0.4", *chords])


def pointer(*args):
    subprocess.run([sys.executable, str(HERE / "pointer.py"), *map(str, args)])


def check(label, cond):
    print(("  ok   " if cond else "  FAIL ") + label)
    return cond


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else ""
    rec = None
    if out:
        rec = subprocess.Popen(["gpu-screen-recorder", "-w", "eDP-1", "-f", "60", "-fallback-cpu-encoding", "yes", "-o", out],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)
    ok = True
    try:
        keys("RIGHTALT+Q")
        time.sleep(1.3)
        st = status()
        ok &= check(f"opened curved (zoom {st['zoom']}, lens {st['lens']}, flat {st['flat']})", st["opened"] and not st["flat"])
        target = max(st["items"], key=lambda i: i["w"] * i["h"])
        notches = 0
        while not status()["flat"] and notches < 12:
            pointer("scroll", target["sx"], target["sy"], 1)
            time.sleep(0.4)
            notches += 1
            st = status()
            print(f"    notch {notches}: zoom={st['zoom']} lens={st['lens']} flat={st['flat']}")
        time.sleep(0.5)
        st = status()
        ok &= check(f"snapped to flat 1:1 (zoom {st['zoom']}, lens {st['lens']}), still in the canvas", st["flat"] and abs(st["zoom"] - 1) < 0.01 and st["lens"] == 0 and st["opened"])
        subprocess.run(["grim", "/tmp/flat-view.png"])
        pointer("drag", 1300, 600, 900, 500, "middle")
        time.sleep(0.5)
        st2 = status()
        ok &= check("panning works in flat view", st2["flat"] and st2["zoom"] == st["zoom"])
        pointer("scroll", 960, 540, -1)
        time.sleep(0.6)
        st = status()
        ok &= check(f"scrolling out returned to the curved view (zoom {st['zoom']}, lens {st['lens']})", not st["flat"] and st["lens"] > 0 or not st["flat"])
        subprocess.run(["grim", "/tmp/flat-back.png"])
        keys("ESC")
        time.sleep(0.8)
    finally:
        if rec:
            time.sleep(0.3)
            rec.send_signal(2)
            rec.wait()
    print("PASS" if ok else "FAIL")


if __name__ == "__main__":
    main()
