#!/usr/bin/env python3
"""Puts back the protective MBR and backup GPT header of the rehearsal's inner table.

The primary header and entries survived (5 Nov: only blocks 0 and N-1 were zeroed), so this
writes a protective MBR into block 0, then rebuilds the backup from the primary. Runs on the
phone as root against rawdump only, with the loop's sector size the table was written in.
"""
import os
import struct
import sys
import zlib

DEV = os.path.realpath("/dev/disk/by-partlabel/rawdump")
B = 4096
fd = os.open(DEV, os.O_RDWR | os.O_SYNC)
boy = os.lseek(fd, 0, os.SEEK_END) // B
bas = os.pread(fd, B, B)
if bas[:8] != b"EFI PART":
    sys.exit("birincil başlık yok, onarılmadı")
hb = struct.unpack_from("<I", bas, 12)[0]
ad = bas[:hb]
crc = struct.unpack_from("<I", ad, 16)[0]
if zlib.crc32(ad[:16] + b"\0" * 4 + ad[20:]) != crc:
    sys.exit("birincil başlık CRC bozuk, onarılmadı")
my, alt = struct.unpack_from("<QQ", ad, 24)
ent_lba, n, es = struct.unpack_from("<QII", ad, 72)
if my != 1 or alt != boy - 1:
    sys.exit(f"beklenmeyen başlık: my={my} alt={alt} boy={boy}")
tablo = os.pread(fd, n * es, ent_lba * B)
if zlib.crc32(tablo) != struct.unpack_from("<I", ad, 88)[0]:
    sys.exit("girdi CRC bozuk, onarılmadı")

mbr = bytearray(B)
mbr[446:462] = bytes([0, 0, 2, 0, 0xEE, 0xFF, 0xFF, 0xFF]) + struct.pack("<II", 1, min(boy - 1, 0xFFFFFFFF))
mbr[510:512] = b"\x55\xaa"

ent_yedek = boy - 1 - (n * es + B - 1) // B
y = bytearray(ad)
struct.pack_into("<QQ", y, 24, alt, my)
struct.pack_into("<Q", y, 72, ent_yedek)
struct.pack_into("<I", y, 16, 0)
struct.pack_into("<I", y, 16, zlib.crc32(bytes(y)))

os.pwrite(fd, bytes(mbr), 0)
os.pwrite(fd, tablo, ent_yedek * B)
os.pwrite(fd, bytes(y) + b"\0" * (B - hb), (boy - 1) * B)
os.fsync(fd)
print(f"onarıldı: {DEV}, {boy} blok, yedek girdiler {ent_yedek}")
