#!/usr/bin/env bash
# Faz 3 (dar, docs/guvenlik-kurallari.md §8): copy the phone's own firmware partitions to the Mac,
# read-only. The phone must run the extraction set (scripts/build/ufs-oku-imaj.sh:
# mini initramfs with "nicole.ufsro" + DTB with UFS enabled), e.g.
#   RAZER_SEVIYE2_ONAY=evet RAZER_BASARIDA_KAL=evet scripts/lab/yaz-dene.sh \
#     --boot out/ufs-oku/d5-boot-v3.img --vendor-boot out/ufs-oku/d5-vendor_boot-v3.img \
#     --dtbo out/ufs-oku/d5-dtbo.img ufs-oku
#
# Usage: ufs-oku.sh [bolum ...]     (default: modem_b dsp_b bluetooth_b; also: super)
# Output: $YEDEK_KOK/firmware-<stamp>/<bolum>.img + SHA256SUMS + bolumler.txt
# Firmware stays on this Mac and the phone (docs/guvenlik-kurallari.md §2): never upload or commit it.
#
# Guards: refuses unless the kernel runs with nicole.ufsro and EVERY sd* disk reports
# ro=1 (checked before and after); only partitions named on the command line or the
# default list are read; nothing on the phone is mounted or written.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli python3 shasum
ARAC="$(dirname "$0")/arac"
CIHAZ_IP=${RAZER_IP:-172.16.42.1}
PORT=5600
if [ $# -gt 0 ]; then BOLUMLER=("$@"); else BOLUMLER=(modem_b dsp_b bluetooth_b); fi
for b in "${BOLUMLER[@]}"; do
	# super: 28 Ekim 2026 extension, only for the vendor_b audio files (docs/guvenlik-kurallari.md §8)
	[[ "$b" =~ ^((modem|dsp|bluetooth)_[ab]|super)$ ]] || hata "$b: Faz 3 (dar) yalnız modem/dsp/bluetooth bölümlerini ve super'ı kapsar"
done
dur_kontrol

tl() {
	printf 'echo @@B; %s; echo @@S\n' "$1" | python3 "$ARAC/telnet.py" "${2:-3}" |
		tr -d '\r' | awk '/^@@S$/{f=0} f; /^@@B$/{f=1}'
}
hepsi_ro() {
	local liste
	# shellcheck disable=SC2016  # expands on the phone
	liste=$(tl 'for b in /sys/block/sd*; do [ -e $b ] && echo "${b##*/} $(cat $b/ro)"; done; true')
	[ -n "$liste" ] || { echo "sd yok"; return 1; }
	echo "$liste"
	! grep -qv ' 1$' <<<"$liste"
}

[[ "$(tl 'uname -r')" == *nicole* ]] || hata "telefonda mini initramfs yok (telnet $CIHAZ_IP)"
# keep the mini init's nicole.oto_donus timer off: a long read (super, 8 GiB) outlasts
# it, and yaz-dene.sh's own touch can miss (28 Oct: reboot to fastboot at 4.1 GB)
tl 'touch /tmp/oturum' >/dev/null
tl 'cat /proc/cmdline' | grep -qw nicole.ufsro || hata "çekirdek nicole.ufsro ile açılmamış: UFS koruması yok"
for _ in $(seq 30); do
	[ -n "$(tl 'ls /sys/block | grep "^sd"; true')" ] && break
	sleep 2
done
sleep 3   # all LUs probed
durum=$(hepsi_ro) || hata "UFS disklerinden biri salt okunur DEĞİL, durduruldu: $(tr '\n' ' ' <<<"$durum")"
bilgi "UFS diskleri salt okunur: $(tr '\n' ' ' <<<"$durum")"

D="$YEDEK_KOK/firmware-$(damga)"
mkdir -p "$D"
chmod 700 "$D"
# partition inventory (names/sizes only, read from sysfs)
# shellcheck disable=SC2016  # expands on the phone
tl 'for u in /sys/class/block/sd*/uevent; do p=$(grep PARTNAME= $u | cut -d= -f2); [ -n "$p" ] && d=${u%/uevent} && echo "${d##*/} $p $(cat $d/size)"; done; true' 5 > "$D/bolumler.txt"
bilgi "$(wc -l < "$D/bolumler.txt" | tr -d ' ') bölüm listelendi → $D/bolumler.txt"
eylem_kaydet "ufs-oku: ${BOLUMLER[*]} -> $D"

: > "$D/SHA256SUMS"
for b in "${BOLUMLER[@]}"; do
	dev=$(awk -v b="$b" '$2==b {print $1}' "$D/bolumler.txt")
	[ "$(wc -w <<<"$dev" | tr -d " ")" = 1 ] || hata "$b için tek bölüm bulunamadı: '$dev'"
	sektor=$(awk -v b="$b" '$2==b {print $3}' "$D/bolumler.txt")
	boyut=$((sektor * 512))
	bilgi "$b = /dev/$dev ($((boyut / 1048576)) MiB) okunuyor"
	python3 "$ARAC/al.py" "$PORT" "$D/$b.img" 2> "$D/$b.al.txt" &
	al_pid=$!
	sleep 1
	tl "rm -f /tmp/oku.sha; setsid sh -c 'dd if=/dev/$dev bs=1048576 2>/dev/null | nc 172.16.42.2 $PORT; sha256sum /dev/$dev >/tmp/oku.sha' </dev/null >/dev/null 2>&1 & true" >/dev/null
	wait "$al_pid" || hata "$b: alıcı başarısız ($(cat "$D/$b.al.txt"))"
	n=$(sed -n 's/^bytes=\([0-9]*\) .*/\1/p' "$D/$b.al.txt")
	mac_sha=$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' "$D/$b.al.txt")
	[ "$n" = "$boyut" ] || hata "$b: $n bayt alındı, bölüm $boyut bayt"
	tel_sha=""
	for _ in $(seq 120); do
		tel_sha=$(tl 'cat /tmp/oku.sha 2>/dev/null; true' | awk '{print $1}')
		[ -n "$tel_sha" ] && break
		sleep 2
	done
	[ "$tel_sha" = "$mac_sha" ] || hata "$b: SHA-256 uyuşmuyor (telefon ${tel_sha:-yok}, Mac $mac_sha)"
	echo "$mac_sha  $b.img" >> "$D/SHA256SUMS"
	chmod 600 "$D/$b.img"
	bilgi "$b tamam (sha256 ${mac_sha:0:16}…)"
done
durum=$(hepsi_ro) || hata "okuma SONRASI bir UFS diski salt okunur değil: $(tr '\n' ' ' <<<"$durum")"
eylem_kaydet "ufs-oku: tamam ${BOLUMLER[*]} ($D)"
bilgi "Bitti: $D (diskler hâlâ salt okunur)"
