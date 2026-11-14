#!/usr/bin/env python3
"""Fit a white-preserving 3x3 colour correction matrix from renk-olc.py measurements.

The soft ISP order is: black level -> AWB gains (grey world) -> CCM -> gamma, all on
linear values. So the CCM maps white-balanced linear camera RGB to linear sRGB.
Targets are the sRGB values the scene page showed (Chrome colour-manages them on the
Mac display). The screen-black measurement (display black + room reflection) is
subtracted from every patch. Rows of the matrix sum to 1 so white stays white.

Usage: renk-uydur.py out/renk-olcum-*.tsv
"""
import sys
import numpy as np


def srgb_lin(h):
    v = np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)])
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


M_XYZ = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
WP = M_XYZ @ np.ones(3)


def lab(rgb):
    x = (np.clip(rgb, 0, None) @ M_XYZ.T) / WP
    f = np.where(x > (6 / 29) ** 3, np.cbrt(x), x / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


def de(a, b):
    return np.linalg.norm(lab(a) - lab(b), axis=1)


def matris(p):
    m = np.array([[0, p[0], p[1]], [p[2], 0, p[3]], [p[4], p[5], 0]], float)
    m[np.diag_indices(3)] = 1 - m.sum(1)
    return m


def nelder_mead(f, x0, adim=0.1, n=4000):
    k = len(x0)
    s = [np.array(x0, float)] + [np.array(x0, float) + adim * np.eye(k)[i] for i in range(k)]
    v = [f(x) for x in s]
    for _ in range(n):
        o = np.argsort(v); s = [s[i] for i in o]; v = [v[i] for i in o]
        c = np.mean(s[:-1], 0)
        r = c + (c - s[-1]); fr = f(r)
        if fr < v[0]:
            e = c + 2 * (c - s[-1]); fe = f(e)
            s[-1], v[-1] = (e, fe) if fe < fr else (r, fr)
        elif fr < v[-2]:
            s[-1], v[-1] = r, fr
        else:
            cc = c + 0.5 * (s[-1] - c); fc = f(cc)
            if fc < v[-1]:
                s[-1], v[-1] = cc, fc
            else:
                s = [s[0]] + [s[0] + 0.5 * (x - s[0]) for x in s[1:]]
                v = [v[0]] + [f(x) for x in s[1:]]
        if np.std(v) < 1e-9:
            break
    return s[int(np.argmin(v))]


def main():
    satir = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if not l.startswith(("# ", "hex"))]
    hexler = [s[0] for s in satir]
    val = np.array([[float(x) for x in s[1:]] for s in satir])
    cam = np.stack([val[:, 0], (val[:, 1] + val[:, 2]) / 2, val[:, 3]], 1)
    clip = val[:, 5]

    siyah = cam[[h == "#000000" for h in hexler]]
    beyaz = cam[[h == "#ffffff" for h in hexler]]
    print("ekran siyahı (64 sensör siyahı dahil):", siyah.round(1).tolist())
    print("beyaz tekrarları:", beyaz.round(1).tolist())
    kayma = (beyaz.max(0) - beyaz.min(0)) / beyaz.mean(0)
    print("beyaz kayması %:", (100 * kayma).round(2).tolist())

    s0 = siyah.mean(0)
    sec = [i for i, h in enumerate(hexler) if h not in ("#000000", "#ffffff") and clip[i] == 0]
    w = beyaz.mean(0) - s0
    c = (cam[sec] - s0) / w            # white balanced, white = (1,1,1)
    t = np.array([srgb_lin(hexler[i]) for i in sec])
    wb = w[1] / w                       # AWB gains the ISP would use on a white scene
    print("beyaz dengesi kazançları R,G,B:", wb.round(3).tolist())

    gri = [k for k, i in enumerate(sec) if hexler[i][1:3] == hexler[i][3:5] == hexler[i][5:7]]
    print("gri doğrusallık (hedef, ölçülen G):")
    for k in gri:
        print(f"  {hexler[sec[k]]} {t[k, 1]:.4f} {c[k, 1]:.4f} oran {c[k, 1] / max(t[k, 1], 1e-6):.3f}")

    print("matrissiz ΔE ort/maks:", de(c, t).mean().round(2), de(c, t).max().round(2))
    # start: unconstrained least squares, then constrained ΔE fit
    m0, *_ = np.linalg.lstsq(c, t, rcond=None)
    m0 = m0.T
    p0 = [m0[0, 1], m0[0, 2], m0[1, 0], m0[1, 2], m0[2, 0], m0[2, 1]]
    p = nelder_mead(lambda p: de(c @ matris(p).T, t).mean(), p0)
    m = matris(p)
    d = de(c @ m.T, t)
    print("matrisli ΔE ort/maks:", d.mean().round(2), d.max().round(2))
    for k in np.argsort(-d)[:6]:
        print(f"  en kötü {hexler[sec[k]]}: ΔE {d[k]:.1f}")
    print("ccm:", np.array2string(m, precision=5, separator=", ", suppress_small=True))
    print("yaml:\n          ccm: [ " + ",\n                 ".join(", ".join(f"{x:8.5f}" for x in r) for r in m) + " ]")


if __name__ == "__main__":
    main()
