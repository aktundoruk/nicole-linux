#!/usr/bin/env python3
"""Check a full UFS backup (ufs-tam-yedek.sh) against the phone's own partition hashes.

Usage: tam-yedek-dogrula.py DIR [--cikar persist,misc,...]

Rebuilds every LU from its compressed pieces in stream order and hashes each partition at
the offset the phone reported. A match proves that the pieces are complete and that the
cut around userdata puts every byte back where it was. Compares the two slots as well
(M0 asked for it). --cikar also writes the named partitions to DIR/bolumler/.
Reads only; prints a report and writes it to DIR/dogrulama.txt.
"""
import hashlib
import subprocess
import sys
from pathlib import Path

D = Path(sys.argv[1])
cikar = set()
if "--cikar" in sys.argv:
    cikar = set(sys.argv[sys.argv.index("--cikar") + 1].split(","))

LU, BOLUM = {}, []
for line in (D / "disk.txt").read_text().splitlines():
    a = line.split()
    if a and a[0] == "LU":
        LU[a[1]] = int(a[2].split("=")[1]) * 512
    elif len(a) >= 5 and a[0] in ("sda", "sdb", "sdc", "sdd", "sde", "sdf"):
        BOLUM.append((a[0], a[1], a[2], int(a[3].split("=")[1]) * 512, int(a[4].split("=")[1]) * 512))

tel = {}
for line in (D / "bolum-sha256.txt").read_text().splitlines():
    h, dev = line.split()
    tel[dev.rsplit("/", 1)[1]] = h

PARCA = {"sda": ["sda-on"]
         + sorted(f.name[:-8] for f in D.glob("sda-userdata-*.img.zst"))
         + ["sda-son"]}
rapor, hata = [], 0
sonuc = {}
for lu, boyut in sorted(LU.items()):
    parcalar = PARCA.get(lu, [lu])
    bolumler = sorted((b for b in BOLUM if b[0] == lu), key=lambda b: b[3])
    konum, i, h, f = 0, 0, None, None
    bitis = 0
    for parca in parcalar:
        p = subprocess.Popen(["zstd", "-dc", str(D / f"{parca}.img.zst")], stdout=subprocess.PIPE)
        while True:
            veri = p.stdout.read(1 << 22)
            if not veri:
                break
            m = 0
            while m < len(veri):
                if h is None and i < len(bolumler) and konum >= bolumler[i][3]:
                    h = hashlib.sha256()
                    bitis = bolumler[i][3] + bolumler[i][4]
                    f = None
                    if bolumler[i][2] in cikar:
                        (D / "bolumler").mkdir(exist_ok=True)
                        f = open(D / "bolumler" / f"{bolumler[i][2]}.img", "wb")
                if h is not None:
                    n = min(len(veri) - m, bitis - konum)
                    h.update(veri[m:m + n])
                    if f:
                        f.write(veri[m:m + n])
                else:
                    sonraki = bolumler[i][3] if i < len(bolumler) else konum + len(veri) - m
                    n = min(len(veri) - m, sonraki - konum)
                m += n
                konum += n
                if h is not None and konum == bitis:
                    _, dev, ad, _, _ = bolumler[i]
                    ozet = h.hexdigest()
                    sonuc[ad] = ozet
                    if ozet != tel.get(dev):
                        hata += 1
                        rapor.append(f"HATA {dev} {ad}: yedek {ozet}, telefon {tel.get(dev)}")
                    if f:
                        f.close()
                    h, f = None, None
                    i += 1
        p.wait()
    if konum != boyut:
        hata += 1
        rapor.append(f"HATA {lu}: {konum} bayt çıktı, LU {boyut} bayt")
    if i != len(bolumler):
        hata += 1
        rapor.append(f"HATA {lu}: {len(bolumler) - i} bölüm doğrulanamadı")
    rapor.append(f"{lu}: {boyut} bayt, {i} bölüm")

rapor.append("")
rapor.append("slot karşılaştırması (A / B):")
for ad in sorted(sonuc):
    if ad.endswith("_a") and ad[:-2] + "_b" in sonuc:
        rapor.append(f"  {ad[:-2]:<16} {'aynı' if sonuc[ad] == sonuc[ad[:-2] + '_b'] else 'FARKLI'}")
rapor.append("")
rapor.append(f"{len(sonuc)} bölüm doğrulandı, {hata} hata")
metin = "\n".join(rapor) + "\n"
(D / "dogrulama.txt").write_text(metin)
print(metin, end="")
sys.exit(1 if hata else 0)
