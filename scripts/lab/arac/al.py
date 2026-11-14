#!/usr/bin/env python3
"""Accept one connection on PORT, write everything received to OUT until EOF.

Usage: al.py PORT OUT [--zaman-asimi SN]
Prints "bytes=N sha256=H" to stderr (hash of exactly what was written), so the
sender's `sha256sum /dev/X` can be compared against it. Twin of gonder.py.
Listens on 172.16.42.2 (the Mac's address on the phone's USB network) only.
"""
import hashlib
import os
import socket
import sys
import time

port, out = int(sys.argv[1]), sys.argv[2]
zaman_asimi = 120
if "--zaman-asimi" in sys.argv:
    zaman_asimi = int(sys.argv[sys.argv.index("--zaman-asimi") + 1])
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((os.environ.get("AL_ADRES", "172.16.42.2"), port))
srv.listen(1)
srv.settimeout(zaman_asimi)
c, _ = srv.accept()
c.settimeout(zaman_asimi)
h = hashlib.sha256()
n = 0
t0 = time.time()
with open(out, "wb") as f:
    while True:
        b = c.recv(1 << 20)
        if not b:
            break
        f.write(b)
        h.update(b)
        n += len(b)
c.close()
srv.close()
dt = max(time.time() - t0, 0.001)
print(f"bytes={n} sha256={h.hexdigest()} ({dt:.0f} s, {n / dt / 1e6:.1f} MB/s)", file=sys.stderr)
