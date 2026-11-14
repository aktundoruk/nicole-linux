#!/usr/bin/env bash
# After a manual-reset notification: wait (default up to 12 h) until the device has
# been put back into fastboot by hand, then clear log/DURUM.
# Usage: fastboot-bekle.sh [azami_saat]
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli fastboot

AZAMI_SN=$(( ${1:-12} * 3600 ))
gecen=0
while ! fastboot devices 2>/dev/null | grep -q fastboot; do
	if command -v adb >/dev/null && [ "$(adb get-state 2>/dev/null)" = "device" ]; then
		# Reset landed in Android instead of fastboot: fine, take it from here
		dur_kontrol; ab reboot bootloader; sleep 20; continue
	fi
	(( gecen >= AZAMI_SN )) && hata "Cihaz $((AZAMI_SN / 3600)) saat içinde fastboot'a gelmedi"
	sleep 15; gecen=$((gecen + 15))
done
eylem_kaydet "manuel reset sonrası cihaz fastboot'ta (${gecen}s beklendi)"
[ -f "$LOG_DIR/DURUM" ] && mv "$LOG_DIR/DURUM" "$LOG_DIR/denemeler/DURUM-cozuldu-$(damga).txt"
bilgi "Cihaz fastboot'ta, devam edilebilir"
