#!/usr/bin/env python3
"""MIPI RAW10 (packed, GRBG) frame from kamera-yakala.py -> PNG, 2x2 binned, rough black level,
grey-world white balance, gamma 2.2. Usage: kamera-raw-png.py IN.raw OUT.png [W H STRIDE]"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
W, H, S = (int(x) for x in sys.argv[3:6]) if len(sys.argv) > 5 else (2592, 1944, 3248)
raw = np.fromfile(src, np.uint8)[:S * H].reshape(H, S)[:, :W * 5 // 4]
b = raw.reshape(H, -1, 5).astype(np.uint16)
px = np.empty((H, b.shape[1], 4), np.uint16)
for i in range(4):
    px[:, :, i] = (b[:, :, i] << 2) | ((b[:, :, 4] >> (2 * i)) & 3)
img = px.reshape(H, W).astype(np.float32)
print(f"10 bit: min {img.min():.0f} max {img.max():.0f} ort {img.mean():.1f} p99 {np.percentile(img, 99):.0f}")
g1, r, bl, g2 = img[0::2, 0::2], img[0::2, 1::2], img[1::2, 0::2], img[1::2, 1::2]
rgb = np.clip(np.stack([r, (g1 + g2) / 2, bl], -1) - 64, 0, None)
for c in range(3):
    rgb[..., c] *= rgb[..., 1].mean() / max(rgb[..., c].mean(), 1e-3)
rgb = rgb / max(np.percentile(rgb, 99.5), 1)
Image.fromarray((np.clip(rgb, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)).save(dst)
