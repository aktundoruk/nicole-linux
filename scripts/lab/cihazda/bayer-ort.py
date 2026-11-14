#!/usr/bin/env python3
"""Mean of each Bayer channel in the centre of a RAW10 CSI-2 packed GRBG frame.

Usage: bayer-ort.py FILE W H BPL [ROI_FRACTION]
Prints: R Gr Gb B max_raw clipped_fraction (10-bit values, black not subtracted).
Used for colour calibration: only numbers leave the phone, never the image.
"""
import sys
import numpy as np

f, w, h, bpl = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
frac = float(sys.argv[5]) if len(sys.argv) > 5 else 0.3

d = np.fromfile(f, dtype=np.uint8)[: bpl * h].reshape(h, bpl)
p = d[:, : w * 5 // 4].reshape(h, w // 4, 5).astype(np.uint16)
img = np.empty((h, w), dtype=np.uint16)
for i in range(4):
    img[:, i::4] = (p[:, :, i] << 2) | ((p[:, :, 4] >> (2 * i)) & 3)

rh, rw = int(h * frac) // 2 * 2, int(w * frac) // 2 * 2
y0, x0 = (h - rh) // 4 * 2, (w - rw) // 4 * 2
r = img[y0 : y0 + rh, x0 : x0 + rw].astype(np.float64)
gr, rr, bb, gb = r[0::2, 0::2], r[0::2, 1::2], r[1::2, 0::2], r[1::2, 1::2]
mx = r.max()
print(f"{rr.mean():.2f} {gr.mean():.2f} {gb.mean():.2f} {bb.mean():.2f} {mx:.0f} {(r >= 1020).mean():.4f}")
