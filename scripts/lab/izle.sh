#!/usr/bin/env bash
# Thermal / battery watchdog for our own Linux on the device (docs/guvenlik-kurallari.md §3).
# Polls over SSH every 60 s, writes CSV, and on a "Durdur" threshold stops the load
# and sends the device back to the bootloader.
# Usage: izle.sh [oturum_sn]  (runs until interrupted; start it in the background)
#   oturum_sn: §3.1 blind-period limit (default 1800 while the fan does not run):
#   after it the device goes back to the bootloader (charges there) and izle.sh exits 5.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"

CIHAZ_IP=${RAZER_IP:-172.16.42.1}
# pmOS image: user "user" + dedicated key; root actions via doas without a password
# (package razer-nicole-lab). The mini initramfs has no SSH: izle.sh needs the pmOS image.
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes
	-i "${RAZER_SSH_ANAHTAR:-$HOME/.ssh/razer_nicole}" "${RAZER_SSH_KULLANICI:-user}@$CIHAZ_IP")
CSV="$LOG_DIR/termal-$(date +%Y-%m-%d).csv"
[ -f "$CSV" ] || echo "zaman,max_termal_c,pil_c,pil_mv,pil_yuzde,durum" > "$CSV"

# Thresholds (milli-units). Uyarı / Durdur
PIL_C_UYARI=42000;  PIL_C_DUR=45000
PIL_YUZDE_UYARI=25; PIL_YUZDE_DUR=15
OTURUM_SN=${1:-1800}
BASLANGIC=$(date +%s)
TERMAL_UYARI=80000; TERMAL_DUR=90000
PIL_MV_UYARI=3600;  PIL_MV_DUR=3450

olc() {
	# shellcheck disable=SC2016  # expands on the phone
	"${SSH[@]}" '
	m=0; for z in /sys/class/thermal/thermal_zone*/temp; do t=$(cat $z 2>/dev/null || echo 0); [ "$t" -gt "$m" ] && m=$t; done
	b=$(ls -d /sys/class/power_supply/*/ 2>/dev/null | grep -iE "bat" | head -1)
	pt=$(cat ${b}temp 2>/dev/null || echo -1)
	pv=$(cat ${b}voltage_now 2>/dev/null || echo -1)
	pc=$(cat ${b}capacity 2>/dev/null || echo -1)
	echo "$m $pt $pv $pc"'
}

while true; do
	if ! olcum=$(olc 2>/dev/null); then sleep 60; continue; fi
	read -r maxt pilt pilv pily <<< "$olcum"
	# power_supply temp is in 0.1 °C, voltage in µV
	pil_mc=$(( pilt >= 0 ? pilt * 100 : -1 ))
	pil_mv=$(( pilv >= 0 ? pilv / 1000 : -1 ))
	durum=normal
	if (( maxt >= TERMAL_UYARI || pil_mc >= PIL_C_UYARI || (pil_mv > 0 && pil_mv <= PIL_MV_UYARI) || (pily >= 0 && pily <= PIL_YUZDE_UYARI) )); then durum=uyari; fi
	if (( maxt >= TERMAL_DUR || pil_mc >= PIL_C_DUR || (pil_mv > 0 && pil_mv <= PIL_MV_DUR) || (pily >= 0 && pily <= PIL_YUZDE_DUR) )); then durum=durdur; fi
	echo "$(zaman),$((maxt / 1000)),$((pil_mc / 1000)),$pil_mv,$pily,$durum" >> "$CSV"
	if [ "$durum" = durdur ]; then
		eylem_kaydet "GÜVENLİK EŞİĞİ: termal=${maxt} pil=${pil_mc} mV=${pil_mv} → yük kesildi, bootloader"
		echo "$(zaman) güvenlik eşiği aşıldı (termal=$((maxt / 1000))C pil=$((pil_mc / 1000))C ${pil_mv}mV)" > "$LOG_DIR/DURUM"
		"${SSH[@]}" 'doas pkill -9 -f "stress|glmark|vkmark|make" ; sync; doas reboot-mode bootloader || doas reboot -f' || true
		exit 4
	fi
	if (( OTURUM_SN > 0 && $(date +%s) - BASLANGIC >= OTURUM_SN )); then
		eylem_kaydet "§3.1 oturum süresi (${OTURUM_SN} sn) doldu → bootloader"
		"${SSH[@]}" 'sync; doas systemctl reboot --reboot-argument=bootloader || doas reboot-mode bootloader' || true
		exit 5
	fi
	sleep 60
done
