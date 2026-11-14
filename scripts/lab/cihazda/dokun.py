#!/usr/bin/env python3
"""dokun.py: a virtual touchscreen for the home-screen gesture tests (lab only).

Creates one multitouch device through /dev/uinput (kernel r28+, CONFIG_INPUT_UINPUT) and
plays touches read from stdin, one command per line, answering "ok" or "hata ...":

  dokun X Y [MS]               tap (finger down MS ms, default 60)
  kaydir X1 Y1 X2 Y2 [MS]      swipe from (X1,Y1) to (X2,Y2) in MS ms (default 250)
  bekle S                      sleep S seconds
  bitti                        remove the device and exit

X, Y are sway layout pixels (logical, as swaymsg reports outputs). The script maps them
onto the output it is bound to (map_to_output) and, with --donuk, undoes the output
transform itself (whether wlroots applies it for touch is checked by calibration in
arayuz-dene.py). Needs root for /dev/uinput: doas python3 dokun.py --cikis DSI-1.
Never writes anything but input events; the real touchscreen is left alone.
"""
import argparse
import json
import os
import subprocess
import sys
import time

import evdev
from evdev import UInput, ecodes as e

AD = "nicole-sanal-dokunmatik"
MAKS_X, MAKS_Y = 1079, 2399  # the panel's native size (FT3658S)
ADIM_HZ = 120  # move events per second while swiping


def sway(*args):
    env = dict(os.environ)
    if "SWAYSOCK" not in env:
        import glob
        env["SWAYSOCK"] = (glob.glob("/run/user/*/sway-ipc.*.sock") or [""])[0]
    return subprocess.run(["swaymsg", *args], capture_output=True, text=True, env=env)


def cikis_bilgisi(ad):
    for o in json.loads(sway("-t", "get_outputs", "-r").stdout or "[]"):
        if o["name"] == ad:
            return o
    sys.exit(f"çıkış yok: {ad}")


class Sanal:
    def __init__(self, cikis, donuk):
        self.cikis, self.donuk = cikis, donuk
        cap = {
            e.EV_KEY: [e.BTN_TOUCH],
            e.EV_ABS: [
                (e.ABS_X, evdev.AbsInfo(0, 0, MAKS_X, 0, 0, 0)),
                (e.ABS_Y, evdev.AbsInfo(0, 0, MAKS_Y, 0, 0, 0)),
                (e.ABS_MT_SLOT, evdev.AbsInfo(0, 0, 9, 0, 0, 0)),
                (e.ABS_MT_TRACKING_ID, evdev.AbsInfo(0, 0, 65535, 0, 0, 0)),
                (e.ABS_MT_POSITION_X, evdev.AbsInfo(0, 0, MAKS_X, 0, 0, 0)),
                (e.ABS_MT_POSITION_Y, evdev.AbsInfo(0, 0, MAKS_Y, 0, 0, 0)),
            ],
        }
        self.ui = UInput(cap, name=AD, input_props=[e.INPUT_PROP_DIRECT])
        self.iz = 1
        time.sleep(1.0)  # let libinput and sway pick it up
        r = sway("input", "type:touch", "map_to_output", cikis)
        # map every touch device: the real one is already mapped there too
        if r.returncode:
            print("uyarı: map_to_output:", r.stderr.strip(), file=sys.stderr)
        self.o = cikis_bilgisi(cikis)

    def ham(self, x, y):
        r = self.o["rect"]
        u, v = (x - r["x"]) / r["width"], (y - r["y"]) / r["height"]
        if self.donuk:
            t = self.o.get("transform", "normal")
            # sway maps a touch device's raw position through the output transform
            # (measured 8 Kasım: 270 -> layout (1-b, a)); undo it here
            u, v = {"normal": (u, v), "90": (1 - v, u), "180": (1 - u, 1 - v),
                    "270": (v, 1 - u)}.get(t, (u, v))
        u, v = min(max(u, 0), 1), min(max(v, 0), 1)
        return round(u * MAKS_X), round(v * MAKS_Y)

    def _yaz(self, olaylar):
        for tip, kod, deger in olaylar:
            self.ui.write(tip, kod, deger)
        self.ui.syn()

    def bas(self, x, y):
        hx, hy = self.ham(x, y)
        self.iz += 1
        self._yaz([(e.EV_ABS, e.ABS_MT_SLOT, 0), (e.EV_ABS, e.ABS_MT_TRACKING_ID, self.iz),
                   (e.EV_ABS, e.ABS_MT_POSITION_X, hx), (e.EV_ABS, e.ABS_MT_POSITION_Y, hy),
                   (e.EV_KEY, e.BTN_TOUCH, 1), (e.EV_ABS, e.ABS_X, hx), (e.EV_ABS, e.ABS_Y, hy)])

    def tasi(self, x, y):
        hx, hy = self.ham(x, y)
        self._yaz([(e.EV_ABS, e.ABS_MT_POSITION_X, hx), (e.EV_ABS, e.ABS_MT_POSITION_Y, hy),
                   (e.EV_ABS, e.ABS_X, hx), (e.EV_ABS, e.ABS_Y, hy)])

    def birak(self):
        self._yaz([(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1), (e.EV_KEY, e.BTN_TOUCH, 0)])

    def dokun(self, x, y, ms=60):
        self.bas(x, y)
        time.sleep(ms / 1000)
        self.birak()

    def kaydir(self, x1, y1, x2, y2, ms=250):
        n = max(2, int(ms / 1000 * ADIM_HZ))
        self.bas(x1, y1)
        for i in range(1, n + 1):
            time.sleep(ms / 1000 / n)
            k = i / n
            self.tasi(x1 + (x2 - x1) * k, y1 + (y2 - y1) * k)
        self.birak()


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--cikis", default="DSI-1")
    a.add_argument("--donuk", action="store_true", help="undo the output transform here")
    o = a.parse_args()
    s = Sanal(o.cikis, o.donuk)
    print("hazir", json.dumps({"transform": s.o.get("transform"), "rect": s.o["rect"]}), flush=True)
    for satir in sys.stdin:
        p = satir.split()
        if not p:
            continue
        try:
            k, n = p[0], [float(x) for x in p[1:]]
            if k == "dokun":
                s.dokun(*n[:2], *(n[2:3] or [60]))
            elif k == "kaydir":
                s.kaydir(*n[:4], *(n[4:5] or [250]))
            elif k == "bekle":
                time.sleep(n[0])
            elif k == "bitti":
                break
            else:
                raise ValueError(f"bilinmeyen komut {k}")
            print("ok", flush=True)
        except Exception as x:  # report and go on: the caller decides
            print("hata", x, flush=True)
    s.ui.close()


if __name__ == "__main__":
    main()
