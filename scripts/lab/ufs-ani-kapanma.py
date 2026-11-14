#!/usr/bin/env python3
"""Sudden reset with root on UFS: is what fsync acknowledged still there afterwards?

The phone appends numbered lines, fsyncs each and reports the number to the Mac only after
fsync returned, while a second thread churns small files without syncing. Then sysrq b resets
the phone with nothing flushed. After the boot every number the Mac saw must be on the disk,
with an intact checksum. A proper power cut would be harder on the disk's cache: sysrq b resets
the SoC, it does not remove power from the UFS part.

Usage: ufs-ani-kapanma.py TUR [SANIYE]    Each round uses one of slot A's boot attempts.
       ufs-ani-kapanma.py TUR --tus       Someone holds the power key instead of sysrq. Logind
                                          is inhibited, or it would shut down cleanly. Also
                                          measures how long the key was held before the reset.
                                          A boot without ext4 journal recovery is not valid.
"""
import hashlib
import random
import re
import subprocess
import sys
import threading
import time

TUR = int(sys.argv[1])
TUS = "--tus" in sys.argv
_sayi = [a for a in sys.argv[2:] if a.isdigit()]
SANIYE = int(_sayi[0]) if _sayi else 20
TUS_BEKLE = 1800
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
       "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=2", "-o", "ServerAliveCountMax=2", "-o", "LogLevel=ERROR",
       "-i", subprocess.os.path.expanduser("~/.ssh/razer_nicole"), "user@172.16.42.1"]

YAZICI = r'''
import hashlib, os, threading, time
D = "/var/tmp/kapanma"; os.makedirs(D, exist_ok=True)
def cop():
    i = 0
    while True:
        p = f"{D}/k{i % 4000}"
        with open(p + ".t", "wb") as f:
            f.write(os.urandom(8192))
        os.rename(p + ".t", p)
        i += 1
threading.Thread(target=cop, daemon=True).start()
def tus():
    import re, struct
    m = re.search(r'Name="pmic_pwrkey".*?Handlers=[^\n]*?(event\d+)', open("/proc/bus/input/devices").read(), re.S)
    if not m:
        print("TUS yok", flush=True)
        return
    with open("/dev/input/" + m.group(1), "rb") as f:
        while True:
            _, _, tip, kod, deger = struct.unpack("<qqHHi", f.read(24))
            if tip == 1 and kod == 116:
                print("TUS", deger, flush=True)
threading.Thread(target=tus, daemon=True).start()
yol = f"{D}/gunluk"
n = 0
if os.path.exists(yol):
    for s in open(yol, errors="replace"):
        if s.split() and s.split()[0].isdigit():
            n = max(n, int(s.split()[0]) + 1)
fd = os.open(yol, os.O_WRONLY | os.O_CREAT | os.O_APPEND)
while True:
    h = hashlib.sha256(str(n).encode()).hexdigest()[:16]
    os.write(fd, f"{n} {h}\n".encode() + b"x" * 200 + b"\n")
    os.fsync(fd)
    print(n, flush=True)
    n += 1
'''

DENETIM = r'''
import hashlib
gor, bozuk = set(), 0
for s in open("/var/tmp/kapanma/gunluk", errors="replace"):
    a = s.split()
    if len(a) == 2 and a[0].isdigit():
        if hashlib.sha256(a[0].encode()).hexdigest()[:16] == a[1]:
            gor.add(int(a[0]))
        else:
            bozuk += 1
en = max(gor)
eksik = [i for i in range(en + 1) if i not in gor]
print(en, len(eksik), bozuk)
'''


def t(komut, sure=30):
    return subprocess.run(SSH + [komut], capture_output=True, text=True, timeout=sure).stdout


def bekle():
    for _ in range(90):
        try:
            if t("cat /proc/uptime", 8):
                return True
        except subprocess.TimeoutExpired:
            pass
        time.sleep(2)
    return False


def ozellik():
    return t("doas sfdisk -d /dev/sde 2>/dev/null | grep 'name=\"boot_a\"' | sed 's/.*attrs=//'").strip()


hata = 0
for tur in range(1, TUR + 1):
    kimlik = t("cat /proc/sys/kernel/random/boot_id").strip()
    print(f"--- tur {tur}, boot_a {ozellik()}, açılış {kimlik[:8]}", flush=True)
    onek = "doas systemd-inhibit --what=handle-power-key:sleep:idle --who=kapanma --why=test " if TUS else "doas "
    p = subprocess.Popen(SSH + [onek + "python3 -u -"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    p.stdin.write(YAZICI)
    p.stdin.close()
    son = [-1]
    son_an = [time.time()]
    basis = [None]

    def oku():
        for s in p.stdout:
            s = s.strip()
            if s.isdigit():
                son[0] = int(s)
                son_an[0] = time.time()
            elif s == "TUS 1":
                basis[0] = time.time()
                print(f"tuş basıldı {time.strftime('%T')}", flush=True)
            elif s == "TUS 0":
                print(f"tuş bırakıldı {time.time() - basis[0]:.1f} sn sonra, sıfırlanmadı" if basis[0] else s, flush=True)

    threading.Thread(target=oku, daemon=True).start()
    time.sleep(SANIYE + random.random() * 5)
    an = son[0]
    if TUS:
        print(f"HAZIR {time.strftime('%T')}, yazma sürüyor, onay {an}", flush=True)
        bitis = time.time() + TUS_BEKLE
        while time.time() - son_an[0] < 5:
            if time.time() > bitis:
                p.kill()
                print("HATA: tuşa basılmadı", flush=True)
                sys.exit(2)
            time.sleep(0.2)
        if basis[0]:
            print(f"tuş basılı kalma süresi, son onaya kadar: {son_an[0] - basis[0]:.1f} sn", flush=True)
        else:
            print("HATA: tuş görülmeden yazma durdu", flush=True)
    else:
        try:  # the phone resets inside this command, so it never returns
            subprocess.run(SSH + ["doas sh -c 'echo 1 > /proc/sys/kernel/sysrq; echo b > /proc/sysrq-trigger'"],
                           capture_output=True, timeout=6)
        except subprocess.TimeoutExpired:
            pass
    time.sleep(8)
    if p.poll() is None:
        p.kill()
    gorulen = son[0]
    print(f"Mac'in gördüğü son onay: {gorulen} (sıfırlama komutundan hemen önce {an})", flush=True)
    time.sleep(12)
    if not bekle():
        print("HATA: telefon dönmedi")
        sys.exit(2)
    time.sleep(8)
    if t("cat /proc/sys/kernel/random/boot_id").strip() == kimlik:
        print("HATA: telefon sıfırlanmadı, bu tur geçersiz", flush=True)
        sys.exit(2)
    en, eksik, bozuk = t(f"doas python3 - <<'EOF'\n{DENETIM}\nEOF", 60).split()
    kurtarma = re.findall(r"recovery[^\n]*", t("doas dmesg | grep -E 'EXT4-fs.*(recovery|error|warning)|I/O error'"))
    print(f"diskte son: {en}, eksik {eksik}, bozuk satır {bozuk}; açılış {t('uptime -s').strip()}; {kurtarma}", flush=True)
    print(t("doas dmesg | grep -E 'EXT4-fs.*loop0p2|refused|I/O error|ufshc.*(err|fail)' | cut -c1-110").strip(), flush=True)
    print(t("doas tune2fs -l /dev/loop0p2 | grep -E 'Filesystem state|FS Error|Mount count|Last checked|errors'").strip(), flush=True)
    if TUS and not t("doas dmesg | grep -E 'pmOS_root: recovering journal|EXT4-fs.*loop0p2.*(recovery|orphan)'").strip():
        print("GEÇERSİZ: günlük kurtarması yok, temiz kapanmış olabilir", flush=True)
        hata += 1
    if int(en) < gorulen or int(eksik):
        hata += 1
        print("HATA: onaylanan veri kayıp", flush=True)
print(f"son boot_a {ozellik()}; hata={hata}", flush=True)
sys.exit(1 if hata else 0)
