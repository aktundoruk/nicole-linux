#!/usr/bin/env python3
"""Minimal telnet client for the nicole mini initramfs: run commands, print output."""
import socket, sys, time
IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
def run(cmds, host="172.16.42.1", wait=4.0):
    s = socket.create_connection((host, 23), timeout=5)
    s.settimeout(0.5)
    out = bytearray()
    def pump(t):
        end = time.time() + t
        while time.time() < end:
            try:
                d = s.recv(65536)
            except socket.timeout:
                continue
            if not d:
                return
            i = 0
            while i < len(d):
                b = d[i]
                if b == IAC and i + 1 < len(d):
                    c = d[i + 1]
                    if c in (DO, DONT, WILL, WONT) and i + 2 < len(d):
                        s.send(bytes([IAC, WONT if c in (DO, DONT) else DONT, d[i + 2]]))
                        i += 3; continue
                    if c == SB:
                        j = d.find(bytes([IAC, SE]), i)
                        i = j + 2 if j >= 0 else len(d); continue
                    i += 2; continue
                out.append(b); i += 1
    pump(1.0)
    for c in cmds:
        s.send(c.encode() + b"\n")
        pump(wait)
    s.close()
    return out.decode(errors="replace")
if __name__ == "__main__":
    w = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
    print(run(sys.stdin.read().splitlines(), wait=w))
