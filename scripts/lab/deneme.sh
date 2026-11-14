#!/usr/bin/env bash
# One RAM-only boot attempt (fastboot boot), with logging, webcam shots and recovery.
#
# Usage: deneme.sh <boot.img> <etiket> [zaman_asimi_sn]
# Exit codes: 0 = device reachable over USB network, 2 = no response but recovered to
# fastboot by itself, 3 = manual reset needed (log/DURUM is written, Claude notifies).
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli fastboot nc shasum

IMAJ=${1:?boot imajı}
ETIKET=${2:?etiket}
ZAMAN_ASIMI=${3:-180}
CIHAZ_IP=${RAZER_IP:-172.16.42.1}   # postmarketOS initramfs / rootfs USB network default
LAB="$(dirname "$0")"
D="$LOG_DIR/denemeler/$(damga)-$ETIKET"
OZET="$LOG_DIR/denemeler/ozet.tsv"
mkdir -p "$D"
[ -f "$OZET" ] || printf 'zaman\tetiket\tsonuc\tsure_sn\timaj_sha256\n' > "$OZET"

dur_kontrol
kamera() { "$LAB/kamera.sh" "$ETIKET-$1" >/dev/null 2>&1 && cp "$(ls -t "$LOG_DIR"/kamera/*/*"$ETIKET-$1".jpg | head -1)" "$D/" || true; }
# shellcheck source=../lib/cihaz.sh
source "$(dirname "$0")/../lib/cihaz.sh"

SHA=$(shasum -a 256 "$IMAJ" | awk '{print $1}')
printf 'imaj: %s\nsha256: %s\netiket: %s\n' "$IMAJ" "$SHA" "$ETIKET" > "$D/bilgi.txt"

fastboot_a_don || {
	echo "$(zaman) MANUEL_RESET: deneme öncesi cihaz fastboot'ta değil" > "$LOG_DIR/DURUM"
	echo "Cihaz fastboot'ta değil ve kendiliğinden kurtulmadı → log/DURUM" >&2
	exit 3
}
echo "deneme öncesi: $(slot_durumu)" | tee -a "$D/slot.txt" >> "$D/bilgi.txt"
if ! b_saglam_mi; then
	if ! b_geri_getir; then
		[ -f "$LOG_DIR/DURUM" ] || echo "$(zaman) DUR: deneme öncesi B geri getirilemedi ($D)" > "$LOG_DIR/DURUM"
		echo "B slotu geri getirilemedi; deneme yapılmadı → log/DURUM" >&2
		exit 3
	fi
fi
fastboot getvar current-slot >> "$D/bilgi.txt" 2>&1 || true

pil_bekle

# Fresh ABL for every attempt: after a failed BootLinux this ABL answers every later
# `fastboot boot` with "Load Error" (observed 2026-10-24), which would hide the real result.
if [ "${RAZER_TEMIZ_ABL:-evet}" = "evet" ]; then
	fb reboot bootloader >> "$D/fastboot.txt" 2>&1 || true
	sleep 3
	fastboot_bekle 90 || { echo "$(zaman) MANUEL_RESET: reboot bootloader sonrası fastboot yok ($D)" > "$LOG_DIR/DURUM"; exit 3; }
	b_saglam_mi || { b_geri_getir || exit 3; }
	: > "$D/fastboot.txt"
fi

# Deneme 3 (docs/guvenlik-kurallari.md onayı 24 Ekim 2026): boot with slot A active so ABL reads the
# empty dtbo_a and uses our single DTB. The slot goes back to B after the attempt.
DENEME_SLOT=${RAZER_DENEME_SLOT:-b}
if [ "$DENEME_SLOT" = "a" ]; then
	RAZER_SEVIYE2_ONAY=evet fb --set-active=a >> "$D/slot.txt" 2>&1 || hata "set-active=a başarısız"
	[ "$(gv current-slot)" = "a" ] || hata "aktif slot A olmadı: $(slot_durumu)"
	echo "deneme için A aktif: $(slot_durumu)" >> "$D/slot.txt"
fi

bilgi "fastboot boot: $IMAJ"
baslangic=$(date +%s)
fb boot "$IMAJ" > "$D/fastboot.txt" 2>&1 || { cat "$D/fastboot.txt"; uyari "fastboot boot reddedildi"; }

sonuc="yanit-yok"
cekilen_kare=""
while (( $(date +%s) - baslangic < ZAMAN_ASIMI )); do
	gecen=$(( $(date +%s) - baslangic ))
	for k in 5 20 60 120; do
		if (( gecen >= k )) && [[ " $cekilen_kare " != *" $k "* ]]; then
			kamera "${k}sn"; cekilen_kare+=" $k"
		fi
	done
	if nc -z -G 2 "$CIHAZ_IP" 22 2>/dev/null; then sonuc="ssh"; break; fi
	if nc -z -G 2 "$CIHAZ_IP" 23 2>/dev/null; then sonuc="telnet"; break; fi
	if fastboot_var && (( gecen > 15 )); then sonuc="fastboot-a-dustu"; break; fi
	sleep 3
done
sure=$(( $(date +%s) - baslangic ))
ifconfig > "$D/mac-ifconfig.txt" 2>&1 || true
# ABL's own answer to "fastboot boot" (e.g. "Load Error") goes into the summary
abl_cevap=$(sed -n "s/.*FAILED (remote: '\(.*\)').*/\1/p; s/.*FAILED (\(usb_read.*\)).*/\1/p" "$D/fastboot.txt" | head -1)
grep -q "^Booting.*OKAY" "$D/fastboot.txt" && abl_cevap="Booting OKAY"
[ -n "$abl_cevap" ] && sonuc="$sonuc|$abl_cevap"

case "$sonuc" in
	ssh)
		# pmOS image: user "user" + dedicated key (docs/boot-plani.md §6). BatchMode: never
		# stop at a password prompt in an unattended run.
		SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
			-o ConnectTimeout=5 -i "${RAZER_SSH_ANAHTAR:-$HOME/.ssh/razer_nicole}"
			"${RAZER_SSH_KULLANICI:-user}@$CIHAZ_IP")
		"${SSH[@]}" 'uname -a; cat /proc/cmdline; doas dmesg || dmesg' > "$D/dmesg.txt" 2>&1 || true
		;;
	telnet)
		printf 'uname -a\ncat /proc/cmdline\ndmesg\nexit\n' | python3 "$(dirname "$0")/arac/telnet.py" 3 > "$D/dmesg.txt" 2>&1 || true
		;;
esac
kamera "son"
printf '%s\t%s\t%s\t%s\t%s\n' "$(zaman)" "$ETIKET" "$sonuc" "$sure" "$SHA" >> "$OZET"
eylem_kaydet "deneme $ETIKET: $sonuc (${sure}s) → $D"

case "$sonuc" in
	ssh*|telnet*)
		bilgi "Cihaz erişilebilir ($sonuc). Loglar: $D"
		if [ "$DENEME_SLOT" = "a" ] && [ "${RAZER_BASARIDA_KAL:-}" != "evet" ]; then
			# Slot A is active: a plain reboot would start A's old Android. Go back to
			# fastboot with the reboot-mode helper, then make B active again.
			bilgi "Linux'tan bootloader'a dönülüyor (reboot-mode), sonra B geri alınacak"
			printf 'reboot-mode bootloader\n' | python3 "$(dirname "$0")/arac/telnet.py" 3 >> "$D/dmesg.txt" 2>&1 || true
			if fastboot_bekle 120; then
				echo "Linux sonrası: $(slot_durumu)" >> "$D/slot.txt"
				b_saglam_mi || b_geri_getir || { [ -f "$LOG_DIR/DURUM" ] || echo "$(zaman) DUR: Linux sonrası B geri getirilemedi ($D)" > "$LOG_DIR/DURUM"; exit 3; }
			else
				uyari "120 sn içinde fastboot gelmedi; kendiliğinden kurtulma bekleniyor"
				fastboot_a_don || { echo "$(zaman) MANUEL_RESET: Linux sonrası fastboot'a dönülemedi ($D)" > "$LOG_DIR/DURUM"; exit 3; }
				b_saglam_mi || b_geri_getir || exit 3
			fi
		fi
		exit 0 ;;
esac
uyari "Sonuç: $sonuc. Kendiliğinden kurtulması bekleniyor (en fazla ${KENDILIGINDEN_SN} sn)"
kamera "kurtarma-oncesi"
if fastboot_a_don; then
	echo "deneme sonrası: $(slot_durumu)" | tee -a "$D/slot.txt" >> "$D/bilgi.txt"
	if ! b_saglam_mi; then
		if ! b_geri_getir; then
			[ -f "$LOG_DIR/DURUM" ] || echo "$(zaman) DUR: deneme $ETIKET sonrası B geri getirilemedi ($D)" > "$LOG_DIR/DURUM"
			exit 3
		fi
	fi
	bilgi "Slot durumu: $(slot_durumu)"
	exit 2
fi
kamera "manuel-reset-gerekli"
echo "$(zaman) MANUEL_RESET: deneme $ETIKET sonrası cihaz kendiliğinden kurtulmadı ($D)" > "$LOG_DIR/DURUM"
echo "Manuel reset gerekli → log/DURUM, docs/geri-donus.md" >&2
exit 3
