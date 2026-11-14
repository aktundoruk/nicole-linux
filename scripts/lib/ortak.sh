# shellcheck shell=bash
# Common helpers for all project scripts. Source this file; do not execute it.
#
# Enforces the project contract (docs/guvenlik-kurallari.md):
#   - a `DUR` file in the project root stops every device-touching command
#   - every action is appended to the daily log
#   - forbidden fastboot operations are refused even if a script tries them

PROJE_KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PROJE_KOK
LOG_DIR="$PROJE_KOK/log"
EYLEM_LOG="$LOG_DIR/eylemler.log"
mkdir -p "$LOG_DIR"

# Where backups and large dumps go (project lives on the external SSD). Override with RAZER_YEDEK=/path
YEDEK_KOK="${RAZER_YEDEK:-$PROJE_KOK/yedek}"
export YEDEK_KOK

zaman() { date '+%Y-%m-%d %H:%M:%S'; }
damga() { date '+%Y%m%d-%H%M%S'; }

bilgi() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
uyari() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
hata()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

eylem_kaydet() { printf '%s\t%s\t%s\n' "$(zaman)" "${0##*/}" "$*" >> "$EYLEM_LOG"; }

dur_kontrol() {
	if [ -e "$PROJE_KOK/DUR" ]; then
		eylem_kaydet "DUR dosyası mevcut, işlem iptal"
		hata "DUR dosyası var ($PROJE_KOK/DUR). Cihaza dokunan işlemler durduruldu."
	fi
}

gerekli() {
	local t
	for t in "$@"; do
		command -v "$t" >/dev/null 2>&1 || hata "'$t' bulunamadı. Kurulum: README.md"
	done
}

# Minimum free space (GB) on the filesystem holding $1
bos_alan_kontrol() {
	local yol=$1 gerek_gb=$2 bos_kb
	mkdir -p "$yol"
	bos_kb=$(df -Pk "$yol" | awk 'NR==2 {print $4}')
	if [ $((bos_kb / 1024 / 1024)) -lt "$gerek_gb" ]; then
		hata "$yol üzerinde en az ${gerek_gb} GB boş alan gerekli (şu an $((bos_kb / 1024 / 1024)) GB). RAZER_YEDEK ile harici SSD gösterin."
	fi
}

# Partitions that must never be written (docs/guvenlik-kurallari.md §2, Seviye 4)
YASAK_BOLUMLER_RE='^(persist|modemst1|modemst2|fsg|fsc|xbl.*|xbl_config.*|abl.*|aop.*|tz.*|hyp.*|devcfg.*|keymaster.*|qupfw.*|uefisecapp.*|cpucp.*|shrm.*|storsec|devinfo|frp|misc|splash|ssd|ddr|cdt)$'
# Partitions allowed for Seviye 2 writes (only when approved in docs/guvenlik-kurallari.md)
# Slot düzeni (24 Ekim 2026): B = Android güvenlik ağı, A = bizim slotumuz
SEVIYE2_BOLUMLER_RE='^(boot_a|vendor_boot_a|dtbo_a|vbmeta_a)$'
# Faz 4 (docs/guvenlik-kurallari.md §8, 8 Kasım 2026): slot B becomes the Linux rescue system; its four boot
# partitions only, and only with RAZER_FAZ4_ONAY=evet (on top of Seviye 2)
FAZ4_BOLUMLER_RE='^(boot_b|vendor_boot_b|dtbo_b|vbmeta_b)$'

# Which phone is on the cable: Razer Edge's ABL answers `getvar product` with the SoC
# platform name "lahaina" (fastboot dump 24 Oct 2026). Other SM8350 phones may say the same,
# so this only stops writes to a clearly different phone; RAZER_URUN overrides it.
urun_kontrol() {
	local urun
	urun=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p' | head -1)
	[ "$urun" = "${RAZER_URUN:-lahaina}" ] ||
		hata "fastboot product '$urun', beklenen '${RAZER_URUN:-lahaina}': bu telefon Razer Edge (nicole) değil gibi, yazılmaz"
}

# Guarded fastboot wrapper. Scripts must call this instead of `fastboot`.
fb() {
	dur_kontrol
	# The subcommand is the first non-option argument: `fb --disable-verity flash X`
	# must be checked like `fb flash X` (options must not bypass the guard).
	local args=("$@") i=0 alt="" sonraki=""
	while [ $i -lt ${#args[@]} ]; do
		case "${args[$i]}" in
			-s|-S|--slot) i=$((i + 2)); continue ;;
			--set-active*|set_active) alt=${args[$i]}; break ;;
			-*) i=$((i + 1)); continue ;;
		esac
		alt=${args[$i]}; sonraki=${args[$((i + 1))]:-}
		break
	done
	case "$*" in *" -w"*|"-w"*|*--wipe*) hata "fastboot -w / --wipe sözleşme gereği yasak";; esac
	case "$alt" in
		erase|format|flashing|oem|"flash:raw"|update|flashall|flash-all|wipe-super|delete-logical-partition|resize-logical-partition|create-logical-partition)
			hata "fastboot $alt sözleşme gereği yasak (Seviye 4)";;
		flash)
			local bolum=$sonraki
			if [[ "$bolum" =~ $YASAK_BOLUMLER_RE ]]; then
				hata "fastboot flash $bolum: YASAK bölüm (Seviye 4)"
			fi
			if [[ "$bolum" =~ $FAZ4_BOLUMLER_RE ]]; then
				[ "${RAZER_FAZ4_ONAY:-}" = "evet" ] ||
					hata "fastboot flash $bolum: Faz 4 onayı yok (RAZER_FAZ4_ONAY=evet, docs/guvenlik-kurallari.md §8)"
			elif ! [[ "$bolum" =~ $SEVIYE2_BOLUMLER_RE ]]; then
				hata "fastboot flash $bolum: Seviye 3, Kullanıcı onayı gerekir"
			fi
			if [ "${RAZER_SEVIYE2_ONAY:-}" != "evet" ]; then
				hata "fastboot flash $bolum: Seviye 2 onayı yok (RAZER_SEVIYE2_ONAY=evet ve docs/guvenlik-kurallari.md onayı gerekir)"
			fi
			urun_kontrol;;
		--set-active=b|--set-active=_b)
			# Dar Seviye 2 izni (Kullanıcı, 24 Ekim 2026): yalnız B'ye (Android) geri dönüş
			urun_kontrol;;
		--set-active*|set_active)
			[ "${RAZER_SEVIYE2_ONAY:-}" = "evet" ] || hata "Slot değişimi Seviye 2 onayı ister (yalnız --set-active=b serbest)"
			urun_kontrol;;
	esac
	eylem_kaydet "fastboot $*"
	fastboot "$@"
}

# Guarded adb wrapper (logs every call)
ab() {
	dur_kontrol
	eylem_kaydet "adb $*"
	adb "$@"
}

# macOS holds back new USB accessories while the screen is locked: the phone enumerates
# but its NCM interface never gets a BSD name, so USB networking looks dead (2026-10-25,
# two "hangs" that were this). Every boot is a new accessory to macOS.
mac_kilitli() {
	[ "${RAZER_KILIT_DENETIMI:-evet}" = hayir ] && return 1   # mock tests
	command -v ioreg >/dev/null || return 1
	ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleUsers xml1 -o - - 2>/dev/null |
		grep -A1 CGSSessionScreenIsLocked | grep -q '<true/>'
}
mac_kilit_bekle() {
	mac_kilitli || return 0
	uyari "Mac ekranı kilitli: telefonun USB ağı kilit açılana kadar bağlanmaz. Kilit açılması bekleniyor"
	while mac_kilitli; do sleep 5; done
	bilgi "Mac kilidi açıldı"
}
