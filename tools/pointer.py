#!/usr/bin/env python3
"""Drive the real pointer for tests: warp with Hyprland, click/scroll via uinput.

  tools/pointer.py move X Y
  tools/pointer.py click X Y [left|right|middle]
  tools/pointer.py scroll X Y STEPS        # +up / -down (wheel notches)
  tools/pointer.py drag X1 Y1 X2 Y2 [left|right|middle]
"""

import fcntl
import os
import struct
import subprocess
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x5501, 0x5502
EV_SYN, EV_KEY, EV_REL = 0, 1, 2
REL_X, REL_Y, REL_WHEEL, REL_WHEEL_HI_RES = 0, 1, 8, 11
BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}


def warp(x, y):
    subprocess.run(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{ x = {int(x)}, y = {int(y)} }})"],
                   capture_output=True)


class Mouse:
    def __enter__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
        for code in BUTTONS.values():
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        for code in (REL_X, REL_Y, REL_WHEEL, REL_WHEEL_HI_RES):
            fcntl.ioctl(self.fd, UI_SET_RELBIT, code)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x03, 0x1209, 0xCA12, 1, b"infiniarchy-test-mouse", 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(1.0)
        return self

    def __exit__(self, *exc):
        time.sleep(0.1)
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)

    def emit(self, etype, code, value):
        now = time.time()
        os.write(self.fd, struct.pack("llHHi", int(now), int((now % 1) * 1e6), etype, code, value))

    def syn(self):
        self.emit(EV_SYN, 0, 0)

    def nudge(self):
        # A tiny real motion so the compositor re-evaluates the surface under the cursor.
        self.emit(EV_REL, REL_X, 1); self.syn(); time.sleep(0.03)
        self.emit(EV_REL, REL_X, -1); self.syn(); time.sleep(0.05)

    def button(self, name, down):
        self.emit(EV_KEY, BUTTONS[name], 1 if down else 0)
        self.syn()

    def move(self, dx, dy):
        self.emit(EV_REL, REL_X, dx); self.emit(EV_REL, REL_Y, dy); self.syn()

    def wheel(self, steps):
        for _ in range(abs(steps)):
            self.emit(EV_REL, REL_WHEEL, 1 if steps > 0 else -1)
            self.emit(EV_REL, REL_WHEEL_HI_RES, 120 if steps > 0 else -120)
            self.syn()
            time.sleep(0.05)


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    with Mouse() as m:
        if cmd == "move":
            warp(args[0], args[1]); time.sleep(0.1); m.nudge()
        elif cmd == "click":
            warp(args[0], args[1]); time.sleep(0.1); m.nudge()
            name = args[2] if len(args) > 2 else "left"
            m.button(name, True); time.sleep(0.06); m.button(name, False)
        elif cmd == "scroll":
            warp(args[0], args[1]); time.sleep(0.1); m.nudge()
            m.wheel(int(args[2]))
        elif cmd == "drag":
            x1, y1, x2, y2 = map(float, args[:4])
            name = args[4] if len(args) > 4 else "left"
            warp(x1, y1); time.sleep(0.1); m.nudge()
            m.button(name, True)
            # Warp to exact points (relative motion would be accelerated by libinput).
            steps = 20
            for s in range(1, steps + 1):
                warp(x1 + (x2 - x1) * s / steps, y1 + (y2 - y1) * s / steps)
                m.nudge()
            time.sleep(0.1)
            m.button(name, False)
        else:
            sys.exit(__doc__)


if __name__ == "__main__":
    main()
