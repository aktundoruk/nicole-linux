# shellcheck shell=bash
# Device helpers shared by scripts/lab/deneme.sh (RAM boot) and scripts/lab/yaz-dene.sh
# (flash to slot A). Source after lib/ortak.sh; callers set D (attempt log directory).
#   fastboot_var / fastboot_bekle N   device in ABL fastboot (now / within N s)
#   fastboot_a_don                    back to fastboot by itself or via Android (adb)
#   gv VAR, slot_durumu, b_saglam_mi  ABL slot state; B must be active and bootable
#   android_bekle N, b_geri_getir     restore B (narrow --set-active=b permission)
#   pil_bekle                         docs/guvenlik-kurallari.md §3.1 battery threshold

fastboot_var() { fastboot devices 2>/dev/null | grep -q fastboot; }

fastboot_bekle() { # seconds
	local i
	for ((i = 0; i < $1; i++)); do fastboot_var && return 0; sleep 1; done
	return 1
}

# Recovery without a button rig (user decision 2026-10-05): wait for the device to
# recover by itself (panic=30 / watchdog → slot B Android → adb reboot bootloader).
# If it does not, write log/DURUM and exit 3; the phone then needs a forced restart
# by hand (hold Power, docs/geri-donus.md).
KENDILIGINDEN_SN=${RAZER_KENDILIGINDEN_SN:-420}
fastboot_a_don() {
	local i
	for ((i = 0; i < KENDILIGINDEN_SN; i += 5)); do
		fastboot_var && return 0
		if command -v adb >/dev/null && [ "$(adb get-state 2>/dev/null)" = "device" ]; then
			bilgi "Cihaz Android'e düştü, fastboot'a alınıyor"
			ab reboot bootloader; fastboot_bekle 90 && return 0
		fi
		sleep 5
	done
	return 1
}

# Slot state (2026-10-24): this ABL marks the active slot "unbootable" and switches
# slots when a `fastboot boot` fails. B (stock Android) must be active and bootable
# before every attempt; Claude may restore it with --set-active=b (narrow Seviye 2
# approval, docs/guvenlik-kurallari.md §2) and then boots Android once to prove the safety net.
gv() { fastboot getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }
slot_durumu() { printf 'aktif=%s b_acilamaz=%s b_basarili=%s a_acilamaz=%s' \
	"$(gv current-slot)" "$(gv slot-unbootable:b)" "$(gv slot-successful:b)" "$(gv slot-unbootable:a)"; }
b_saglam_mi() { # a freshly started ABL may answer the first getvar with nothing: retry
	local i s u
	for i in 1 2 3; do
		s=$(gv current-slot); u=$(gv slot-unbootable:b)
		if [ -n "$s" ] && [ -n "$u" ]; then [ "$s" = "b" ] && [ "$u" = "no" ]; return; fi
		sleep 2
	done
	return 1
}
android_bekle() { # seconds -> 0 when Android finished booting
	local i
	for ((i = 0; i < $1; i += 2)); do
		[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && return 0
		sleep 2
	done
	return 1
}
b_geri_getir() {
	uyari "Slot durumu bozuk ($(slot_durumu)); B yeniden etkinleştiriliyor"
	fb --set-active=b >> "$D/slot.txt" 2>&1 || return 1
	fb reboot >> "$D/slot.txt" 2>&1 || return 1
	if ! android_bekle "${RAZER_ANDROID_BEKLE_SN:-240}"; then
		echo "$(zaman) DUR: --set-active=b sonrası B'deki Android açılmadı ($D)" > "$LOG_DIR/DURUM"
		uyari "B'deki Android açılmadı → log/DURUM (docs/guvenlik-kurallari.md §4 madde 3)"
		return 1
	fi
	bilgi "Android B'den açıldı ($(adb shell getprop ro.boot.slot_suffix | tr -d '\r')); fastboot'a dönülüyor"
	ab reboot bootloader; fastboot_bekle 90 || return 1
	echo "geri getirme sonrası: $(slot_durumu)" >> "$D/slot.txt"
	b_saglam_mi
}

# docs/guvenlik-kurallari.md §3.1: no attempt below 3.8 V; wait in fastboot (ABL charges) up to 2 h
pil_mv() { fastboot getvar battery-voltage 2>&1 | sed -n 's/^battery-voltage: *\([0-9]*\).*/\1/p' | head -1; }
pil_bekle() {
	local v bekleme
	local PIL_ESIK=${RAZER_PIL_ESIK_MV:-3800}
	v=$(pil_mv)
	if [ -z "$v" ]; then
		uyari "Bootloader pil voltajı vermiyor; §3.1 için manuel takip gerekir"
	else
		echo "pil_mv_once: $v" >> "$D/bilgi.txt"
		bekleme=0
		while [ "$v" -lt "$PIL_ESIK" ]; do
			(( bekleme >= 7200 )) && { echo "$(zaman) pil ${v}mV, 2 saatte ${PIL_ESIK}mV'a çıkmadı" > "$LOG_DIR/DURUM"; hata "Pil şarj olmuyor (${v} mV) → log/DURUM"; }
			bilgi "Pil ${v} mV < ${PIL_ESIK} mV, fastboot'ta şarj bekleniyor"
			sleep 300; bekleme=$((bekleme + 300)); v=$(pil_mv); v=${v:-0}
		done
	fi
}
