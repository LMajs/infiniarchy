#!/usr/bin/env python3
"""Press real key chords through a temporary /dev/uinput keyboard.

Unlike wtype (which uploads its own keymap), these events go through libinput
with the system keymap, so Hyprland sees genuine keycodes — Right Alt really
is KEY_RIGHTALT. Used to verify the canvas hotkey end-to-end.

  tools/press-keys.py RIGHTALT+Q            # one chord
  tools/press-keys.py RIGHTALT+Q -- ESC      # several, in order
  tools/press-keys.py --gap 1.5 RIGHTALT+Q RIGHTALT+Q
"""

import argparse
import fcntl
import os
import struct
import sys
import time

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_SETUP = 0x405C5503
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
EV_SYN, EV_KEY, SYN_REPORT = 0, 1, 0

KEYS = {
    "ESC": 1, "ESCAPE": 1, "MINUS": 12, "EQUAL": 13, "BACKSPACE": 14, "TAB": 15,
    "ENTER": 28, "RETURN": 28, "LEFTCTRL": 29, "CTRL": 29, "LEFTSHIFT": 42, "SHIFT": 42,
    "GRAVE": 41, "SPACE": 57, "LEFTALT": 56, "ALT": 56, "RIGHTALT": 100, "RALT": 100,
    "LEFTMETA": 125, "SUPER": 125, "UP": 103, "LEFT": 105, "RIGHT": 106, "DOWN": 108,
    "HOME": 102, "END": 107, "COMMA": 51, "DOT": 52, "PERIOD": 52, "SLASH": 53,
}
for i, ch in enumerate("QWERTYUIOP"):
    KEYS[ch] = 16 + i
for i, ch in enumerate("ASDFGHJKL"):
    KEYS[ch] = 30 + i
for i, ch in enumerate("ZXCVBNM"):
    KEYS[ch] = 44 + i
for i, ch in enumerate("1234567890"):
    KEYS[ch] = 2 + i
for i in range(10):
    KEYS[f"F{i + 1}"] = 59 + i
KEYS["F11"], KEYS["F12"] = 87, 88


def emit(fd, etype, code, value):
    now = time.time()
    sec, usec = int(now), int((now % 1) * 1e6)
    os.write(fd, struct.pack("llHHi", sec, usec, etype, code, value))


def chord(fd, names, hold):
    codes = []
    for name in names:
        code = KEYS.get(name.upper())
        if code is None:
            sys.exit(f"unknown key {name!r}")
        codes.append(code)
    for code in codes:
        emit(fd, EV_KEY, code, 1)
        emit(fd, EV_SYN, SYN_REPORT, 0)
        time.sleep(0.04)
    time.sleep(hold)
    for code in reversed(codes):
        emit(fd, EV_KEY, code, 0)
        emit(fd, EV_SYN, SYN_REPORT, 0)
        time.sleep(0.04)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("chords", nargs="+")
    parser.add_argument("--gap", type=float, default=0.6, help="seconds between chords")
    parser.add_argument("--hold", type=float, default=0.08, help="seconds to hold each chord")
    parser.add_argument("--settle", type=float, default=1.0, help="seconds to wait for the device to appear")
    args = parser.parse_args()

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for code in set(KEYS.values()):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    setup = struct.pack("HHHH80sI", 0x03, 0x1209, 0xCA11, 1, b"infiniarchy-test-keyboard", 0)
    fcntl.ioctl(fd, UI_DEV_SETUP, setup)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    try:
        time.sleep(args.settle)
        first = True
        for spec in args.chords:
            if spec == "--":
                continue
            if not first:
                time.sleep(args.gap)
            first = False
            chord(fd, spec.split("+"), args.hold)
        time.sleep(0.2)
    finally:
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        os.close(fd)


if __name__ == "__main__":
    main()
