#!/usr/bin/env python3
"""Inspect Android dtbo images (dt_table format) for the nicole boot plan.

Subcommands
  bilgi     DTBO                 header, entries, qcom,msm-id / qcom,board-id of each overlay
  ayikla    DTBO OUTDIR          write every entry as OUTDIR/entry-NN.dtbo
  etiketler DTBO BASE.DTB [-e N] labels the overlay(s) reference (__fixups__) vs. labels the
                                 base DTB exports (__symbols__): "missing" -> ABL overlay apply
                                 fails; "shared" -> overlay would modify our mainline nodes
  bos       OUT.IMG [--msm-id 439,0x20001|yok] [--board-id 0x1001f,0x2]
                                 build a dtbo with ONE empty overlay carrying only the IDs
                                 (alternative to the 2-zero-byte emptydtbo, docs/boot-plani.md §3.4)
  parca     DTBO OUT.IMG KEEP    copy entry 0 keeping only fragment@N for N in KEEP ("0-317,400");
                                 __fixups__/__local_fixups__/__symbols__ are pruned to match.
                                 For bisecting which fragments of a working dtbo ABL needs

Needs: fdtget, dtc (device-tree-compiler); parca also needs pylibfdt (python3-libfdt). Read-only on its inputs; never talks to a device.
"""
import argparse
import os
import struct
import subprocess
import sys
import tempfile

MAGIC = 0xD7B7AB1E
HDR = struct.Struct(">8I")    # magic total_size header_size dt_entry_size count entries_off page_size version
ENT = struct.Struct(">8I")    # dt_size dt_offset id rev custom[4]


def die(msg):
    print(f"[x] {msg}", file=sys.stderr)
    sys.exit(1)


def read_table(path):
    data = open(path, "rb").read()
    if len(data) < HDR.size:
        die(f"{path}: too small ({len(data)} bytes) - empty/zeroed dtbo?")
    magic, total, hsize, esize, count, eoff, page, ver = HDR.unpack_from(data, 0)
    if magic != MAGIC:
        die(f"{path}: bad magic 0x{magic:08x} (not a dt_table image; zeroed partition?)")
    entries = []
    for i in range(count):
        dt_size, dt_off, eid, rev, c0, c1, c2, c3 = ENT.unpack_from(data, eoff + i * esize)
        entries.append(dict(index=i, size=dt_size, offset=dt_off, id=eid, rev=rev,
                            custom=(c0, c1, c2, c3), blob=data[dt_off:dt_off + dt_size]))
    hdr = dict(total=total, header_size=hsize, entry_size=esize, count=count,
               entries_offset=eoff, page_size=page, version=ver)
    return hdr, entries


def fdt(args):
    r = subprocess.run(["fdtget"] + args, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def with_blob(blob, fn):
    with tempfile.NamedTemporaryFile(suffix=".dtbo", delete=False) as t:
        t.write(blob)
        name = t.name
    try:
        return fn(name)
    finally:
        os.unlink(name)


def props(path, node):
    out = fdt(["-p", path, node])
    return set(out.split()) if out else set()


def cmd_bilgi(a):
    hdr, ents = read_table(a.dtbo)
    print(f"{a.dtbo}: {hdr}")
    for e in ents:
        def show(p):
            msm = fdt(["-t", "x", p, "/", "qcom,msm-id"])
            board = fdt(["-t", "x", p, "/", "qcom,board-id"])
            model = fdt([p, "/", "model"])
            nfix = len(props(p, "/__fixups__"))
            print(f"  [{e['index']:02d}] size={e['size']} id=0x{e['id']:x} rev=0x{e['rev']:x} "
                  f"custom={e['custom']}\n       model={model!r} msm-id=<{msm}> board-id=<{board}> "
                  f"fixup-labels={nfix}")
        with_blob(e["blob"], show)


def cmd_ayikla(a):
    _, ents = read_table(a.dtbo)
    os.makedirs(a.outdir, exist_ok=True)
    for e in ents:
        p = os.path.join(a.outdir, f"entry-{e['index']:02d}.dtbo")
        open(p, "wb").write(e["blob"])
        print(p)


def cmd_etiketler(a):
    _, ents = read_table(a.dtbo)
    if a.e is not None:
        ents = [e for e in ents if e["index"] == a.e]
        if not ents:
            die(f"no entry {a.e}")
    need = set()
    for e in ents:
        need |= with_blob(e["blob"], lambda p: props(p, "/__fixups__"))
    have = props(a.base, "/__symbols__")
    if not have:
        print("[!] base DTB has no __symbols__ (build it with dtc -@ / DTC_FLAGS_<name> := -@)")
    missing = sorted(need - have)
    shared = sorted(need & have)
    print(f"overlay references {len(need)} labels; base exports {len(have)}")
    print(f"\nMISSING in base ({len(missing)}) -> overlay apply would fail on these:")
    for l in missing:
        print(f"  {l}")
    print(f"\nSHARED ({len(shared)}) -> overlay would modify these mainline nodes:")
    for l in shared:
        print(f"  {l}")
    for want in ("qcom_tzlog", "arch_timer"):
        print(f"\nbase has label {want}: {'yes' if want in have else 'NO'}")


def parse_pair(s):
    a, b = (int(x, 0) for x in s.split(","))
    return a, b


def cmd_bos(a):
    # --msm-id yok: board-id only, like Razer's/LineageOS' nicole dtbo
    msm = None if a.msm_id in ("", "yok") else parse_pair(a.msm_id)
    board = parse_pair(a.board_id)
    msm_line = f"\tqcom,msm-id = <0x{msm[0]:x} 0x{msm[1]:x}>;\n" if msm else ""
    dts = ("/dts-v1/;\n/plugin/;\n\n/ {\n" + msm_line +
           f"\tqcom,board-id = <0x{board[0]:x} 0x{board[1]:x}>;\n"
           "};\n")
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "bos.dts")
        out = os.path.join(d, "bos.dtbo")
        open(src, "w").write(dts)
        subprocess.run(["dtc", "-@", "-q", "-I", "dts", "-O", "dtb", "-o", out, src], check=True)
        blob = open(out, "rb").read()
    total = write_table(a.out, blob)
    print(f"{a.out}: {total} bytes, 1 entry, msm-id={msm}, board-id={board}")


def write_table(out, blob):
    """dt_table with a single entry (id/rev/custom 0, like Razer's nicole dtbo)."""
    eoff = HDR.size
    dt_off = eoff + ENT.size
    total = dt_off + len(blob)
    img = HDR.pack(MAGIC, total, HDR.size, ENT.size, 1, eoff, 4096, 0)
    img += ENT.pack(len(blob), dt_off, 0, 0, 0, 0, 0, 0)
    img += blob
    open(out, "wb").write(img)
    return total


def parse_keep(s):
    keep = set()
    for part in filter(None, s.split(",")):
        lo, _, hi = part.partition("-")
        keep.update(range(int(lo), int(hi or lo) + 1))
    return keep


def cmd_parca(a):
    import libfdt
    _, ents = read_table(a.dtbo)
    keep = parse_keep(a.keep)
    f = libfdt.Fdt(ents[0]["blob"])
    q = (libfdt.NOTFOUND,)

    def subnodes(path):
        off = f.path_offset(path, q)
        if off < 0:
            return []
        names, sub = [], f.first_subnode(off, q)
        while sub >= 0:
            names.append(f.get_name(sub))
            sub = f.next_subnode(sub, q)
        return names

    def proplist(path):
        off = f.path_offset(path, q)
        if off < 0:
            return []
        out, po = [], f.first_property_offset(off, q)
        while po >= 0:
            pr = f.get_property_by_offset(po)
            out.append((pr.name, bytes(pr)))
            po = f.next_property_offset(po, q)
        return out

    def gone(path):  # "/fragment@N/..." of a dropped fragment
        head = path.lstrip("/").split("/", 1)[0]
        return head.startswith("fragment@") and int(head.split("@")[1]) not in keep

    frags = [n for n in subnodes("/") if n.startswith("fragment@")]
    dropped = [n for n in frags if int(n.split("@")[1]) not in keep]
    for n in dropped:
        f.del_node(f.path_offset("/" + n))
        if f.path_offset("/__local_fixups__/" + n, q) >= 0:
            f.del_node(f.path_offset("/__local_fixups__/" + n))
    for name, val in proplist("/__fixups__"):
        refs = [r for r in val.split(b"\0") if r]
        left = [r for r in refs if not gone(r.decode().split(":")[0])]
        off = f.path_offset("/__fixups__")
        if left:
            f.setprop(off, name, b"\0".join(left) + b"\0")
        else:
            f.delprop(off, name)
    for name, val in proplist("/__symbols__"):
        if gone(val.rstrip(b"\0").decode()):
            f.delprop(f.path_offset("/__symbols__"), name)
    f.pack()
    total = write_table(a.out, bytes(f.as_bytearray()))
    print(f"{a.out}: {total} bytes, kept {len(frags) - len(dropped)}/{len(frags)} fragments")


def cmd_kok(a):
    """Set root properties of the single overlay without repacking (totalsize kept)."""
    import libfdt
    _, ents = read_table(a.dtbo)
    f = libfdt.Fdt(bytearray(ents[0]["blob"]))
    size = f.totalsize()
    for spec in a.ozellik:
        name, _, vals = spec.partition("=")
        val = b"".join(v.encode() + b"\0" for v in vals.split("|"))
        f.setprop(0, name, val)
    assert f.totalsize() == size
    total = write_table(a.out, bytes(f.as_bytearray()))
    print(f"{a.out}: {total} bytes, root {', '.join(a.ozellik)} (fdt totalsize {size} kept)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("bilgi"); p.add_argument("dtbo"); p.set_defaults(fn=cmd_bilgi)
    p = sub.add_parser("ayikla"); p.add_argument("dtbo"); p.add_argument("outdir"); p.set_defaults(fn=cmd_ayikla)
    p = sub.add_parser("etiketler"); p.add_argument("dtbo"); p.add_argument("base")
    p.add_argument("-e", type=int, default=None, help="only entry N"); p.set_defaults(fn=cmd_etiketler)
    p = sub.add_parser("bos"); p.add_argument("out")
    p.add_argument("--msm-id", default="439,0x20001"); p.add_argument("--board-id", default="0x1001f,0x2")
    p.set_defaults(fn=cmd_bos)
    p = sub.add_parser("parca"); p.add_argument("dtbo"); p.add_argument("out"); p.add_argument("keep")
    p.set_defaults(fn=cmd_parca)
    p = sub.add_parser("kok", help="set root string-list props without repacking")
    p.add_argument("dtbo"); p.add_argument("out")
    p.add_argument("ozellik", nargs="+", help='NAME=v1|v2 (string list), e.g. "compatible=razer,nicole|qcom,sm8350"')
    p.set_defaults(fn=cmd_kok)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
