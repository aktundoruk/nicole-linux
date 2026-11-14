#!/usr/bin/env python3
"""Colour calibration measurement: show solid colours on the Mac screen (scene page),
capture a raw Hi-556 frame on the phone at fixed exposure, record the centre means.

Needs: scene server serving scripts/lab/kamera-sahne (sahne.txt), phone front camera
facing the screen so the centre of the view sees only the screen, /tmp/kamera-yakala.py
and /tmp/bayer-ort.py on the phone. Only channel means leave the phone.

Output: out/renk-olcum-<time>.tsv  (hex, R, Gr, Gb, B, max, clipped)
"""
import os, subprocess, sys, time

KOK = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SAHNE = os.path.join(KOK, "scripts/lab/kamera-sahne/sahne.txt")
RW = os.environ.get("RW", "rw")
W, H, BPL = 1296, 972, 1632

# 24 ColorChecker-like sRGB values (same as the scene page chart)
KART = ["#735244", "#c29682", "#627a9d", "#576c43", "#8580b1", "#67bdaa",
        "#d67e2c", "#505ba6", "#c15a63", "#5e3c6c", "#9dbc40", "#e0a32e",
        "#383d96", "#469449", "#af363c", "#e7c71f", "#bb5695", "#0885a1",
        "#f3f3f2", "#c8c8c8", "#a0a0a0", "#7a7a79", "#555555", "#343434"]
ANA = ["#ff0000", "#00ff00", "#0000ff", "#00ffff", "#ff00ff", "#ffff00",
       "#800000", "#008000", "#000080", "#ff8000", "#80ff00", "#0080ff",
       "#ff0080", "#8000ff", "#00ff80"]
GRI = ["#202020", "#404040", "#606060", "#808080", "#b0b0b0", "#e0e0e0"]


def sahne(renk):
    with open(SAHNE + ".yeni", "w") as f:
        f.write(renk + "\n")
    os.replace(SAHNE + ".yeni", SAHNE)


def olc(renk, bekle=0.9):
    sahne(renk)
    time.sleep(bekle)
    out = subprocess.run(
        [RW, f"cd /tmp && doas python3 kamera-yakala.py --kare 6 --boyut {W}x{H} --cikti /tmp/r.raw >/dev/null 2>&1"
             f" && python3 bayer-ort.py /tmp/r.raw {W} {H} {BPL}"],
        capture_output=True, text=True, timeout=60).stdout.split()
    return [float(x) for x in out[-6:]]


def pozlama(exp, gain=16):
    subprocess.run([RW, f"doas v4l2-ctl -d /dev/v4l-subdev28 --set-ctrl exposure={exp},analogue_gain={gain}"],
                   check=True, capture_output=True)


def main():
    # Pick exposure so that white peaks around 800 of 1023 (black is 64).
    exp = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    if not exp:
        exp = 300
        for _ in range(8):
            pozlama(exp)
            r, gr, gb, b, mx, clip = olc("#ffffff")
            tepe = max(r, gr, gb, b) - 64
            print(f"pozlama {exp}: beyaz tepe {tepe:.0f}, kırpık {clip}", flush=True)
            if 600 <= tepe + 64 <= 850 and clip == 0:
                break
            exp = max(6, min(2066, int(exp * 700 / max(tepe, 1))))
    pozlama(exp)
    sira = ["#000000", "#ffffff"] + KART + ["#000000", "#ffffff"] + ANA + GRI + ["#000000", "#ffffff"]
    yol = os.path.join(KOK, "out", time.strftime("renk-olcum-%Y%m%d-%H%M%S.tsv"))
    with open(yol, "w") as f:
        f.write(f"# exposure {exp} gain 16 size {W}x{H}\nhex\tR\tGr\tGb\tB\tmax\tclip\n")
        for renk in sira:
            v = olc(renk)
            f.write(renk + "\t" + "\t".join(f"{x:g}" for x in v) + "\n")
            f.flush()
            print(renk, v, flush=True)
    sahne("#000000")
    print("yazıldı", yol)


if __name__ == "__main__":
    main()
