#!/usr/bin/env python3
"""Front camera, one raw frame, without media-ctl/v4l2-ctl (6 Kasım, kernel r22).

Builds hi556 -> msm_csiphy5 -> msm_csidN -> msm_vfeM_rdiK -> msm_vfeM_videoK with raw media
and V4L2 ioctls, sets the same bus format on every pad, captures a few MMAP frames and writes
the last one to OUT (raw packed MIPI10 bytes). Prints sequence numbers, sizes, timestamps.
Nothing else is touched: links set here can be reset with --sifirla.

Usage: doas python3 -u kamera-yakala.py [--adim N] [--csid 0] [--vfe 0] [--rdi 0] [--kare 8]
                                     [--boyut 1296x972] [--cikti /tmp/kare.raw] [--sifirla]
"""
import argparse
import ctypes
import fcntl
import mmap
import os
import select
import struct
import sys
import time


def ioc(d, t, nr, size):
    return (d << 30) | (size << 16) | (ord(t) << 8) | nr


IOWR, IOW = 3, 1
MEDIA_IOC_ENUM_ENTITIES = ioc(IOWR, "|", 1, 256)
MEDIA_IOC_ENUM_LINKS = ioc(IOWR, "|", 2, 40)
MEDIA_IOC_SETUP_LINK = ioc(IOWR, "|", 3, 52)
SUBDEV_G_FMT = ioc(IOWR, "V", 4, 88)
SUBDEV_S_FMT = ioc(IOWR, "V", 5, 88)
VIDIOC_S_FMT = ioc(IOWR, "V", 5, 208)
VIDIOC_REQBUFS = ioc(IOWR, "V", 8, 20)
VIDIOC_QUERYBUF = ioc(IOWR, "V", 9, 88)
VIDIOC_QBUF = ioc(IOWR, "V", 15, 88)
VIDIOC_DQBUF = ioc(IOWR, "V", 17, 88)
VIDIOC_STREAMON = ioc(IOW, "V", 18, 4)
VIDIOC_STREAMOFF = ioc(IOW, "V", 19, 4)
VIDIOC_S_CTRL = ioc(IOWR, "V", 28, 8)
CID_TEST_PATTERN = 0x009F0903
CIDLER = {"exposure": 0x00980911, "gain": 0x009E0903}
MPLANE, MMAP = 9, 1
LINK_ENABLED, LINK_IMMUTABLE = 1, 2
PAD_SINK, PAD_SOURCE = 1, 2
# bus code -> (V4L2 packed pixel format, bits)
FORMATLAR = {0x3007: (b"pBAA", 10), 0x300A: (b"pgAA", 10), 0x300E: (b"pGAA", 10), 0x300F: (b"pRAA", 10)}


def varliklar(m):
    out, i = {}, 0
    while True:
        b = bytearray(256)
        struct.pack_into("I", b, 0, i | (1 << 31))
        try:
            fcntl.ioctl(m, MEDIA_IOC_ENUM_ENTITIES, b)
        except OSError:
            return out
        eid = struct.unpack_from("I", b, 0)[0]
        ad = bytes(b[4:36]).split(b"\0")[0].decode()
        pads, links = struct.unpack_from("HH", b, 52)
        out[ad] = (eid, pads, links)
        i = eid


def baglar(m, eid, pads, links):
    pb = (ctypes.c_ubyte * (20 * max(pads, 1)))()
    lb = (ctypes.c_ubyte * (52 * max(links, 1)))()
    req = struct.pack("IIQQ16x", eid, 0, ctypes.addressof(pb), ctypes.addressof(lb))
    fcntl.ioctl(m, MEDIA_IOC_ENUM_LINKS, bytearray(req))
    raw = bytes(lb)
    out = []
    for k in range(links):
        s_ent, s_idx, _, s_fl, d_ent, d_idx, _, d_fl, fl = struct.unpack_from("IHHI8xIHHI8xI", raw, 52 * k)
        out.append((s_ent, s_idx, d_ent, d_idx, fl))
    return out


def bag_kur(m, s_ent, s_idx, d_ent, d_idx, ac):
    b = bytearray(52)
    struct.pack_into("IHHI8xIHHI8xI", b, 0, s_ent, s_idx, 0, PAD_SOURCE, d_ent, d_idx, 0, PAD_SINK,
                     LINK_ENABLED if ac else 0)
    fcntl.ioctl(m, MEDIA_IOC_SETUP_LINK, b)


def alt_dugum(ad):
    for d in sorted(os.listdir("/sys/class/video4linux")):
        if open(f"/sys/class/video4linux/{d}/name").read().strip() == ad:
            return "/dev/" + d
    sys.exit(f"{ad} düğümü yok")


def fmt_al(fd, pad):
    b = bytearray(88)
    struct.pack_into("II", b, 0, 1, pad)
    fcntl.ioctl(fd, SUBDEV_G_FMT, b)
    return struct.unpack_from("IIIII", b, 8)


def fmt_kur(fd, pad, w, h, code):
    b = bytearray(88)
    struct.pack_into("IIIIIII", b, 0, 1, pad, w, h, code, 1, 0)  # field NONE
    fcntl.ioctl(fd, SUBDEV_S_FMT, b)
    return struct.unpack_from("IIIII", b, 8)


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--csid", type=int, default=0)
    a.add_argument("--vfe", type=int, default=0)
    a.add_argument("--rdi", type=int, default=0)
    a.add_argument("--kare", type=int, default=8)
    a.add_argument("--boyut")
    a.add_argument("--cikti", default="/tmp/kare.raw")
    a.add_argument("--sifirla", action="store_true")
    a.add_argument("--tpg", type=int, default=0, help="CSID test pattern (1..), sensor and CSIPHY left out")
    a.add_argument("--nabiz", action="store_true", help="print a timestamp every 100 ms from a thread")
    a.add_argument("--degistir", action="append", default=[],
                   help="KARE:ctrl=değer, ör. 10:exposure=200 (sensör kontrolü, gecikme ölçümü)")
    a.add_argument("--adim", type=int, default=9, help="1 bağlar, 2 formatlar, 3 video aç, 4 tampon, 5 akış")
    o = a.parse_args()

    def adim(n, ne):
        print(f"ADIM {n}: {ne}", flush=True)
        if n > o.adim:
            print("durdu (--adim)", flush=True)
            sys.exit(0)

    m = os.open("/dev/media0", os.O_RDWR)
    v = varliklar(m)
    sensor = next(k for k in v if k.startswith("hi556"))
    phy, csid = "msm_csiphy5", f"msm_csid{o.csid}"
    rdi, vid = f"msm_vfe{o.vfe}_rdi{o.rdi}", f"msm_vfe{o.vfe}_video{o.rdi}"
    for ad in (phy, csid, rdi):
        e, p, l = v[ad]
        for s_ent, s_idx, d_ent, d_idx, fl in baglar(m, e, p, l):
            if s_ent == e and fl & LINK_ENABLED and not fl & LINK_IMMUTABLE:
                bag_kur(m, s_ent, s_idx, d_ent, d_idx, False)
    if o.sifirla:
        print("bağlar kapatıldı")
        return
    if o.nabiz:
        import threading

        def nabiz():
            while True:
                print(f"nabız {time.monotonic():.2f}", flush=True)
                time.sleep(0.1)
        threading.Thread(target=nabiz, daemon=True).start()
    adim(1, "bağlar")
    cfd = os.open(alt_dugum(csid), os.O_RDWR)  # CSID refuses the CSIPHY link while its pattern is on
    fcntl.ioctl(cfd, VIDIOC_S_CTRL, bytearray(struct.pack("Ii", CID_TEST_PATTERN, o.tpg)))
    os.close(cfd)
    if not o.tpg:
        bag_kur(m, v[phy][0], 1, v[csid][0], 0, True)
    bag_kur(m, v[csid][0], 1, v[rdi][0], 0, True)
    sb = baglar(m, *v[sensor])
    print("sensör bağı:", [(s, d, fl) for s, _, d, _, fl in sb], "phy", v[phy][0])

    adim(2, "formatlar")
    sfd = os.open(alt_dugum(sensor), os.O_RDWR)
    w, h, code, _, _ = fmt_al(sfd, 0)
    if o.boyut:
        w, h = map(int, o.boyut.split("x"))
        w, h, code, _, _ = fmt_kur(sfd, 0, w, h, code)
    print(f"sensör {w}x{h} kod 0x{code:04x}")
    for ad in ((csid, rdi) if o.tpg else (phy, csid, rdi)):
        fd = os.open(alt_dugum(ad), os.O_RDWR)
        if ad == csid:
            fcntl.ioctl(fd, VIDIOC_S_CTRL, bytearray(struct.pack("Ii", CID_TEST_PATTERN, o.tpg)))
            print(f"{csid} test deseni {o.tpg}", flush=True)
        r = fmt_kur(fd, 0, w, h, code)
        k = fmt_al(fd, 1)
        print(f"{ad}: giriş {r[0]}x{r[1]} 0x{r[2]:04x}, çıkış {k[0]}x{k[1]} 0x{k[2]:04x}")
        os.close(fd)

    pix, bits = FORMATLAR[code]
    adim(3, "video düğümü açılıyor (boru hattı güç alır)")
    vfd = os.open(alt_dugum(vid), os.O_RDWR)
    print("açıldı", flush=True)
    f = bytearray(208)
    struct.pack_into("I", f, 0, MPLANE)
    struct.pack_into("IIIII", f, 8, w, h, struct.unpack("I", pix)[0], 1, 0)
    struct.pack_into("B", f, 8 + 20 + 160, 1)
    fcntl.ioctl(vfd, VIDIOC_S_FMT, f)
    fw, fh = struct.unpack_from("II", f, 8)
    size, bpl = struct.unpack_from("II", f, 28)
    print(f"video {fw}x{fh} {pix.decode()} satır {bpl} kare {size}")

    adim(4, "tamponlar")
    rb = bytearray(struct.pack("IIII4x", 4, MPLANE, MMAP, 0))
    fcntl.ioctl(vfd, VIDIOC_REQBUFS, rb)
    n = struct.unpack_from("I", rb, 0)[0]
    planes = [(ctypes.c_ubyte * 64)() for _ in range(n)]

    def buf(i):
        b = bytearray(88)
        struct.pack_into("II", b, 0, i, MPLANE)
        struct.pack_into("I", b, 60, MMAP)
        struct.pack_into("Q", b, 64, ctypes.addressof(planes[i]))
        struct.pack_into("I", b, 72, 1)
        return b

    maps = []
    for i in range(n):
        b = buf(i)
        fcntl.ioctl(vfd, VIDIOC_QUERYBUF, b)
        ln, off = struct.unpack_from("II", bytes(planes[i]), 4)
        maps.append(mmap.mmap(vfd, ln, mmap.MAP_SHARED, mmap.PROT_READ, offset=off))
        fcntl.ioctl(vfd, VIDIOC_QBUF, buf(i))
    t = struct.pack("I", MPLANE)
    adim(5, "STREAMON")
    fcntl.ioctl(vfd, VIDIOC_STREAMON, t)
    print(f"akış açık, {n} tampon")
    son = None
    degis = {}
    for d in o.degistir:
        k, kv = d.split(":")
        ad, deger = kv.split("=")
        degis.setdefault(int(k), []).append((CIDLER[ad], int(deger), kv))
    try:
        for sira in range(o.kare):
            for cid, deger, kv in degis.get(sira, []):
                fcntl.ioctl(sfd, VIDIOC_S_CTRL, bytearray(struct.pack("Ii", cid, deger)))
                print(f"-> {sira}. karede {kv} yazıldı", flush=True)
            r, _, _ = select.select([vfd], [], [], 3)
            if not r:
                print("ZAMAN AŞIMI: 3 sn kare gelmedi", flush=True)
                continue
            b = buf(0)
            fcntl.ioctl(vfd, VIDIOC_DQBUF, b)
            i, _, _, flags = struct.unpack_from("IIII", b, 0)
            sec, usec = struct.unpack_from("qq", b, 24)
            seq = struct.unpack_from("I", b, 56)[0]
            used = struct.unpack_from("I", bytes(planes[i]), 0)[0]
            veri = maps[i][:used]
            ornek = veri[::4097]  # roughly the MSBs of scattered pixels: a brightness figure, not an image
            ort = sum(ornek) / max(len(ornek), 1)
            print(f"kare seq {seq} tampon {i} {used} bayt, bayrak 0x{flags:x}, zaman {sec}.{usec:06d}, örnek ort {ort:.1f}")
            son = veri
            fcntl.ioctl(vfd, VIDIOC_QBUF, buf(i))
    finally:
        fcntl.ioctl(vfd, VIDIOC_STREAMOFF, t)
    if son:
        open(o.cikti, "wb").write(son)
        print(f"yazıldı {o.cikti} ({w}x{h}, satır {bpl})")


if __name__ == "__main__":
    main()
