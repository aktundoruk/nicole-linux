#!/usr/bin/env python3
"""Read-only: slot attribute bits (48-55) of every _a/_b entry in each GPT given (devices or images)."""
import struct, sys, zlib
def oku(yol, bs=4096):
    with open(yol, "rb") as f:
        f.seek(bs); h = f.read(bs)
        if h[:8] != b"EFI PART": return None
        glba, = struct.unpack_from("<Q", h, 72); n, boy = struct.unpack_from("<II", h, 80)
        f.seek(glba * bs); g = f.read(n * boy)
    out = {}
    for i in range(n):
        e = g[i*boy:(i+1)*boy]
        if e[:16] == b"\0"*16: continue
        ad = e[56:128].decode("utf-16-le").rstrip("\0")
        if ad.endswith(("_a", "_b")):
            out[ad] = (struct.unpack_from("<Q", e, 48)[0] >> 48) & 0xff
    return out
for yol in sys.argv[1:]:
    d = oku(yol)
    if d is None: print(yol, "GPT yok"); continue
    akt = {"a": [], "b": []}
    for ad, b in d.items():
        if (b >> 2) & 1: akt[ad[-1]].append(ad[:-2])
    ozel = {k: f"0x{v:02x}" for k, v in d.items() if k.startswith("boot_")}
    print(f"{yol}: {len(d)} slot girdisi; etkin biti _a'da {len(akt['a'])}, _b'de {len(akt['b'])}; boot: {ozel}")
    print("   _a etkin:", " ".join(sorted(akt["a"]))[:300])
    print("   _b etkin:", " ".join(sorted(akt["b"]))[:300])
