#!/usr/bin/env python3
"""dpu-yazmac-oku.py: read-only dump of the display path's registers (lab only, root).

For the panel "shifted right" hunt (9 Kasım): DPU (mdp at 0xae01000) top, CTL0, DMA0,
INTF1, LM0/1, MERGE_3D0, PP0/1, the two DSC 1.2 encoders and DSI0's controller. One dump
in the bad state, one after a reboot; the diff names the register that stays wrong.

Reading a block that is not powered or clocked can hang the bus, so it refuses unless the
DPU is runtime-active and the panel's reset line is released (panel on). Prints
"<name> <address> <value>" lines. Usage: doas python3 dpu-yazmac-oku.py > dump.txt
"""
import mmap
import os
import struct
import sys

MDP = 0xAE01000
BLOKLAR = [  # (name, absolute base, length) from dpu_7_0_sm8350.h / dpu_hw_catalog.c
    ("top", MDP + 0x0, 0x494), ("ctl0", MDP + 0x15000, 0x1E8), ("dma0", MDP + 0x24000, 0x1F8),
    ("intf1", MDP + 0x35000, 0x2C4), ("lm0", MDP + 0x44000, 0x320), ("lm1", MDP + 0x45000, 0x320),
    ("merge3d0", MDP + 0x4E000, 0x8), ("pp0", MDP + 0x69000, 0x100), ("pp1", MDP + 0x6A000, 0x100),
    ("dsc_ortak", MDP + 0x80000, 0x4), ("dsc0_enc", MDP + 0x80100, 0x9C),
    ("dsc1_enc", MDP + 0x80200, 0x9C), ("dsc0_ctl", MDP + 0x80F00, 0x10),
    ("dsc1_ctl", MDP + 0x80F80, 0x10), ("dsi0", 0xAE94000, 0x400),
]
DPU_PM = "/sys/devices/platform/soc@0/ae00000.display-subsystem/ae01000.display-controller/power/runtime_status"


def guvenli():
    try:
        if open(DPU_PM).read().strip() != "active":
            return "DPU uyuyor (runtime_status != active): ekran kapalı"
    except OSError as e:
        return f"DPU güç durumu okunamadı: {e}"
    try:
        for satir in open("/sys/kernel/debug/gpio"):
            p = satir.split()
            if p and p[0] == "gpio24":
                return None if "high" in satir else "panel reset hattı aşağıda: panel kapalı"
    except OSError as e:
        return f"gpio okunamadı: {e}"
    return "gpio24 bulunamadı"


def main():
    neden = guvenli()
    if neden:
        print("OKUNMADI:", neden, file=sys.stderr)
        return 2
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    try:
        for ad, taban, boy in BLOKLAR:
            sayfa = taban & ~0xFFF
            fark = taban - sayfa
            m = mmap.mmap(fd, (fark + boy + 0xFFF) & ~0xFFF, mmap.MAP_SHARED, mmap.PROT_READ,
                          offset=sayfa)
            try:
                for o in range(0, boy, 4):
                    v = struct.unpack_from("<I", m, fark + o)[0]
                    print(f"{ad} {taban + o:#010x} {v:#010x}")
            finally:
                m.close()
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
