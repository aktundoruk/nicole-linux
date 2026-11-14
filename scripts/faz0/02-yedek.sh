#!/usr/bin/env bash
# Faz 0 / Adım 2 — Read-only raw backup of device partitions (requires root via Magisk).
# Every partition is read with dd and verified against an on-device sha256.
# Nothing is written to the device.
#
# Usage: scripts/faz0/02-yedek.sh   (backups go to <project>/yedek on the SSD;
#        override with RAZER_YEDEK=/path)
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"

gerekli adb shasum
dur_kontrol
bos_alan_kontrol "$YEDEK_KOK" 12

# Huge partitions skipped (contents reproducible or user data)
ATLA_RE='^(super|userdata|rawdump|logdump|metadata)$'
# Most important first: calibration/identity data that cannot be recreated
ONCELIK=(persist modemst1 modemst2 fsg fsc devinfo misc frp)
MAKS_BOYUT=$((1024 * 1024 * 1024)) # 1 GiB

[ "$(ab get-state 2>/dev/null)" = "device" ] || hata "adb ile bağlı cihaz yok"
ab shell 'su -c id' 2>/dev/null | grep -q 'uid=0' || hata "Root gerekli (Magisk). Önce cihazı Magisk ile rootlayın"

CIKTI="$YEDEK_KOK/bolumler-$(damga)"
mkdir -p "$CIKTI"
eylem_kaydet "bölüm yedeği başladı → $CIKTI"

TUM=()
while IFS= read -r satir; do
	if [ -n "$satir" ]; then TUM+=("$satir"); fi
done < <(ab exec-out "su -c 'ls /dev/block/by-name/'" | tr -d '\r' | tr ' ' '\n' | sort)
[ ${#TUM[@]} -gt 0 ] || hata "Bölüm listesi okunamadı"
SIRA=("${ONCELIK[@]}")
for b in "${TUM[@]}"; do
	[[ " ${ONCELIK[*]} " == *" $b "* ]] || SIRA+=("$b")
done

basarisiz=()
for b in "${SIRA[@]}"; do
	[[ " ${TUM[*]} " == *" $b "* ]] || continue
	if [[ "$b" =~ $ATLA_RE ]]; then
		bilgi "atlandı (büyük/kullanıcı verisi): $b"; continue
	fi
	boyut=$(ab exec-out "su -c 'blockdev --getsize64 /dev/block/by-name/$b'" | tr -d '\r')
	if [ -z "$boyut" ] || [ "$boyut" -gt "$MAKS_BOYUT" ]; then
		uyari "atlandı (boyut ${boyut:-?} > 1 GiB): $b"; continue
	fi
	printf '  %-24s %10s bayt ... ' "$b" "$boyut"
	ab exec-out "su -c 'dd if=/dev/block/by-name/$b bs=4M 2>/dev/null'" > "$CIKTI/$b.img"
	cihaz_sha=$(ab exec-out "su -c 'sha256sum /dev/block/by-name/$b'" | awk '{print $1}')
	mac_sha=$(shasum -a 256 "$CIKTI/$b.img" | awk '{print $1}')
	if [ "$cihaz_sha" = "$mac_sha" ]; then
		echo "tamam"
		printf '%s  %s.img\n' "$mac_sha" "$b" >> "$CIKTI/SHA256SUMS"
	else
		echo "SAĞLAMA UYUŞMADI"
		basarisiz+=("$b")
	fi
done

ab exec-out "su -c 'ls -l /dev/block/by-name/'" > "$CIKTI/by-name.txt"
ab shell getprop ro.build.fingerprint > "$CIKTI/fingerprint.txt"
ab shell getprop ro.boot.slot_suffix > "$CIKTI/aktif-slot.txt"

if [ ${#basarisiz[@]} -gt 0 ]; then
	eylem_kaydet "yedek: sağlaması uyuşmayan bölümler: ${basarisiz[*]}"
	hata "Sağlaması uyuşmayan bölümler: ${basarisiz[*]}. Tekrar çalıştırın; M0 tamam sayılmaz."
fi
chmod -R a-w "$CIKTI"
eylem_kaydet "bölüm yedeği tamam → $CIKTI"
bilgi "Bitti: $CIKTI ($(du -sh "$CIKTI" | cut -f1)). Bu klasörü ikinci bir yere de kopyalayın."
