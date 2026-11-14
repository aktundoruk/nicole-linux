#!/usr/bin/env python3
"""Offline test of nicole-imaj's partition writing (--yaz / --geri helpers) on image files.

Runs on the Mac or the phone: builds fake v3 boot/vendor_boot images with nicole-imaj's own
functions, "partitions" are files, then checks: header lengths, the first write keeps the old
contents, a second identical run writes nothing, a size or header mismatch is refused before
any byte is written, and the range checks (old and new cmdline) refuse what they should.
Usage: nicole-imaj-yaz-test.py [path to nicole-imaj]
"""
import importlib.machinery
import importlib.util
import os
import sys
import tempfile

yol = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), "../../pmaports/device-razer-nicole/nicole-imaj")
yukleyici = importlib.machinery.SourceFileLoader("nicole_imaj", yol)
spec = importlib.util.spec_from_loader("nicole_imaj", yukleyici)
m = importlib.util.module_from_spec(spec)
yukleyici.exec_module(m)

hatalar = 0


def bekle(ad, kosul):
    global hatalar
    print(("tamam  " if kosul else "HATA   ") + ad)
    hatalar += not kosul


def reddeder(ad, f):
    try:
        f()
    except SystemExit as e:
        bekle(f"{ad} (reddetti: {e})", True)
        return
    bekle(f"{ad} (reddetmedi)", False)


boot1 = m.boot_v3(os.urandom(5_000_000), os.urandom(1_000_003), "a=1 b=2")
vend1 = m.vendor_boot_v3(os.urandom(140_001))
boot2 = m.boot_v3(os.urandom(5_100_000), os.urandom(900_000), "a=1 b=3")
vend2 = m.vendor_boot_v3(os.urandom(140_002))
bekle("boot boyu başlıktan", m.imaj_boyu(boot1) == len(boot1))
bekle("vendor_boot boyu başlıktan", m.imaj_boyu(vend1) == len(vend1))
bekle("tanınmayan imaj None", m.imaj_boyu(b"\0" * 8192) is None)

with tempfile.TemporaryDirectory() as d:
    hb, hv, cikti = f"{d}/boot_a", f"{d}/vendor_boot_a", f"{d}/cikti"
    BOY = 12 << 20
    for h, v in ((hb, boot1), (hv, vend1)):
        with open(h, "wb") as f:
            f.write(v + os.urandom(BOY - len(v)))  # the old image plus junk after it
    hedef = {"boot": hb, "vendor_boot": hv}
    yazildi = m.bolumlere_yaz(cikti, {"boot": boot2, "vendor_boot": vend2}, "a", hedef)
    bekle("ilk yazma yaptı", yazildi)
    bekle("boot_a'nın başı yeni imaj", open(hb, "rb").read(len(boot2)) == boot2)
    bekle("vendor_boot_a'nın başı yeni imaj", open(hv, "rb").read(len(vend2)) == vend2)
    bekle("bölüm boyu değişmedi", os.path.getsize(hb) == BOY and os.path.getsize(hv) == BOY)
    bekle("önceki boot saklandı (başlığa göre)", open(f"{cikti}/onceki/boot-v3.img", "rb").read() == boot1)
    bekle("önceki vendor_boot saklandı", open(f"{cikti}/onceki/vendor_boot-v3.img", "rb").read() == vend1)
    bekle("ikinci kez aynı: yazmadı", not m.bolumlere_yaz(cikti, {"boot": boot2, "vendor_boot": vend2}, "a", hedef))
    bekle("ikinci kez onceki/ değişmedi", open(f"{cikti}/onceki/boot-v3.img", "rb").read() == boot1)

    once = open(hb, "rb").read(), open(hv, "rb").read()
    buyuk = m.boot_v3(os.urandom(BOY), b"", "x")
    reddeder("bölüme sığmayan imaj", lambda: m.bolumlere_yaz(cikti, {"boot": buyuk, "vendor_boot": vend1}, "a", hedef))
    reddeder("başlığı boyuna uymayan imaj", lambda: m.bolumlere_yaz(cikti, {"boot": boot1 + b"\0" * 4096, "vendor_boot": vend1}, "a", hedef))
    bekle("reddedilenler hiçbir bayt yazmadı", (open(hb, "rb").read(), open(hv, "rb").read()) == once)

    # --geri: what was kept goes back
    imajlar = {t: open(f"{cikti}/onceki/{t}-v3.img", "rb").read() for t in ("boot", "vendor_boot")}
    m.bolumlere_yaz(cikti, imajlar, "a", hedef, onceki_sakla=False)
    bekle("geri: boot_a eski imaj", open(hb, "rb").read(len(boot1)) == boot1)
    bekle("geri: onceki/ dokunulmadı", open(f"{cikti}/onceki/boot-v3.img", "rb").read() == boot1)

# range arithmetic used for the kernel guard and the new cmdline
A = m.araliklar_coz("0:5306920:24337875,4:1:2,4:86534:24576,4:185783:24576")
bekle("aralık: boot_a kapsanıyor", m.kapsar(A, (4, 86534, 24576)))
bekle("aralık: vendor_boot_a kapsanıyor", m.kapsar(A, (4, 185783, 24576)))
bekle("aralık: boot_b kapsanmıyor", not m.kapsar(A, (4, 304631, 24576)))
bekle("aralık: bir blok taşan kapsanmıyor", not m.kapsar(A, (4, 86534, 24577)))
bekle("aralık: başka LU kapsanmıyor", not m.kapsar(A, (3, 86534, 24576)))
bekle("aralık: boş cmdline", m.araliklar_coz(None) == [])
# which slot --yaz/--geri may write (running slot faked)
with tempfile.TemporaryDirectory() as d:
    os.makedirs(f"{d}/a/etc"); os.makedirs(f"{d}/x/etc")
    open(f"{d}/a/etc/nicole-kurulum", "w").write("Faz 4 kurulumu 2026-11-08: slot A, kök userdata\n")
    open(f"{d}/x/etc/nicole-kurulum", "w").write("Faz 4 kurulumu: slot B\n")
    gercek = m.calisan_slot
    try:
        m.calisan_slot = lambda: "a"
        bekle("A'da çalışan kurulum: a", m.hedef_slot("/") == "a")
        reddeder("A, başka bir kurulumu yazmaz", lambda: m.hedef_slot(f"{d}/a"))
        m.calisan_slot = lambda: "b"
        bekle("B'de çalışan kurulum: b", m.hedef_slot("/") == "b")
        bekle("B'den A'nın kurulumu: a", m.hedef_slot(f"{d}/a") == "a")
        reddeder("B'den A olmayan kurulum", lambda: m.hedef_slot(f"{d}/x"))
        reddeder("B'den nicole-kurulum'u olmayan dizin", lambda: m.hedef_slot(d))
    finally:
        m.calisan_slot = gercek

print("SONUÇ:", "hepsi tamam" if not hatalar else f"{hatalar} hata")
sys.exit(1 if hatalar else 0)
