#!/usr/bin/env bash
# Faz 0 / Adım 3 — Copy device firmware (read-only) for the mainline port.
# Razer/Qualcomm firmware is proprietary: it stays on this Mac and the device only
# (docs/guvenlik-kurallari.md §2, Seviye 4). Never commit or upload the output directory.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"

gerekli adb tar shasum
dur_kontrol
bos_alan_kontrol "$YEDEK_KOK" 4

[ "$(ab get-state 2>/dev/null)" = "device" ] || hata "adb ile bağlı cihaz yok"
ab shell 'su -c id' 2>/dev/null | grep -q 'uid=0' || hata "Root gerekli"

CIKTI="$YEDEK_KOK/firmware-$(damga)"
mkdir -p "$CIKTI"
eylem_kaydet "firmware kopyası başladı → $CIKTI"

DIZINLER=(
	/vendor/firmware_mnt   # modem partition (vfat): adsp/cdsp/slpi/a660_zap/wlan/ipa ...
	/vendor/firmware       # touch, wlan bdf, gpu, venus ...
	/vendor/dsp            # DSP libraries / audio
	/vendor/bt_firmware    # Bluetooth (QCA6490)
	/vendor/etc/acdbdata   # audio calibration
	/odm/firmware
	/odm/etc
)
for d in "${DIZINLER[@]}"; do
	if ab exec-out "su -c 'test -d $d && echo var'" | grep -q var; then
		bilgi "kopyalanıyor: $d"
		ab exec-out "su -c 'tar -cf - $d 2>/dev/null'" | tar -xf - -C "$CIKTI"
	else
		uyari "yok: $d"
	fi
done

# Audio mixer paths / UCM hints for later
for f in /vendor/etc/mixer_paths*.xml /vendor/etc/audio_platform_info*.xml /odm/etc/mixer_paths*.xml; do
	ab exec-out "su -c 'cat $f 2>/dev/null'" > "$CIKTI/$(basename "$f")" || true
done
find "$CIKTI" -maxdepth 1 -type f -empty -delete

( cd "$CIKTI" && find . -type f -exec shasum -a 256 {} + > SHA256SUMS )
find "$CIKTI" -type f | sed "s#^$CIKTI/##" | sort > "$CIKTI/LISTE.txt"
eylem_kaydet "firmware kopyası tamam → $CIKTI ($(wc -l < "$CIKTI/LISTE.txt") dosya)"
bilgi "Bitti: $CIKTI. Eşleme için: docs/firmware-listesi.md"
