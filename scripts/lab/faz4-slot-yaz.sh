#!/usr/bin/env bash
# Faz 4 (docs/guvenlik-kurallari.md §8, 8 Kasım 2026): write a slot's four boot partitions, make that slot
# active and boot it once, from a running Linux. Slot B is the Linux rescue system (root in
# rawdump), slot A the daily one (root in userdata).
#
# Usage: faz4-slot-yaz.sh <a|b> <DIR> <etiket> [beklenen_kok_uuid]
#   DIR holds boot-v3.img, vendor_boot-v3.img and optionally dtbo.img, vbmeta.img
#   (SHA256SUMS, when present, is checked first).
# Needs RAZER_SEVIYE2_ONAY=evet, and RAZER_FAZ4_ONAY=evet for slot B (fb() enforces it).
# Never boots Android (B is not Android any more), never writes anything else.
# Exit: 0 = the slot booted and answers over SSH with the expected slot and root;
#       2 = it did not come up in time (the phone is left as it is, see the log).
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli fastboot shasum ssh

SLOT=${1:?a|b}; DIR=${2:?imaj dizini}; ETIKET=${3:?etiket}; KOK=${4:-}
[[ "$SLOT" =~ ^[ab]$ ]] || hata "slot a ya da b"
[ "${RAZER_SEVIYE2_ONAY:-}" = "evet" ] || hata "Seviye 2 onayı yok"
[ "$SLOT" = a ] || [ "${RAZER_FAZ4_ONAY:-}" = "evet" ] || hata "B için Faz 4 onayı yok (RAZER_FAZ4_ONAY=evet)"
for f in boot-v3.img vendor_boot-v3.img; do [ -f "$DIR/$f" ] || hata "yok: $DIR/$f"; done
[ ! -f "$DIR/SHA256SUMS" ] || (cd "$DIR" && shasum -a 256 -c SHA256SUMS >/dev/null) || hata "SHA256SUMS tutmuyor"
IP=${RAZER_IP:-172.16.42.1}
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5 -o LogLevel=ERROR -i "$HOME/.ssh/razer_nicole" "user@$IP")
D="$LOG_DIR/denemeler/$(damga)-$ETIKET"
mkdir -p "$D"
dur_kontrol
# shellcheck source=../lib/cihaz.sh
source "$(dirname "$0")/../lib/cihaz.sh"

{
	echo "yöntem: Faz 4, slot $SLOT yaz + aç"
	for f in "$DIR"/*.img; do echo "$(basename "$f") $(shasum -a 256 "$f" | awk '{print $1}')"; done
} > "$D/bilgi.txt"

if ! fastboot_var; then
	bilgi "telefon fastboot'a alınıyor"
	"${SSH[@]}" 'doas systemctl reboot --reboot-argument=bootloader' >/dev/null 2>&1 || true
	fastboot_bekle 120 || hata "telefon 120 sn'de fastboot'a gelmedi ($D)"
fi
sleep 2
echo "önce: $(slot_durumu) retry_a=$(gv slot-retry-count:a) retry_b=$(gv slot-retry-count:b)" | tee -a "$D/slot.txt"
pil_bekle
mac_kilit_bekle

yaz() { # partition file
	bilgi "fastboot flash $1 $(basename "$2")"
	fb flash "$1" "$2" >> "$D/fastboot.txt" 2>&1 || { cat "$D/fastboot.txt"; hata "flash $1 başarısız ($D)"; }
}
yaz "boot_$SLOT" "$DIR/boot-v3.img"
yaz "vendor_boot_$SLOT" "$DIR/vendor_boot-v3.img"
[ ! -f "$DIR/dtbo.img" ] || yaz "dtbo_$SLOT" "$DIR/dtbo.img"
[ ! -f "$DIR/vbmeta.img" ] || yaz "vbmeta_$SLOT" "$DIR/vbmeta.img"
fb "--set-active=$SLOT" >> "$D/slot.txt" 2>&1 || hata "set-active=$SLOT başarısız"
[ "$(gv current-slot)" = "$SLOT" ] || hata "aktif slot $SLOT olmadı: $(slot_durumu)"
echo "sonra: $(slot_durumu) retry_$SLOT=$(gv slot-retry-count:$SLOT)" | tee -a "$D/slot.txt"
t0=$(date +%s)
fb reboot >> "$D/fastboot.txt" 2>&1 || true

for ((i = 0; i < 300; i += 5)); do
	sleep 5
	c=$("${SSH[@]}" 'cat /proc/cmdline; findmnt -no SOURCE /; systemctl is-system-running' 2>/dev/null) || continue
	echo "$c" > "$D/acilis.txt"
	s=$(tr ' ' '\n' <<< "$c" | sed -n 's/^androidboot.slot_suffix=//p')
	k=$(tr ' ' '\n' <<< "$c" | sed -n 's/^pmos_root_uuid=//p')
	echo "$(( $(date +%s) - t0 )) sn: slot $s, kök $k, $(tail -1 <<< "$c")" | tee -a "$D/slot.txt"
	[ "$s" = "_$SLOT" ] || hata "beklenmeyen slot: $s ($D)"
	[ -z "$KOK" ] || [ "$k" = "$KOK" ] || hata "beklenmeyen kök: $k ($D)"
	bilgi "slot $SLOT açıldı ($D)"
	exit 0
done
uyari "slot $SLOT 300 sn'de SSH'a gelmedi ($D)"
exit 2
