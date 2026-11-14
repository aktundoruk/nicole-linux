#!/usr/bin/env python3
"""tlmm-pull.py GPIO [none|down|keeper|up]: read (and set) the pull bits of a TLMM GPIO's
config register on SM8350 (TLMM 0x0f100000, 0x1000 per GPIO, bits 1:0). Lab only, root."""
import mmap, os, struct, sys
TLMM, ADIM = 0x0F100000, 0x1000
ADLAR = ["none", "down", "keeper", "up"]
g = int(sys.argv[1])
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, ADIM, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=TLMM + g * ADIM)
v = struct.unpack("<I", m[0:4])[0]
print(f"gpio{g} cfg 0x{v:08x} pull={ADLAR[v & 3]} func={(v >> 2) & 0xf} drv={(v >> 6) & 7}")
if len(sys.argv) > 2:
    yeni = (v & ~3) | ADLAR.index(sys.argv[2])
    m[0:4] = struct.pack("<I", yeni)
    v = struct.unpack("<I", m[0:4])[0]
    print(f"gpio{g} cfg 0x{v:08x} pull={ADLAR[v & 3]} (yazıldı)")
