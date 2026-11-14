#!/usr/bin/env python3
"""Offline test of nicole-slot on a copy of the backed-up LUN 4 GPT (out/faz4/gpt-test/sde-orijinal.img).

Next to the tool runs a model of ABL's slot rules, written from abl LA.UM.9.14.1
(PartitionTableUpdate.c: GetActiveSlot, FindBootableSlot, HandleActiveSlotUnbootable,
SetActiveSlot), applied to the image's boot_a/boot_b bytes, so the whole cycle is played:
daily A, seven failed boots -> B, B repairs -> "gec a" -> A, "gec b" from A, and what
breaks without B's successful bit (the state before this change). Also: byte-level diffs,
both copies, refusals. Usage: nicole-slot-test.py [nicole-slot] [image]
"""
import importlib.machinery, importlib.util, os, shutil, struct, sys, tempfile

kok = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../..")
arac = sys.argv[1] if len(sys.argv) > 1 else f"{kok}/pmaports/device-razer-nicole/nicole-slot"
imaj = sys.argv[2] if len(sys.argv) > 2 else f"{kok}/out/faz4/gpt-test/sde-orijinal.img"
yk = importlib.machinery.SourceFileLoader("nicole_slot", arac)
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("nicole_slot", yk))
yk.exec_module(m)
hatalar = 0


def bekle(ad, kosul):
    global hatalar
    print(("tamam  " if kosul else "HATA   ") + ad)
    hatalar += not kosul


def reddeder(ad, f):
    try:
        f()
    except SystemExit as e:
        bekle(f"{ad} (reddetti: {e})", True); return
    bekle(f"{ad} (reddetmedi)", False)


# --- ABL model on the two bytes (fields as nicole-slot's coz) ---
def abl_ayarla(yol, a, b):
    """Write both bytes as ABL would (through the tool's own checked writer)."""
    m.yaz_plan(yol, {"boot_a": a, "boot_b": b}, False)


def abl_acilis(yol):
    """One power-on: returns the slot ABL boots, or None (No bootable slot -> fastboot),
    updating the bytes the way ABL does."""
    d = m.durumlar(yol)
    aktif = [s for s in "ab" if d[s]["etkin"]]
    aktif.sort(key=lambda s: -d[s]["öncelik"])
    if not aktif:
        return None
    s = aktif[0]
    o = "b" if s == "a" else "a"
    x = d[s]
    if not x["açılamaz"] and x["başarılı"]:
        return s
    if not x["açılamaz"] and not x["başarılı"] and x["deneme"] > 0:
        x["deneme"] -= 1
        abl_ayarla(yol, d["a"], d["b"])
        return s
    # HandleActiveSlotUnbootable
    x["açılamaz"] = 1; x["başarılı"] = 0
    y = d[o]
    if not y["açılamaz"] and y["başarılı"]:
        # SetActiveSlot(o, FALSE): o prio 3, active, tries 7, unbootable off; s prio 2, inactive
        y.update({"öncelik": 3, "etkin": 1, "deneme": 7, "açılamaz": 0})
        x.update({"öncelik": 2, "etkin": 0})
        abl_ayarla(yol, d["a"], d["b"])
        return abl_acilis(yol)  # cold reset, boots again
    abl_ayarla(yol, d["a"], d["b"])
    return None


def sessiz(f, *a):
    import contextlib, io
    with contextlib.redirect_stdout(io.StringIO()):
        return f(*a)


with tempfile.TemporaryDirectory(dir=os.path.dirname(imaj)) as d:
    yol = f"{d}/sde.img"
    shutil.copyfile(imaj, yol) if os.path.getsize(imaj) < (1 << 30) else os.system(f"cp -c '{imaj}' '{yol}' 2>/dev/null || cp '{imaj}' '{yol}'")
    once = m.durumlar(yol)
    print("yedekteki durum:", {s: hex(m.bayt_yap(once[s])) for s in "ab"})

    # byte-level check of one tazele on A
    def blok_oku(lbalar):
        with open(yol, "rb") as f:
            return {l: m.oku(f, l) for l in lbalar}
    with open(yol, "rb") as f:
        a, b = m.ikisi(f, m.toplam(yol, f))
        ia, ib = a.bul("boot_a"), a.bul("boot_b")
        lbalar = sorted({1, a.giris_lba + ia * 128 // 4096, a.giris_lba + ib * 128 // 4096,
                         b.lba, b.giris_lba + ia * 128 // 4096, b.giris_lba + ib * 128 // 4096})
    print("boot_a girişi", ia, "boot_b girişi", ib, "ilgili bloklar", lbalar)
    # start from a known state: A active daily (0x3f), B as now (0x32: prio 2, tries 6)
    sessiz(abl_ayarla, yol, m.coz(0x3f), m.coz(0x32))
    ilk = blok_oku(lbalar)
    sessiz(m.tazele, yol, "a", False)
    son = blok_oku(lbalar)
    izinli = {1: set(range(16, 20)) | set(range(88, 92)), b.lba: set(range(16, 20)) | set(range(88, 92))}
    for g in (a, b):
        izinli.setdefault(g.giris_lba + ib * 128 // 4096, set()).add(ib * 128 % 4096 + 54)
        izinli.setdefault(g.giris_lba + ia * 128 // 4096, set()).add(ia * 128 % 4096 + 54)
    farklar = {l: [i for i in range(4096) if ilk[l][i] != son[l][i]] for l in lbalar}
    disari = {l: [i for i in f if i not in izinli.get(l, set())] for l, f in farklar.items()}
    fark = sum(len(f) for f in farklar.values())
    d1 = m.durumlar(yol)
    bekle(f"tazele (A): B hazır: başarılı=1 açılamaz=0 ({hex(m.bayt_yap(d1['b']))})", d1["b"]["başarılı"] == 1 and d1["b"]["açılamaz"] == 0)
    bekle(f"tazele (A): A deneme 7 başarılı 0 ({hex(m.bayt_yap(d1['a']))})", d1["a"]["deneme"] == 7 and d1["a"]["başarılı"] == 0)
    bekle(f"tazele: {fark} bayt değişti, hepsi izinli yerlerde (boot_b baytı + CRC'ler, iki kopya): {farklar}",
          not any(disari.values()) and all(ib * 128 % 4096 + 54 in farklar[g.giris_lba + ib * 128 // 4096] for g in (a, b)))
    bekle("ikinci tazele yazmaz", "yazılacak bir şey yok" in __import__("subprocess").run(
        [sys.executable, arac, "tazele", "--slot", "a", yol], capture_output=True, text=True).stdout)

    # cycle 1: seven failed boots of A -> B
    yol_ = yol
    for k in range(7):
        bekle(f"başarısız açılış {k+1}: ABL A'yı açar", abl_acilis(yol_) == "a")
    s = abl_acilis(yol_)
    bekle(f"8. açılış: ABL B'ye geçer ({s})", s == "b")
    d2 = m.durumlar(yol)
    bekle("A açılamaz, B etkin", d2["a"]["açılamaz"] == 1 and d2["b"]["etkin"] == 1)
    sessiz(m.tazele, yol, "b", False)
    bekle("B'de tazele A'ya dokunmaz", m.durumlar(yol)["a"] == d2["a"])
    bekle("B açılışları B'de kalır", all(abl_acilis(yol) == "b" for _ in range(3)))
    # B repaired A -> gec a
    sessiz(m.gec, yol, "b", "a", False)
    s = abl_acilis(yol)
    bekle(f"gec a sonrası açılış: A ({s})", s == "a")
    d3 = m.durumlar(yol)
    bekle(f"ABL B'yi açılamaz işaretledi (beklenen), A etkin ({hex(m.bayt_yap(d3['a']))}/{hex(m.bayt_yap(d3['b']))})", d3["b"]["açılamaz"] == 1 and d3["a"]["etkin"] == 1)
    sessiz(m.tazele, yol, "a", False)
    d4 = m.durumlar(yol)
    bekle("A'da tazele: B yine hazır, A yine deneme sayıyor", d4["b"]["açılamaz"] == 0 and d4["b"]["başarılı"] == 1 and d4["a"]["başarılı"] == 0 and d4["a"]["deneme"] == 7)
    # cycle 2: gec b from A, then back
    sessiz(m.gec, yol, "a", "b", False)
    bekle("A'dan gec b: B açılır", abl_acilis(yol) == "b")
    sessiz(m.gec, yol, "b", "a", False)
    bekle("B'den gec a: A açılır", abl_acilis(yol) == "a")
    sessiz(m.tazele, yol, "a", False)
    bekle("ve A yine yedi başarısızlıkta B'ye düşer", [abl_acilis(yol) for _ in range(8)][-1] == "b")
    sessiz(m.gec, yol, "b", "a", False); abl_acilis(yol); sessiz(m.tazele, yol, "a", False)

    # what the state before this change did: B not successful -> no fallback
    sessiz(abl_ayarla, yol, m.coz(0x3f), m.coz(0x32))
    s = [abl_acilis(yol) for _ in range(8)][-1]
    bekle(f"ESKİ durum (B başarılı değil): 8. açılış {s} = No bootable slot (fastboot)", s is None)
    sessiz(abl_ayarla, yol, m.coz(0x3f), m.coz(0x32)); sessiz(m.tazele, yol, "a", False)

    # refusals
    reddeder("zaten olunan slota gec", lambda: sessiz(m.gec, yol, "a", "a", False))
    dd = m.durumlar(yol)
    sessiz(abl_ayarla, yol, dict(dd["a"], etkin=1), dict(dd["b"], etkin=1))
    reddeder("iki slot da etkinken gec", lambda: sessiz(m.gec, yol, "a", "b", False))
    sessiz(abl_ayarla, yol, dd["a"], dd["b"])
    reddeder("çalışan slot açılamazken tazele", lambda: (sessiz(abl_ayarla, yol, dict(dd["a"], açılamaz=1), dd["b"]), sessiz(m.tazele, yol, "a", False)))
    sessiz(abl_ayarla, yol, dict(dd["a"], açılamaz=0), dd["b"])
    with open(yol, "r+b") as f:  # corrupt the primary header CRC
        f.seek(4096 + 16); c = f.read(4); f.seek(4096 + 16); f.write(bytes([c[0] ^ 1]) + c[1:])
    reddeder("bozuk başlık CRC'si", lambda: sessiz(m.tazele, yol, "a", False))
    with open(yol, "r+b") as f:
        f.seek(4096 + 16); f.write(c)
    bekle("onarılan kopya yine okunuyor", m.durumlar(yol)["a"]["etkin"] == 1)
    print("son durum:", {s: hex(m.bayt_yap(m.durumlar(yol)[s])) for s in "ab"})
    os.system(f"cp -c '{yol}' '{os.path.dirname(imaj)}/sde-slot-test-sonu.img' 2>/dev/null")
print("SONUÇ:", "hepsi tamam" if not hatalar else f"{hatalar} hata")
sys.exit(1 if hatalar else 0)
