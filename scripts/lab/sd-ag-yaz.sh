#!/usr/bin/env bash
# Write the postmarketOS image to the phone's own microSD card over the USB network,
# while the phone runs the mini initramfs (telnet on 172.16.42.1:23). No card reader,
# the card never leaves the phone.
#
# Usage: sd-ag-yaz.sh [imaj.zst]      (default: out/pmos/razer-nicole.img.zst)
# Needs RAZER_SD_ONAY=evet: the WHOLE card is overwritten (docs/guvenlik-kurallari.md §2 table, microSD
# row; approved 25 Ekim 2026).
# Precondition: mini initramfs Linux reachable, e.g. after
#   RAZER_SEVIYE2_ONAY=evet RAZER_BASARIDA_KAL=evet scripts/lab/yaz-dene.sh --boot ... sd
# The phone is left in Linux; the caller brings it back (reboot-mode bootloader).
#
# Guards: target is /dev/mmcblk1 only and only if the kernel reports it as an SD card
# (UFS is disabled in the DTS, so internal storage has no block device at all), the
# card is <= 160 GB and >= the image. Verified by re-reading the card with the page
# cache dropped and comparing SHA-256 with what was sent.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli zstd python3 shasum
ARAC="$(dirname "$0")/arac"
IMAJ=${1:-$PROJE_KOK/out/pmos/razer-nicole.img.zst}
CIHAZ_IP=${RAZER_IP:-172.16.42.1}
PORT=5555
HEDEF=mmcblk1
AZAMI_BAYT=$((160 * 1000 * 1000 * 1000))
[ -f "$IMAJ" ] || hata "imaj yok: $IMAJ"
[ "${RAZER_SD_ONAY:-}" = "evet" ] || hata "microSD'nin tamamı silinir: RAZER_SD_ONAY=evet gerekir"
dur_kontrol

# Run one shell line on the phone, print only its output (between markers). The line
# must not end in "&" ("& ; echo" is a syntax error): end background jobs with "& true".
tl() {
	printf 'echo @@B; %s; echo @@S\n' "$1" | python3 "$ARAC/telnet.py" "${2:-3}" |
		tr -d '\r' | awk '/^@@S$/{f=0} f; /^@@B$/{f=1}'
}

ham=$(zstd -lv "$IMAJ" 2>/dev/null | sed -n 's/.*Decompressed Size:.*(\([0-9]*\) B).*/\1/p' | head -1)
[ -n "$ham" ] || hata "imajın açık boyutu okunamadı: $IMAJ"

cekirdek=$(tl 'uname -r') || true
[[ "$cekirdek" == *nicole* ]] || hata "telefonda mini initramfs yok (telnet $CIHAZ_IP: '${cekirdek:-yanıt yok}')"
tur=$(tl "cat /sys/block/$HEDEF/device/type")
ad=$(tl "cat /sys/block/$HEDEF/device/name")
sektor=$(tl "cat /sys/block/$HEDEF/size")
diskler=$(tl 'ls /sys/block | tr "\n" " "; echo')
[ "$tur" = "SD" ] || hata "/dev/$HEDEF SD kart değil (type='$tur'); bloklar: $diskler"
[[ "$sektor" =~ ^[0-9]+$ ]] || hata "/dev/$HEDEF boyutu okunamadı: '$sektor'"
boyut=$((sektor * 512))
[ "$boyut" -le "$AZAMI_BAYT" ] || hata "/dev/$HEDEF $((boyut / 1000000000)) GB: microSD olamaz"
[ "$boyut" -ge "$ham" ] || hata "imaj ($ham bayt) karttan ($boyut bayt) büyük"
bilgi "Hedef: /dev/$HEDEF ($ad, $((boyut / 1000000000)) GB, SD); bloklar: $diskler"
bilgi "İmaj: $IMAJ ($ham bayt açık)"
eylem_kaydet "sd-ag-yaz: $IMAJ -> telefon /dev/$HEDEF ($ad)"

tl "rm -f /tmp/dd.*; setsid sh -c 'nc -l -p $PORT </dev/null | dd of=/dev/$HEDEF bs=4194304 2>/tmp/dd.log; sync; echo bitti >/tmp/dd.durum' </dev/null >/dev/null 2>&1 & true" >/dev/null
sleep 2   # no port probe: busybox nc -l takes the first connection, a probe would be it
# netstat instead of a connect probe (a probe would be accepted as the data connection)
tl "netstat -ltn | grep -q ':$PORT ' && echo dinliyor" | grep -q dinliyor ||
	hata "telefonda alıcı ($PORT) başlamadı"
bilgi "Gönderiliyor (USB 2.0, ~1-2 dk)"
gonderim=$(zstd -dc "$IMAJ" | python3 "$ARAC/gonder.py" "$CIHAZ_IP" "$PORT" 2>&1 | tee /dev/stderr | tail -1)
n=$(sed -n 's/^bytes=\([0-9]*\) .*/\1/p' <<<"$gonderim")
sha=$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' <<<"$gonderim")
[ "$n" = "$ham" ] || hata "gönderilen $n bayt, beklenen $ham"

for _ in $(seq 60); do
	[ "$(tl 'cat /tmp/dd.durum 2>/dev/null')" = "bitti" ] && break
	sleep 2
done
bilgi "dd: $(tl 'cat /tmp/dd.log' | tr '\n' ' ')"
bilgi "Doğrulama: kart önbelleksiz yeniden okunuyor"
tl "sync; echo 3 >/proc/sys/vm/drop_caches; setsid sh -c 'dd if=/dev/$HEDEF bs=4194304 count=$(( (n + 4194303) / 4194304 )) iflag=direct 2>/dev/null | head -c $n | sha256sum >/tmp/dd.sha' </dev/null >/dev/null 2>&1 & true" >/dev/null
okunan=""
for _ in $(seq 90); do
	okunan=$(tl 'cat /tmp/dd.sha 2>/dev/null' | awk '{print $1}')
	[ -n "$okunan" ] && break
	sleep 2
done
[ "$okunan" = "$sha" ] || hata "SHA-256 uyuşmuyor: gönderilen $sha, karttan okunan ${okunan:-yok}"
tl "blockdev --rereadpt /dev/$HEDEF; sleep 1; grep $HEDEF /proc/partitions" 4
eylem_kaydet "sd-ag-yaz: tamam, $n bayt, sha256 $sha"
bilgi "microSD yazıldı ve doğrulandı ($n bayt, sha256 ${sha:0:16}…)"
