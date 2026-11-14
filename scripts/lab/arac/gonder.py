#!/usr/bin/env python3
"""Stream stdin to HOST:PORT, then half-close and wait for the peer to close.

Usage: zstd -dc img.zst | gonder.py 172.16.42.1 5555
Prints "bytes=N sha256=H" to stderr (hash of exactly what was sent), so the
receiver's `head -c N /dev/X | sha256sum` can be compared against it.

Why not macOS nc: it does not reliably shutdown(SHUT_WR) on stdin EOF, so a
busybox `nc -l | dd` receiver never sees EOF and both ends hang.
"""
import hashlib
import socket
import sys
import time

host, port = sys.argv[1], int(sys.argv[2])
h = hashlib.sha256()
n = 0
t0 = time.time()
s = socket.create_connection((host, port), timeout=10)
s.settimeout(120)
src = sys.stdin.buffer
while True:
    b = src.read(1 << 20)
    if not b:
        break
    s.sendall(b)
    h.update(b)
    n += len(b)
    if n % (256 << 20) < (1 << 20):
        dt = time.time() - t0
        print(f"  {n >> 20} MiB, {n / dt / 1e6:.1f} MB/s", file=sys.stderr)
s.shutdown(socket.SHUT_WR)
while s.recv(4096):
    pass
s.close()
dt = time.time() - t0
print(f"bytes={n} sha256={h.hexdigest()} ({dt:.0f} s, {n / dt / 1e6:.1f} MB/s)", file=sys.stderr)
