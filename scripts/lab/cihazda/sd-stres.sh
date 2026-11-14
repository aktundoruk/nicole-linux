#!/bin/sh
# Runs ON the phone (pmOS, as user with doas): microSD write/read integrity test.
# Writes 1 GiB random + 300 MiB zeros, drops the page cache, reads both back twice.
# Prints "SONUC: GECTI" or "SONUC: KALDI". Used for the SDR104 202 MHz check (2026-10-25).
set -u
T=${1:-$HOME/sd-stres}
mkdir -p "$T"
doas -n grep -E "actual clock|timing" /sys/kernel/debug/mmc1/ios
sonuc=GECTI
yaz=$(head -c 1073741824 /dev/urandom | tee "$T/rastgele.bin" | sha256sum | cut -d" " -f1)
dd if=/dev/zero of="$T/sifir.bin" bs=4M count=75 conv=fsync 2>/dev/null
sifir=$(head -c 314572800 /dev/zero | sha256sum | cut -d" " -f1)
sync
for i in 1 2; do
	echo 3 | doas -n tee /proc/sys/vm/drop_caches >/dev/null
	r=$(sha256sum "$T/rastgele.bin" | cut -d" " -f1)
	z=$(sha256sum "$T/sifir.bin" | cut -d" " -f1)
	echo "okuma $i: rastgele $([ "$r" = "$yaz" ] && echo ok || echo BOZUK) sifir $([ "$z" = "$sifir" ] && echo ok || echo BOZUK)"
	[ "$r" = "$yaz" ] && [ "$z" = "$sifir" ] || sonuc=KALDI
done
doas -n dmesg | grep -iE "mmc1|mmcblk1" | grep -iE "err|fail|tun|crc|timeout|reset" | tail -10
rm -rf "$T"
echo "SONUC: $sonuc"
