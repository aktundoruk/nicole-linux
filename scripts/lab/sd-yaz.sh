#!/usr/bin/env bash
# Write the postmarketOS image (out/pmos/razer-nicole.img.zst) to a microSD card on the Mac.
#
# Usage: sd-yaz.sh                 -> lists external physical disks, writes nothing
#        sd-yaz.sh diskN           -> checks diskN, asks for confirmation, writes
#        sd-yaz.sh diskN imaj.zst  -> same with another image
#
# Guards (a wrong disk number would wipe the disk):
#   - only external, non-virtual disks (diskutil "Device Location" / "Virtual")
#   - refuses any disk with an APFS container (macOS disks; a microSD never has one)
#     and any disk whose partitions or containers hold the volume named in RAZER_KORUNAN_BIRIM
#   - refuses disks larger than 160 GB (the card is 64-128 GB; the SSD is 250 GB)
#   - shows name/size/partitions and requires typing the disk name again
# (Tested 2026-10-07: macOS 26 has no "Internal:" field and the SSD is 250.1 GB,
#  so a size-only guard would NOT have protected it; each guard alone refuses it.)
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli diskutil zstd

IMAJ_VARSAYILAN="$PROJE_KOK/out/pmos/razer-nicole.img.zst"
AZAMI_BAYT=$((160 * 1000 * 1000 * 1000))

if [ $# -eq 0 ]; then
	bilgi "Harici fiziksel diskler (microSD kartı burada bul, sonra: $0 diskN):"
	diskutil list external physical
	exit 0
fi

DISK=${1#/dev/}
IMAJ=${2:-$IMAJ_VARSAYILAN}
[[ "$DISK" =~ ^disk[0-9]+$ ]] || hata "Geçersiz disk adı: $DISK (ör. disk6)"
[ -f "$IMAJ" ] || hata "İmaj yok: $IMAJ (önce VM'de scripts/build/pmos-hazirla.sh)"
dur_kontrol

bilgi_al() { diskutil info "/dev/$DISK" | sed -n "s/^ *$1: *//p" | head -1; }
konum=$(bilgi_al "Device Location")
sanal=$(bilgi_al "Virtual")
butun=$(bilgi_al "Whole")
boyut=$(diskutil info "/dev/$DISK" | sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p' | head -1)
[ -n "$boyut" ] || hata "/dev/$DISK okunamadı"
[ "$butun" = "Yes" ] || hata "$DISK bütün disk değil (bölüm adı verme, diskN ver)"
[ "$konum" = "External" ] || hata "$DISK harici disk değil (Device Location=$konum)"
[ "$sanal" = "No" ] || hata "$DISK fiziksel disk değil (Virtual=$sanal; APFS kapsayıcısı mı?)"
[ "$boyut" -le "$AZAMI_BAYT" ] || hata "$DISK $((boyut / 1000000000)) GB: 160 GB'tan büyük, microSD olamaz (SSD mi?)"
liste=$(diskutil list "/dev/$DISK")
if grep -q "Apple_APFS\|Container disk" <<<"$liste"; then
	hata "$DISK üzerinde APFS kapsayıcısı var: bu bir macOS diski (SSD?), microSD değil"
fi
for k in $(grep -o "Container disk[0-9]*" <<<"$liste" | awk '{print $2}'); do
	liste+=$'\n'"$(diskutil list "/dev/$k")"
done
if [ -n "${RAZER_KORUNAN_BIRIM:-}" ] && grep -qF "$RAZER_KORUNAN_BIRIM" <<<"$liste"; then
	hata "$DISK üzerinde $RAZER_KORUNAN_BIRIM birimi var: bu proje diski, yazılmaz"
fi
ham=$(zstd -lv "$IMAJ" 2>/dev/null | sed -n 's/.*Decompressed Size:.*(\([0-9]*\) B).*/\1/p' | head -1)
if [ -n "$ham" ] && [ "$ham" -gt "$boyut" ]; then
	hata "İmaj ($ham bayt) kartdan ($boyut bayt) büyük"
fi

echo
diskutil list "/dev/$DISK"
echo
uyari "/dev/$DISK ($((boyut / 1000000000)) GB) TAMAMEN silinecek ve $IMAJ yazılacak."
printf 'Onaylamak için disk adını tekrar yaz (%s): ' "$DISK"
read -r tekrar
[ "$tekrar" = "$DISK" ] || hata "Onay eşleşmedi, hiçbir şey yazılmadı"

eylem_kaydet "sd-yaz: $IMAJ -> /dev/$DISK ($boyut bayt)"
diskutil unmountDisk "/dev/$DISK"
bilgi "Yazılıyor (sudo şifresi istenebilir)..."
zstd -dc "$IMAJ" | sudo dd of="/dev/r$DISK" bs=4m
sync
diskutil eject "/dev/$DISK" || true
bilgi "Bitti. Kartı Razer'e takabilirsin."
