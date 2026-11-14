#!/usr/bin/env python3
"""List or extract logical partitions from an Android dynamic-partition `super` image.

Usage: lp-cikar.py SUPER.img                 -> list partitions (all metadata slots)
       lp-cikar.py SUPER.img NAME OUT.img    -> write NAME's extents to OUT.img
Read-only on SUPER.img. Format: system/core/fs_mgr/liblp (geometry at 4096, metadata
slots after the primary + backup geometry, then partition/extent tables).
"""
import struct
import sys

SECTOR = 512
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030


def read_metadata(f):
    f.seek(4096)
    magic, _size = struct.unpack("<II", f.read(8))
    if magic != GEOMETRY_MAGIC:
        sys.exit("geometry magic yok: super imajı değil")
    f.read(32)
    max_size, slot_count, _block = struct.unpack("<III", f.read(12))
    slots = []
    for slot in range(slot_count):
        base = 4096 + 2 * 4096 + slot * max_size
        f.seek(base)
        hdr = f.read(256)
        magic, _maj, _min, hdr_size = struct.unpack_from("<IHHI", hdr, 0)
        if magic != HEADER_MAGIC:
            continue
        # after header_checksum[32]: tables_size, tables_checksum[32], then 4 table descriptors
        descs = struct.unpack_from("<12I", hdr, 12 + 32 + 4 + 32)
        part_d, ext_d = descs[0:3], descs[3:6]
        f.seek(base + hdr_size + ext_d[0])
        exts = [struct.unpack_from("<QIQI", f.read(ext_d[2]))[:3] for _ in range(ext_d[1])]
        parts = {}
        f.seek(base + hdr_size + part_d[0])
        for _ in range(part_d[1]):
            e = f.read(part_d[2])
            name = e[:36].split(b"\0")[0].decode()
            _attr, first, num, _grp = struct.unpack_from("<IIII", e, 36)
            parts[name] = exts[first:first + num]
        slots.append(parts)
    return slots


def main():
    with open(sys.argv[1], "rb") as f:
        slots = read_metadata(f)
        if len(sys.argv) == 2:
            for i, parts in enumerate(slots):
                for name, exts in parts.items():
                    size = sum(e[0] for e in exts) * SECTOR
                    print(f"slot{i} {name} {size} {len(exts)} extent")
            return
        name, out = sys.argv[2], sys.argv[3]
        exts = next((p[name] for p in slots if p.get(name)), None)
        if not exts:
            sys.exit(f"{name}: bulunamadı ya da boş")
        with open(out, "wb") as o:
            for num, target_type, start in exts:
                if target_type == 0:  # linear
                    f.seek(start * SECTOR)
                    left = num * SECTOR
                    while left:
                        b = f.read(min(left, 1 << 20))
                        o.write(b)
                        left -= len(b)
                else:  # zero fill
                    o.write(b"\0" * (num * SECTOR))
        print(f"{name}: {sum(e[0] for e in exts) * SECTOR} bayt -> {out}")


main()
