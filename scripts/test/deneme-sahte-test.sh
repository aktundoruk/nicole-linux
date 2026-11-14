#!/usr/bin/env bash
# Regression test for scripts/lab/deneme.sh WITHOUT the phone.
# Copies scripts/ into a temp project, puts fake fastboot/adb/imagesnap first in PATH
# and runs three scenarios:
#   basari     fastboot boot OK, a local telnet stand-in answers on 127.0.0.1:23  -> exit 0
#   kurtulma   no answer, the fake device comes back to fastboot by itself        -> exit 2
#   manuel     no answer and never comes back                                      -> exit 3 + log/DURUM
# Also checks that the guarded fb() refuses a forbidden command inside deneme's env.
# scripts/lab/yaz-dene.sh (flash to A + normal boot) scenarios:
#   yaz-dongu     A's image resets the phone until ABL falls back to Android B  -> exit 2
#   yaz-fastboot  ABL stays in fastboot on A                                     -> exit 2
#   yaz-linux     telnet answers, reboot-mode returns to fastboot, B restored    -> exit 0
#   yaz-onaysiz   no RAZER_SEVIYE2_ONAY                                          -> refused
# Usage: scripts/test/deneme-sahte-test.sh      (macOS, needs nc)
set -euo pipefail
export RAZER_KILIT_DENETIMI=hayir   # the real Mac may be locked while the mocks run
KOK="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/proje" "$T/bin"
cp -R "$KOK/scripts" "$T/proje/"
head -c 4096 /dev/urandom > "$T/sahte.img"

# Fake fastboot. "$S" holds where the device is (fastboot / kapali / android),
# "$S.slot" the ABL slot state: "<current> <unbootable_b> <successful_b> <unbootable_a>".
# Like the real ABL (2026-10-24), a rejected `fastboot boot` (SAHTE_ABL_RED=1) marks
# B unbootable and switches to A while staying in fastboot.
cat > "$T/bin/fastboot" <<'F'
#!/usr/bin/env bash
S="$SAHTE_DURUM"
echo "fastboot $*" >> "$S.log"
[ -f "$S.slot" ] || echo "b no yes no" > "$S.slot"
read -r cur ub sb ua < "$S.slot"
case "$1" in
	devices) [ "$(cat "$S")" = fastboot ] && printf 'SAHTE123\tfastboot\n'; exit 0 ;;
	getvar)
		case "$2" in
			product) echo "product: ${SAHTE_URUN:-lahaina}" >&2 ;;
			battery-voltage) echo "battery-voltage: 3950" >&2 ;;
			current-slot) echo "current-slot: $cur" >&2 ;;
			slot-unbootable:b) echo "slot-unbootable:b: $ub" >&2 ;;
			slot-successful:b) echo "slot-successful:b: $sb" >&2 ;;
			slot-unbootable:a) echo "slot-unbootable:a: $ua" >&2 ;;
			slot-retry-count:a) echo "slot-retry-count:a: 7" >&2 ;;
		esac; echo "Finished." >&2; exit 0 ;;
	flash) echo "Writing '$2'  OKAY" >&2; exit 0 ;;
	--set-active=a) echo "a $ub $sb no" > "$S.slot"; echo "Setting current slot to 'a'  OKAY" >&2; exit 0 ;;
	boot)
		echo "Sending 'boot.img'  OKAY" >&2
		if [ -n "${SAHTE_ABL_RED:-}" ]; then
			echo "a yes yes no" > "$S.slot"
			echo "Booting  FAILED (remote: 'Failed to load/authenticate boot image: Load Error')" >&2
			exit 1
		fi
		echo kapali > "$S"
		# kurtulma scenario: back to fastboot after SAHTE_DONUS_SN seconds
		if [ -n "${SAHTE_DONUS_SN:-}" ]; then ( sleep "$SAHTE_DONUS_SN"; echo fastboot > "$S" ) & fi
		echo "Booting  OKAY" >&2; exit 0 ;;
	--set-active=b) echo "b no no $ua" > "$S.slot"; echo "Setting current slot to 'b'  OKAY" >&2; exit 0 ;;
	reboot)
		if [ "${2:-}" = bootloader ]; then echo fastboot > "$S"
		elif [ "$cur" = a ] && [ -n "${SAHTE_A_SONUC:-}" ]; then
			# normal boot from slot A (yaz-dene.sh)
			case "$SAHTE_A_SONUC" in
				dongu) echo kapali > "$S"; ( sleep 4; echo "b no yes yes" > "$S.slot"; echo android > "$S" ) & ;;
				fastboot) echo fastboot > "$S" ;;
				linux) echo kapali > "$S"; ( sleep 20; echo fastboot > "$S" ) & ;;
			esac
		elif [ -n "${SAHTE_ANDROID_YOK:-}" ]; then echo kapali > "$S"; else echo android > "$S"; fi
		echo "Rebooting  OKAY" >&2; exit 0 ;;
	*) echo "sahte fastboot: beklenmeyen $*" >&2; exit 1 ;;
esac
F
# Fake adb: answers only while the fake device is in "android"; a booted Android marks B successful.
cat > "$T/bin/adb" <<'A'
#!/usr/bin/env bash
S="$SAHTE_DURUM"
echo "adb $*" >> "$S.log"
yer=$(cat "$S")
case "$1" in
	get-state) [ "$yer" = android ] && echo device || echo unknown; exit 0 ;;
	shell)
		[ "$yer" = android ] || exit 1
		case "$*" in
			*sys.boot_completed*) read -r cur ub sb ua < "$S.slot"; echo "$cur $ub yes $ua" > "$S.slot"; echo 1 ;;
			*ro.boot.slot_suffix*) echo _b ;;
		esac; exit 0 ;;
	reboot) [ "$2" = bootloader ] && echo fastboot > "$S"; exit 0 ;;
esac
exit 0
A
printf '#!/bin/sh\n# sahte imagesnap: son argüman dosya yolu\nfor a; do f=$a; done\n: > "$f"\n' > "$T/bin/imagesnap"
chmod +x "$T/bin/"*

hata=0
kontrol() { # $1 ad, $2 beklenen, $3 gercek
	if [ "$2" = "$3" ]; then echo "  OK   $1 (exit $3)"; else echo "  HATA $1: beklenen $2, gelen $3"; hata=1; fi
}
calistir() { # $1 senaryo  -> exit code
	local rc=0 ad=$1
	shift
	# own state file per scenario: a late background "back to fastboot" from the
	# previous scenario must not leak into this one
	echo fastboot > "$T/durum-$ad"
	rm -f "$T/proje/log/DURUM"
	PATH="$T/bin:$PATH" SAHTE_DURUM="$T/durum-$ad" RAZER_IP=127.0.0.1 \
		RAZER_KENDILIGINDEN_SN=12 "$@" bash "$T/proje/scripts/lab/deneme.sh" "$T/sahte.img" "test-$ad" 25 \
		> "$T/$ad.out" 2>&1 || rc=$?
	echo "$rc"
}

echo "senaryo basari"
# telnet stand-in on :23 (macOS refuses an explicit 127.0.0.1 bind below 1024
# for normal users, the wildcard bind works)
( while true; do printf 'Linux nicole 7.3.0-rc6\n' | nc -l 23 >/dev/null 2>&1 || break; done ) &
sleep 1
rc=$(calistir basari env); kontrol basari 0 "$rc"
kill %1 2>/dev/null || true
pkill -f '^nc -l 23$' 2>/dev/null || true
sleep 1
nc -z -G 1 127.0.0.1 23 2>/dev/null && { echo "  HATA telnet taklidi kapanmadı"; hata=1; }
grep -q "fastboot boot" "$T/durum-basari.log" || { echo "  HATA fastboot boot çağrılmadı"; hata=1; }

echo "senaryo kurtulma"
rc=$(calistir kurtulma env SAHTE_DONUS_SN=20); kontrol kurtulma 2 "$rc"
[ -f "$T/proje/log/DURUM" ] && { echo "  HATA kurtulmada DURUM yazılmamalı"; hata=1; }

echo "senaryo manuel"
rc=$(calistir manuel env); kontrol manuel 3 "$rc"
if grep -q MANUEL_RESET "$T/proje/log/DURUM" 2>/dev/null; then echo "  OK   log/DURUM yazıldı: $(cat "$T/proje/log/DURUM")"; else echo "  HATA log/DURUM yok"; hata=1; fi

echo "senaryo slot-bozuldu (ABL reddeder, B'yi işaretler; betik B'yi geri getirir)"
rc=$(calistir slot env SAHTE_ABL_RED=1); kontrol slot-bozuldu 2 "$rc"
grep -q "fastboot --set-active=b" "$T/durum-slot.log" && echo "  OK   --set-active=b çağrıldı" || { echo "  HATA --set-active=b yok"; hata=1; }
if [ "$(cat "$T/durum-slot.slot")" = "b no yes no" ]; then echo "  OK   son slot durumu: B aktif, açılabilir, Android açıldı"
else echo "  HATA son slot durumu: $(cat "$T/durum-slot.slot")"; hata=1; fi
grep -q "Load Error" "$T/proje/log/denemeler/ozet.tsv" && echo "  OK   ABL cevabı özete yazıldı" || { echo "  HATA ABL cevabı özette yok"; hata=1; }
[ -f "$T/proje/log/DURUM" ] && { echo "  HATA slot-bozuldu'da DURUM yazılmamalı"; hata=1; }

echo "senaryo b-acilmiyor (B geri getirilir ama Android açılmaz → dur)"
rc=$(calistir bacilmiyor env SAHTE_ABL_RED=1 SAHTE_ANDROID_YOK=1 RAZER_ANDROID_BEKLE_SN=4); kontrol b-acilmiyor 3 "$rc"
if grep -q "Android açılmadı" "$T/proje/log/DURUM" 2>/dev/null; then echo "  OK   log/DURUM: $(cat "$T/proje/log/DURUM")"; else echo "  HATA log/DURUM yok/yanlış"; hata=1; fi

echo "slot korumaları"
for k in "--set-active=a" "set_active a"; do
	if PATH="$T/bin:$PATH" SAHTE_DURUM="$T/durum-koruma" bash -c "source '$T/proje/scripts/lib/ortak.sh'; fb $k" >/dev/null 2>&1; then
		echo "  HATA fb $k onaysız geçti"; hata=1
	else echo "  OK   fb $k onaysız reddedildi"; fi
done
echo fastboot > "$T/durum-koruma"
if PATH="$T/bin:$PATH" SAHTE_DURUM="$T/durum-koruma" bash -c "source '$T/proje/scripts/lib/ortak.sh'; fb --set-active=b" >/dev/null 2>&1; then
	echo "  OK   fb --set-active=b (dar izin) geçti"
else echo "  HATA fb --set-active=b reddedildi"; hata=1; fi

yaz_calistir() { # $1 senaryo, rest: env assignments -> exit code
	local rc=0 ad=$1
	shift
	echo fastboot > "$T/durum-$ad"
	rm -f "$T/proje/log/DURUM"
	PATH="$T/bin:$PATH" SAHTE_DURUM="$T/durum-$ad" RAZER_IP=127.0.0.1 RAZER_KENDILIGINDEN_SN=12 \
		RAZER_ANDROID_BEKLE_SN=8 "$@" bash "$T/proje/scripts/lab/yaz-dene.sh" --boot "$T/sahte.img" \
		--vendor-boot "$T/sahte.img" "test-$ad" 30 > "$T/$ad.out" 2>&1 || rc=$?
	echo "$rc"
}
echo "senaryo yaz-dongu (A sıfırlanır, ABL B'ye döner)"
rc=$(yaz_calistir yazdongu env RAZER_SEVIYE2_ONAY=evet SAHTE_A_SONUC=dongu); kontrol yaz-dongu 2 "$rc"
grep -q "fastboot flash boot_a" "$T/durum-yazdongu.log" && grep -q "fastboot flash vendor_boot_a" "$T/durum-yazdongu.log" \
	&& echo "  OK   boot_a + vendor_boot_a yazıldı" || { echo "  HATA flash çağrıları eksik"; hata=1; }
grep -q "yaz:android_b" "$T/proje/log/denemeler/ozet.tsv" && echo "  OK   sonuç android_b" || { echo "  HATA sonuç android_b değil"; hata=1; }
[ "$(cat "$T/durum-yazdongu.slot" | cut -d' ' -f1-2)" = "b no" ] && echo "  OK   B aktif" || { echo "  HATA slot: $(cat "$T/durum-yazdongu.slot")"; hata=1; }
echo "senaryo yaz-fastboot (ABL A'da fastboot'ta kalır)"
rc=$(yaz_calistir yazfb env RAZER_SEVIYE2_ONAY=evet SAHTE_A_SONUC=fastboot); kontrol yaz-fastboot 2 "$rc"
grep -q "fastboot --set-active=b" "$T/durum-yazfb.log" && echo "  OK   --set-active=b çağrıldı" || { echo "  HATA --set-active=b yok"; hata=1; }
echo "senaryo yaz-linux (telnet cevap verir)"
( while true; do printf 'Linux nicole 7.3.0-rc6\n' | nc -l 23 >/dev/null 2>&1 || break; done ) &
sleep 1
rc=$(yaz_calistir yazlinux env RAZER_SEVIYE2_ONAY=evet SAHTE_A_SONUC=linux); kontrol yaz-linux 0 "$rc"
kill %1 2>/dev/null || true
pkill -f '^nc -l 23$' 2>/dev/null || true
grep -q "fastboot --set-active=b" "$T/durum-yazlinux.log" && echo "  OK   Linux sonrası B geri alındı" || { echo "  HATA Linux sonrası B alınmadı"; hata=1; }
echo "senaryo yaz-onaysiz"
rc=$(yaz_calistir yazonaysiz env SAHTE_A_SONUC=dongu); kontrol yaz-onaysiz 1 "$rc"
grep -q "flash" "$T/durum-yazonaysiz.log" 2>/dev/null && { echo "  HATA onaysız flash çağrıldı"; hata=1; } || echo "  OK   onaysız hiçbir şey yazılmadı"

echo "özet tablosu:"; sed 's/^/  /' "$T/proje/log/denemeler/ozet.tsv"
echo "koruma (fb erase) testi"
if PATH="$T/bin:$PATH" bash -c "source '$T/proje/scripts/lib/ortak.sh'; fb erase boot_a" >/dev/null 2>&1; then
	echo "  HATA fb erase reddedilmedi"; hata=1
else echo "  OK   fb erase reddedildi"; fi
cat "$T"/durum-*.log | grep -q "erase" && { echo "  HATA sahte fastboot'a erase ulaştı"; hata=1; }
[ "$hata" = 0 ] && echo "SONUÇ: GEÇTİ" || { echo "SONUÇ: BAŞARISIZ"; for f in "$T"/*.out; do echo "--- $f"; tail -5 "$f"; done; exit 1; }
