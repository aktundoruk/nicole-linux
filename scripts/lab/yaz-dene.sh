#!/usr/bin/env bash
# One boot attempt from flash: write slot A partitions, make A active, normal reboot.
#
# Why (2026-10-25): this ABL answers every `fastboot boot` with OKAY but never leaves
# BootLinux (USB stays up), even for LineageOS' own boot.img. A normal boot from slot A
# also has a safety net that RAM boots lack: every failed boot of A uses up one retry
# (7 after --set-active=a), then ABL falls back to B (Android) by itself.
#
# Usage: yaz-dene.sh [--boot IMG] [--vendor-boot IMG] [--dtbo IMG] <etiket> [zaman_asimi_sn]
# Needs RAZER_SEVIYE2_ONAY=evet and the matching docs/guvenlik-kurallari.md §8 approvals (boot_a,
# vendor_boot_a, dtbo_a are Seviye 2; fb() refuses anything else).
# Exit codes: 0 = Linux reachable over USB network, 2 = no Linux but the device came
# back (fastboot or Android B) by itself, 3 = manual reset needed (log/DURUM).
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli fastboot adb nc shasum

# macOS bash 3.2: no associative arrays; partition i is written from file i
BOLUMLER=() DOSYALAR=()
ekle() { BOLUMLER+=("$1"); DOSYALAR+=("$2"); }
while [ $# -gt 0 ]; do
	case "$1" in
		--boot) ekle boot_a "${2:?}"; shift ;;
		--vendor-boot) ekle vendor_boot_a "${2:?}"; shift ;;
		--dtbo) ekle dtbo_a "${2:?}"; shift ;;
		-h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) hata "bilinmeyen seçenek: $1" ;;
		*) break ;;
	esac
	shift
done
ETIKET=${1:?etiket}
ZAMAN_ASIMI=${2:-300}
[ "${#BOLUMLER[@]}" -gt 0 ] || hata "yazılacak bölüm yok (--boot / --vendor-boot / --dtbo)"
[ "${RAZER_SEVIYE2_ONAY:-}" = "evet" ] || hata "Seviye 2 onayı yok (RAZER_SEVIYE2_ONAY=evet ve docs/guvenlik-kurallari.md §8)"
for f in "${DOSYALAR[@]}"; do [ -f "$f" ] || hata "dosya yok: $f"; done
CIHAZ_IP=${RAZER_IP:-172.16.42.1}
D="$LOG_DIR/denemeler/$(damga)-$ETIKET"
OZET="$LOG_DIR/denemeler/ozet.tsv"
mkdir -p "$D"
[ -f "$OZET" ] || printf 'zaman\tetiket\tsonuc\tsure_sn\timaj_sha256\n' > "$OZET"
dur_kontrol
# shellcheck source=../lib/cihaz.sh
source "$(dirname "$0")/../lib/cihaz.sh"

{
	echo "yöntem: flash + normal açılış (A)"
	for i in "${!BOLUMLER[@]}"; do echo "${BOLUMLER[$i]}: ${DOSYALAR[$i]} $(shasum -a 256 "${DOSYALAR[$i]}" | awk '{print $1}')"; done
} > "$D/bilgi.txt"
SHA=$(shasum -a 256 "${DOSYALAR[0]}" | awk '{print $1}')   # first written image (boot first when given)

fastboot_a_don || { echo "$(zaman) MANUEL_RESET: deneme öncesi cihaz fastboot'ta değil" > "$LOG_DIR/DURUM"; exit 3; }
echo "deneme öncesi: $(slot_durumu)" | tee -a "$D/slot.txt" >> "$D/bilgi.txt"
# Normally B is booted once to prove it still works. RAZER_ANDROID_ACMA=hayir skips that: Android
# changes userdata and keys when it runs, and a raw backup can only be restored if it didn't
# run since (docs/geri-donus.md). The end of a failed attempt then stays in fastboot as well.
if [ "${RAZER_ANDROID_ACMA:-}" = "hayir" ]; then
	[ "$(gv slot-unbootable:b)" = "no" ] || hata "B açılamaz işaretli: $(slot_durumu)"
else
	b_saglam_mi || b_geri_getir || { [ -f "$LOG_DIR/DURUM" ] || echo "$(zaman) DUR: deneme öncesi B geri getirilemedi ($D)" > "$LOG_DIR/DURUM"; exit 3; }
fi
pil_bekle
mac_kilit_bekle

for i in "${!BOLUMLER[@]}"; do
	bilgi "fastboot flash ${BOLUMLER[$i]} ${DOSYALAR[$i]}"
	fb flash "${BOLUMLER[$i]}" "${DOSYALAR[$i]}" >> "$D/fastboot.txt" 2>&1 ||
		{ cat "$D/fastboot.txt"; hata "flash ${BOLUMLER[$i]} başarısız (cihaz B'de, A yarım yazılmış olabilir)"; }
done
fb --set-active=a >> "$D/slot.txt" 2>&1 || hata "set-active=a başarısız"
[ "$(gv current-slot)" = "a" ] || hata "aktif slot A olmadı: $(slot_durumu)"
echo "A aktif: $(slot_durumu) retry_a=$(gv slot-retry-count:a)" >> "$D/slot.txt"

# USB timeline: every change of the phone's USB device set (a reboot loop shows up as
# a series of YOK lines); ioreg is macOS-only, the timeline is optional. `|| true`:
# with the phone gone grep matches nothing and errexit would end the monitor
usb_izle() {
	local son="__" n
	while :; do
		n=$(ioreg -p IOUSB -w0 2>/dev/null | grep -v -e XHCI -e 'Root ' -e SanDisk \
			| sed -E 's/.*-o ([^<]*)<.*id (0x[0-9a-f]+).*/\1 \2/' | tr '\n' ';' || true)
		[ "$n" != "$son" ] && { echo "$(( $(date +%s) - baslangic )) ${n:-YOK}"; son=$n; }
		sleep 0.2
	done
}
bilgi "Normal açılış (A); zaman aşımı ${ZAMAN_ASIMI} sn"
baslangic=$(date +%s)
command -v ioreg >/dev/null && { usb_izle > "$D/usb.txt" 2>/dev/null & IZLE_PID=$!; }
fb reboot >> "$D/fastboot.txt" 2>&1 || true

sonuc="yanit-yok"
while (( $(date +%s) - baslangic < ZAMAN_ASIMI )); do
	gecen=$(( $(date +%s) - baslangic ))
	if nc -z -G 2 "$CIHAZ_IP" 22 2>/dev/null; then sonuc="ssh"; break; fi
	if nc -z -G 2 "$CIHAZ_IP" 23 2>/dev/null; then sonuc="telnet"; break; fi
	if [ "$(adb get-state 2>/dev/null)" = "device" ]; then
		sonuc="android$(adb shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r')"; break
	fi
	if (( gecen > 15 )) && fastboot_var; then sonuc="fastboot"; break; fi
	sleep 2
done
sure=$(( $(date +%s) - baslangic ))
[ -n "${IZLE_PID:-}" ] && kill "$IZLE_PID" 2>/dev/null || true
ifconfig > "$D/mac-ifconfig.txt" 2>&1 || true
yeniden=$(grep -c ' YOK$' "$D/usb.txt" 2>/dev/null || true)
[ -n "$yeniden" ] && sonuc="$sonuc|usb_kopma=$yeniden"

case "$sonuc" in
	ssh*)
		# the PMIC RTC is read-only and counts from 1970 (the offset lives in Android);
		# set the clock from the Mac (timesyncd keeps it across reboots)
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			-o ConnectTimeout=5 -i "${RAZER_SSH_ANAHTAR:-$HOME/.ssh/razer_nicole}" \
			"${RAZER_SSH_KULLANICI:-user}@$CIHAZ_IP" "doas -n date -s @$(date +%s) >/dev/null; uname -a; cat /proc/cmdline; doas dmesg || dmesg" \
			> "$D/dmesg.txt" 2>&1 || true ;;
	telnet*)
		# /tmp/oturum: tells the mini init's nicole.oto_donus timer that the Mac is here
		printf 'touch /tmp/oturum\nuname -a\ncat /proc/cmdline\ndmesg\nexit\n' | python3 "$(dirname "$0")/arac/telnet.py" 3 > "$D/dmesg.txt" 2>&1 || true ;;
	fastboot*)
		echo "fastboot'ta: $(slot_durumu) retry_a=$(gv slot-retry-count:a)" >> "$D/slot.txt" ;;
	android*)
		echo "Android açıldı: $sonuc" >> "$D/slot.txt" ;;
esac
printf '%s\t%s\t%s\t%s\t%s\n' "$(zaman)" "$ETIKET" "yaz:$sonuc" "$sure" "$SHA" >> "$OZET"
eylem_kaydet "yaz-dene $ETIKET: $sonuc (${sure}s) → $D"

case "$sonuc" in
	ssh*|telnet*)
		bilgi "Linux erişilebilir ($sonuc). Loglar: $D"
		[ "${RAZER_BASARIDA_KAL:-}" = "evet" ] && exit 0
		# A is active: a plain reboot would start our image again. Back to fastboot,
		# then B active again. pmOS: systemd's clean shutdown (root is on the card) with
		# the reboot argument, ~6 s to fastboot; reboot-mode skips the unmount.
		printf 'reboot-mode bootloader\n' | python3 "$(dirname "$0")/arac/telnet.py" 3 >> "$D/dmesg.txt" 2>&1 || true
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
			-i "${RAZER_SSH_ANAHTAR:-$HOME/.ssh/razer_nicole}" "${RAZER_SSH_KULLANICI:-user}@$CIHAZ_IP" \
			'doas systemctl reboot --reboot-argument=bootloader || doas reboot-mode bootloader' >/dev/null 2>&1 || true
		fastboot_bekle 300 || fastboot_a_don || { echo "$(zaman) MANUEL_RESET: Linux sonrası fastboot'a dönülemedi ($D)" > "$LOG_DIR/DURUM"; exit 3; }
		echo "Linux sonrası: $(slot_durumu)" >> "$D/slot.txt"
		b_saglam_mi || b_geri_getir || exit 3
		exit 0 ;;
	android*)
		bilgi "Android açıldı ($sonuc); fastboot'a dönülüyor"
		ab reboot bootloader; fastboot_bekle 90 || { echo "$(zaman) MANUEL_RESET: Android'den fastboot'a dönülemedi ($D)" > "$LOG_DIR/DURUM"; exit 3; } ;;
	fastboot*) ;;
	*)
		uyari "Sonuç: $sonuc. Kendiliğinden kurtulması bekleniyor (en fazla ${KENDILIGINDEN_SN} sn)"
		fastboot_a_don || { echo "$(zaman) MANUEL_RESET: yaz-dene $ETIKET sonrası cihaz kendiliğinden kurtulmadı ($D)" > "$LOG_DIR/DURUM"; echo "Manuel reset gerekli → log/DURUM, docs/geri-donus.md" >&2; exit 3; } ;;
esac
echo "deneme sonrası: $(slot_durumu) retry_a=$(gv slot-retry-count:a)" | tee -a "$D/slot.txt" >> "$D/bilgi.txt"
if [ "${RAZER_ANDROID_ACMA:-}" = "hayir" ]; then
	bilgi "RAZER_ANDROID_ACMA=hayir: telefon fastboot'ta kalıyor, Android açılmadı"
else
	b_saglam_mi || b_geri_getir || { [ -f "$LOG_DIR/DURUM" ] || echo "$(zaman) DUR: yaz-dene $ETIKET sonrası B geri getirilemedi ($D)" > "$LOG_DIR/DURUM"; exit 3; }
fi
bilgi "Sonuç: $sonuc. Slot durumu: $(slot_durumu). Loglar: $D"
exit 2
