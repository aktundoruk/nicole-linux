#!/usr/bin/env bash
# QEMU smoke test for the kernel + mini initramfs, without the phone (inside the VM).
#
# Boots $WORK/out/latest/Image.gz on "qemu -M virt" (TCG) with a TEST COPY of
# initramfs-mini.cpio.gz that additionally:
#   - insmods dummy_hcd (virtual UDC) and the host-side usbnet/cdc_ncm/cdc_acm drivers
#     before the normal /init logic runs, so the real gadget code path is exercised
#   - after the gadget is up: runs udhcpc on the host-side interface (proves the
#     NCM link + udhcpd), checks that telnetd listens on 172.16.42.1:23 and that
#     /dev/ttyGS0 exists, then prints SMOKE lines and powers off
# The nicole DTB is NOT used (QEMU generates its own); this only tests the kernel
# config + /init script. The real initramfs is not modified.
#
# Usage: qemu-smoke.sh [--timeout SEC] [--usbnet ncm|ecm|rndis]   exit 0 = all checks passed
set -euo pipefail

WORK="${WORK:-/mnt/lima-razer-build}"
ART="$WORK/out/latest"
INITRD="$WORK/out/initramfs-mini.cpio.gz"
TIMEOUT=240
USBNET=ncm

die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--timeout) TIMEOUT="${2:?}"; shift ;;
		--usbnet) USBNET="${2:?}"; shift ;;
		-h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done

command -v qemu-system-aarch64 >/dev/null || die "qemu-system-aarch64 missing (sudo apt install qemu-system-arm)"
[ -f "$ART/Image.gz" ] || die "no kernel at $ART (run build-kernel.sh)"
[ -f "$INITRD" ] || die "no $INITRD (run mkinitramfs-mini.sh)"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir "$T/root"
gzip -dc "$ART/Image.gz" > "$T/Image"
# Only /init is extracted (device nodes need root); the test files go into a
# second cpio appended to the original one - the kernel unpacks both in order,
# so the patched /init overrides the original.
( cd "$T/root" && gzip -dc "$INITRD" | cpio -id --quiet init )

# Modules (in dependency order, resolved from modules.dep)
MODROOT="$(find "$ART/modules-root/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[ -n "$MODROOT" ] || die "no modules-root in $ART"
mkdir -p "$T/root/lib/smoke"
order=()
add_mod() {	# $1 = path relative to MODROOT, deps first
	local m="$1" d
	for d in $(awk -v m="$m:" '$1 == m { for (i = 2; i <= NF; i++) print $i }' "$MODROOT/modules.dep"); do
		add_mod "$d"
	done
	case " ${order[*]-} " in *" $m "*) ;; *) order+=("$m") ;; esac
}
for name in dummy_hcd usbnet cdc_ether cdc_ncm rndis_host cdc-acm; do
	rel="$(awk -F: -v n="/$name.ko" 'index($1, n) { print $1; exit }' "$MODROOT/modules.dep")"
	[ -n "$rel" ] || rel="$(awk -F: -v n="/${name//-/_}.ko" 'index($1, n) { print $1; exit }' "$MODROOT/modules.dep")"
	if [ -z "$rel" ]; then
		case "$name" in
			rndis_host) info "rndis_host not built: --usbnet rndis cannot be checked"; continue ;;
		esac
		die "module $name not built (CONFIG_USB_DUMMY_HCD=m in razer.config?)"
	fi
	add_mod "$rel"
done
i=0
for m in "${order[@]}"; do
	i=$((i + 1))
	dst="$T/root/lib/smoke/$(printf '%02d' "$i")-$(basename "${m%.zst}")"
	dst="${dst%.xz}"
	# modules may be compressed (CONFIG_MODULE_COMPRESS_ZSTD for pmOS); busybox insmod
	# wants a plain .ko
	case "$m" in
		*.zst) zstd -dqf "$MODROOT/$m" -o "$dst" ;;
		*.xz) xz -dc "$MODROOT/$m" > "$dst" ;;
		*) cp "$MODROOT/$m" "$dst" ;;
	esac
done
info "test modules: $(ls "$T/root/lib/smoke" | tr '\n' ' ')"

# Hook 1: load modules right after the mounts (before the UDC wait loop)
awk '
	{ print }
	/^mount -t debugfs/ && !done {
		print "for m in /lib/smoke/*.ko; do insmod \"$m\" && echo \"SMOKE insmod $(basename $m) ok\" > /dev/console || echo \"SMOKE insmod $(basename $m) FAIL\" > /dev/console; done"
		done = 1
	}' "$T/root/init" > "$T/init.1"
# Hook 2: checks right before the heartbeat loop, then power off
awk '
	/^while true; do$/ && !done {
		print "sleep 3"
		print "H=\"\"; for n in /sys/class/net/*; do n=${n##*/}; [ \"$n\" != lo ] && [ \"$n\" != \"$IFACE\" ] && H=$n; done"
		print "echo \"SMOKE udc=${UDC:-none} net=${NET:-none} gadget_if=${IFACE:-none} host_if=${H:-none}\" > /dev/console"
		print "if [ -n \"$H\" ]; then ifconfig $H up; udhcpc -n -q -t 5 -i $H -s /bin/true 2>&1 | grep -q \"lease of 172.16.42.2\" && echo \"SMOKE dhcp OK (172.16.42.2 leased over USB)\" > /dev/console || echo \"SMOKE dhcp FAIL\" > /dev/console; fi"
		print "netstat -ltn 2>/dev/null | grep -q \"172.16.42.1:23\" && echo \"SMOKE telnetd OK\" > /dev/console || echo \"SMOKE telnetd FAIL\" > /dev/console"
		print "[ -e /dev/ttyGS0 ] && echo \"SMOKE acm OK\" > /dev/console || echo \"SMOKE acm FAIL\" > /dev/console"
		print "[ -e /dev/watchdog ] && echo \"SMOKE watchdog present\" > /dev/console || echo \"SMOKE watchdog absent (expected in QEMU)\" > /dev/console"
		print "echo SMOKE done > /dev/console"
		print "poweroff -f"
		done = 1
	}
	{ print }' "$T/init.1" > "$T/root/init"
chmod 0755 "$T/root/init"
sh -n "$T/root/init" || die "patched init has a syntax error"
{
	cat "$INITRD"
	( cd "$T/root" && find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --quiet --owner=0:0 ) | gzip -9
} > "$T/initrd.gz"

info "booting under QEMU (TCG, timeout ${TIMEOUT}s)"
timeout "$TIMEOUT" qemu-system-aarch64 -M virt -cpu max -accel tcg -smp 2 -m 2048 \
	-nographic -no-reboot -kernel "$T/Image" -initrd "$T/initrd.gz" \
	-append "console=ttyAMA0 loglevel=4 panic=30 nicole.usbnet=$USBNET" > "$T/qemu.log" 2>&1 || true

grep -E "SMOKE|nicole-init|Kernel panic" "$T/qemu.log" || true
LOG_OUT="${SMOKE_LOG:-$WORK/out/qemu-smoke-$USBNET.log}"
cp "$T/qemu.log" "$LOG_OUT"
info "full log: $LOG_OUT"
if grep -q "SMOKE done" "$T/qemu.log" && ! grep -q "SMOKE .*FAIL\|Kernel panic" "$T/qemu.log"; then
	info "PASS"
	exit 0
fi
printf '\033[1;31m[x]\033[0m FAIL\n' >&2
exit 1
