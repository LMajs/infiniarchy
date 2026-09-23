#!/usr/bin/env python3
"""Query the running canvas overlay over omarchy-shell IPC.

  tools/probe.py status          # overlay state as JSON
  tools/probe.py latency [n]     # shell IPC round-trip times (ms)
"""

import json
import subprocess
import sys
import time


def call(*args):
    return subprocess.run(["omarchy-shell", "shell", *args], capture_output=True, text=True, timeout=10)


def status():
    out = call("call", "io.github.lmajs.infiniarchy", "status", "").stdout.strip()
    try:
        return json.loads(out)
    except ValueError:
        return {"error": out or "no reply"}


def latency(n=5):
    times = []
    for _ in range(n):
        t = time.perf_counter()
        call("ping")
        times.append(round((time.perf_counter() - t) * 1000))
        time.sleep(0.2)
    return times


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "latency":
        print(json.dumps(latency(int(sys.argv[2]) if len(sys.argv) > 2 else 5)))
    else:
        print(json.dumps(status()))
