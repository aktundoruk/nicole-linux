#!/usr/bin/env bash
# Build a tiny busybox initramfs for the first nicole boot attempts (docs/boot-plani.md §5.2).
#
# What the generated /init does on the phone:
#   - mounts proc/sys/devtmpfs/devpts/configfs/debugfs/tmpfs
#   - waits up to 60 s for a UDC, then creates a configfs gadget:
#       NCM (or ECM/RNDIS fallback) + CDC-ACM, VID:PID 1d6b:0104
#   - usb0 = 172.16.42.1/24, udhcpd hands 172.16.42.2 to the Mac
#   - telnetd on 172.16.42.1:23 (or "nc -ll -e" fallback) and a shell on /dev/ttyGS0
#   - prints a heartbeat line to the framebuffer console every 10 s (webcam-friendly)
#   - cmdline "nicole.sinyal=reboot": reboot immediately (proves userspace was reached)
#   - cmdline "nicole.sinyal=bootloader": reboot into ABL fastboot (reboot-mode helper)
#   - cmdline "nicole.oto_donus=N": back to fastboot if no telnet session (/tmp/oturum)
#     after N s
#   - cmdline "nicole.ufsro": every sd* (internal UFS) is set read-only as soon as it
#     appears, root= is ignored (Faz 3 firmware extraction, scripts/lab/ufs-oku.sh)
#   - cmdline "nicole.usbnet=ecm|rndis|ncm": force the USB network function
#   - cmdline "root=..." (without "nicole.kabuk"): try switch_root into that rootfs
# Everything the init needs must be built into the kernel (razer.config does that).
#
# Usage: mkinitramfs-mini.sh [-o OUTPUT]   (default: $WORK/out/initramfs-mini.cpio.gz)
set -euo pipefail

WORK="${WORK:-/mnt/lima-razer-build}"
OUT="$WORK/out/initramfs-mini.cpio.gz"

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		-o) OUT="${2:?}"; shift ;;
		-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done

command -v fakeroot >/dev/null || die "fakeroot missing (run vm-setup.sh)"
command -v cpio >/dev/null || die "cpio missing (run vm-setup.sh)"
BB=""
for c in /usr/bin/busybox /bin/busybox "$(command -v busybox || true)"; do
	[ -n "$c" ] && [ -x "$c" ] && { BB="$c"; break; }
done
[ -n "$BB" ] || die "busybox not found (apt install busybox-static)"
if ! file -L "$BB" | grep -q 'statically linked'; then
	die "$BB is not static; install busybox-static"
fi
case "$(file -L "$BB")" in
	*aarch64*) ;;
	*) die "$BB is not an aarch64 binary (build inside the arm64 VM)" ;;
esac

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE"/{bin,sbin,usr/bin,usr/sbin,proc,sys,dev,tmp,newroot,mnt,etc,root,run}
cp "$BB" "$STAGE/bin/busybox"

# reboot-mode: busybox `reboot` cannot pass a reboot command. This helper calls
# reboot(2) with LINUX_REBOOT_CMD_RESTART2 and e.g. "bootloader", which the kernel's
# nvmem-reboot-mode driver writes to the PMK8350 SDAM cell so ABL stops in fastboot.
# Needed when we run from slot A: a plain reboot would start A's old Android.
if command -v gcc >/dev/null; then
	cat > "$STAGE/reboot-mode.c" <<'C'
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/reboot.h>
int main(int argc, char **argv)
{
	const char *mode = argc > 1 ? argv[1] : "bootloader";
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, mode);
	perror("reboot");
	return 1;
}
C
	gcc -static -Os -o "$STAGE/bin/reboot-mode" "$STAGE/reboot-mode.c" && strip "$STAGE/bin/reboot-mode"
	rm -f "$STAGE/reboot-mode.c"
else
	echo "warning: gcc missing, no reboot-mode helper in the initramfs" >&2
fi

cat > "$STAGE/init" <<'INIT'
#!/bin/busybox sh
# nicole mini initramfs - PID 1
/bin/busybox --install -s
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /tmp
mount -t configfs configfs /sys/kernel/config 2>/dev/null
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null

CMDLINE="$(cat /proc/cmdline)"
log() {
	echo "[nicole-init] $*" > /dev/kmsg 2>/dev/null
	echo "[nicole-init] $*" > /dev/tty0 2>/dev/null
}
has() { case " $CMDLINE " in *" $1 "*) return 0 ;; esac; return 1; }
getarg() {
	for a in $CMDLINE; do
		case "$a" in "$1"=*) echo "${a#*=}"; return 0 ;; esac
	done
	return 1
}

log "mini initramfs up, kernel $(uname -r)"
# Faz 3 extraction (docs/guvenlik-kurallari.md §8, scripts/lab/ufs-oku.sh): every internal UFS disk is
# made read-only the moment it appears. BLKROSET on the whole disk also covers its
# partitions (bdev_read_only checks the disk). Nothing here ever writes sd*; this is
# the second line of defence. The root= path below is disabled in this mode.
if has nicole.ufsro; then
	(
		while true; do
			for b in /sys/block/sd*; do
				[ -e "$b" ] || continue
				n=${b##*/}
				if [ "$(cat "$b/ro")" != 1 ]; then
					blockdev --setro "/dev/$n" && log "ufsro: /dev/$n read-only"
				fi
			done
			sleep 0.2
		done
	) &
	log "ufsro: guard running"
fi
# Hardware watchdog: if the kernel or this init hangs, the APSS watchdog bites
# and the device reboots by itself (docs/guvenlik-kurallari.md: fewer manual resets).
if [ -e /dev/watchdog ] && ! has nicole.watchdog=0; then
	watchdog -T 60 -t 10 /dev/watchdog && log "watchdog armed (60 s)"
fi
if has nicole.sinyal=reboot; then
	log "nicole.sinyal=reboot -> rebooting (userspace reached)"
	sleep 2
	echo 1 > /proc/sys/kernel/sysrq
	echo b > /proc/sysrq-trigger
fi
# Proof of life without display or USB: back to ABL fastboot (via the PMK8350 SDAM
# reboot reason). If the phone returns to fastboot within ~20 s, userspace ran.
if has nicole.sinyal=bootloader; then
	log "nicole.sinyal=bootloader -> reboot-mode bootloader (userspace reached)"
	sleep 3
	/bin/reboot-mode bootloader
	log "reboot-mode failed, falling back to sysrq reboot"
	echo 1 > /proc/sys/kernel/sysrq
	echo b > /proc/sysrq-trigger
fi

IP=172.16.42.1
CLIENT=172.16.42.2
G=/sys/kernel/config/usb_gadget/g1
UDC=""
NET=""
IFACE=""

i=0
while [ -z "$(ls /sys/class/udc 2>/dev/null)" ] && [ "$i" -lt 60 ]; do
	sleep 1
	i=$((i + 1))
done
UDC="$(ls /sys/class/udc 2>/dev/null | head -n1)"

if [ -n "$UDC" ] && [ -d /sys/kernel/config/usb_gadget ]; then
	mkdir -p "$G"
	echo 0x1d6b > "$G/idVendor"     # Linux Foundation
	echo 0x0104 > "$G/idProduct"    # Multifunction Composite Gadget
	echo 0x0200 > "$G/bcdUSB"
	mkdir -p "$G/strings/0x409"
	echo "Razer" > "$G/strings/0x409/manufacturer"
	echo "Razer Edge nicole (mainline mini initramfs)" > "$G/strings/0x409/product"
	echo "nicole-mini" > "$G/strings/0x409/serialnumber"
	mkdir -p "$G/configs/c.1/strings/0x409"
	echo "net+acm" > "$G/configs/c.1/strings/0x409/configuration"

	order="ncm ecm rndis"
	want="$(getarg nicole.usbnet || true)"
	[ -n "$want" ] && order="$want $order"
	for f in $order; do
		if mkdir "$G/functions/$f.usb0" 2>/dev/null; then NET="$f"; break; fi
	done
	[ -n "$NET" ] && ln -s "$G/functions/$NET.usb0" "$G/configs/c.1/"
	if mkdir "$G/functions/acm.GS0" 2>/dev/null; then
		ln -s "$G/functions/acm.GS0" "$G/configs/c.1/"
	fi
	echo "$UDC" > "$G/UDC"
	sleep 1

	if [ -n "$NET" ]; then
		IFACE="$(cat "$G/functions/$NET.usb0/ifname" 2>/dev/null || echo usb0)"
		ifconfig "$IFACE" "$IP" netmask 255.255.255.0 up
		cat > /tmp/udhcpd.conf <<EOF
start $CLIENT
end $CLIENT
interface $IFACE
max_leases 1
lease_file /tmp/udhcpd.leases
option subnet 255.255.255.0
option lease 3600
EOF
		touch /tmp/udhcpd.leases
		udhcpd /tmp/udhcpd.conf
		if busybox --list | grep -qx telnetd; then
			telnetd -b "$IP:23" -l /bin/sh
		else
			( while true; do nc -ll -p 23 -e /bin/sh; sleep 1; done ) &
		fi
	fi
	if [ -e /dev/ttyGS0 ]; then
		( while true; do setsid sh -c 'exec sh </dev/ttyGS0 >/dev/ttyGS0 2>&1'; sleep 1; done ) &
	fi
	log "USB gadget on $UDC: net=${NET:-none} iface=${IFACE:-none} ip=$IP acm=$([ -e /dev/ttyGS0 ] && echo yes || echo no)"
else
	log "no UDC after 60 s - USB gadget not available (check dwc3/phy in dmesg on screen)"
fi

ROOT="$(getarg root || true)"
if [ -n "$ROOT" ] && ! has nicole.kabuk && ! has nicole.ufsro; then
	log "trying root=$ROOT"
	dev=""
	i=0
	while [ -z "$dev" ] && [ "$i" -lt 30 ]; do
		case "$ROOT" in
			PARTUUID=*|UUID=*|LABEL=*) dev="$(findfs "$ROOT" 2>/dev/null || true)" ;;
			*) [ -b "$ROOT" ] && dev="$ROOT" ;;
		esac
		[ -z "$dev" ] && sleep 1
		i=$((i + 1))
	done
	if [ -n "$dev" ] && mount -o rw "$dev" /newroot && [ -x /newroot/sbin/init ]; then
		log "switch_root to $dev"
		exec switch_root /newroot /sbin/init
	fi
	log "root=$ROOT not usable, staying in initramfs"
fi

# "nicole.oto_donus=N": if nobody has logged in (the Mac's lab scripts touch
# /tmp/oturum over telnet) N s after boot, go back to ABL fastboot by itself instead
# of waiting for a manual reset (2026-10-25: kernel alive, Mac never got the NCM link).
OTO="$(getarg nicole.oto_donus || true)"
while true; do
	up="$(cut -d' ' -f1 /proc/uptime)"
	echo "[nicole-init] alive up=${up}s net=${NET:-none} ip=$IP udc=${UDC:-none}" > /dev/tty0 2>/dev/null
	if [ -n "$OTO" ] && [ ! -e /tmp/oturum ] && [ "${up%.*}" -gt "$OTO" ]; then
		log "no session after ${OTO}s (nicole.oto_donus) -> reboot-mode bootloader"
		# post-mortem for the Mac: dmesg onto the microSD boot partition (pmOS_boot,
		# ext2), read later from pmOS or the next mini boot
		if [ -b /dev/mmcblk1p1 ] && mount /dev/mmcblk1p1 /mnt 2>/dev/null; then
			mkdir -p /mnt/nicole-log
			dmesg > "/mnt/nicole-log/dmesg-oto-donus-${up%.*}s.txt"
			umount /mnt
			log "dmesg saved to mmcblk1p1:/nicole-log/"
		fi
		sync
		/bin/reboot-mode bootloader
	fi
	sleep 10
done
INIT
chmod 0755 "$STAGE/init"

mkdir -p "$(dirname "$OUT")"
info "Packing $OUT"
# shellcheck disable=SC2016  # $1 expands inside the fakeroot shell
fakeroot -- sh -c '
	set -e
	cd "$1"
	mknod -m 600 dev/console c 5 1
	mknod -m 666 dev/null c 1 3
	find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --quiet
' sh "$STAGE" | gzip -9 > "$OUT"
info "Done: $OUT ($(du -h "$OUT" | cut -f1))"
