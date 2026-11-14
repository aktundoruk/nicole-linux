#!/usr/bin/env bash
# Repack the postmarketOS boot parts into the boot chain that works on nicole's ABL
# (lab log, 25 Ekim gece (2)): header v3 boot.img + vendor_boot with the SoC-ID
# DTB + the proven dtbo. pmbootstrap itself only writes a header v1 boot.img
# (deviceinfo_header_version="1"), which this ABL never boots.
#
# Takes the pmOS kernel (vmlinuz, matches the modules in the rootfs), initramfs, DTB and
# the cmdline pmbootstrap generated (pmos_boot_uuid / pmos_root_uuid of the image) from
# the export of scripts/build/pmos-hazirla.sh and calls make-bootimg.sh --only d5.
#
# Usage (inside the build VM): pmos-bootimg.sh [--extra "cmdline additions"] [--drop "words"] [--dtb FILE] [--out DIR]
#   --kernel: kernel image instead of the pmOS one (same kernel.release as the rootfs
#             modules, e.g. build-kernel.sh with LOCALVERSION= and the pmOS config)
#   --drop: cmdline words to remove from the pmOS cmdline (e.g. "clk_ignore_unused pd_ignore_unused")
#   --dtb: DTB for vendor_boot instead of the pmOS package one (ABL takes the DTB only
#          from vendor_boot, so a DTS fix needs build-kernel.sh, not a pmOS rebuild)
# Output: <project>/out/pmos-boot/d5-{boot-v3,vendor_boot-v3,dtbo}.img
# Never touches the phone; flash with scripts/lab/yaz-dene.sh (Seviye 2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${RAZER_PROJECT:-$(cd "$HERE/../.." && pwd)}"
WORK="${WORK:-/mnt/lima-razer-build}"
EXP="${PMOS_EXP:-$WORK/pmos-export}"   # PMOS_EXP: e.g. a copy of the phone's /boot after apk upgrade
OUT="$PROJECT/out/pmos-boot"
EXTRA=""
DROP=""
DTB=""
KERNEL=""

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
while [ $# -gt 0 ]; do
	case "$1" in
		--extra) EXTRA="${2:?}"; shift ;;
		--drop) DROP="${2:?}"; shift ;;
		--kernel) KERNEL="${2:?}"; shift ;;
		--dtb) DTB="${2:?}"; shift ;;
		--out) OUT="${2:?}"; shift ;;
		-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done
[ "$(uname -s)" = "Linux" ] || die "run inside the build VM"
for f in boot.img vmlinuz initramfs dtbs/sm8350-razer-nicole.dtb; do
	[ -e "$EXP/$f" ] || die "missing $EXP/$f (run pmos-hazirla.sh first)"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unpack_bootimg --boot_img "$EXP/boot.img" --out "$TMP/u" > "$TMP/u.txt"
CMDLINE="$(sed -n 's/^command line args: //p' "$TMP/u.txt")"
case "$CMDLINE" in *pmos_root_uuid=*) ;; *) die "no pmos_root_uuid in the pmOS cmdline: $CMDLINE" ;; esac
# kernel messages stay on screen (webcam / photos): drop pmOS' "quiet"
CMDLINE="$(sed -E 's/(^| )quiet( |$)/\1/' <<<"$CMDLINE")"
for w in $DROP; do
	CMDLINE="$(sed -E "s/(^| )$w( |\$)/\1/" <<<"$CMDLINE")"
	case " $CMDLINE " in *" $w "*) die "could not drop $w from the cmdline" ;; esac
done
[ -n "$EXTRA" ] && CMDLINE="$CMDLINE $EXTRA"
# rdinit= naming a file the initramfs lacks is a panic, and each panic uses up a boot attempt
for w in $CMDLINE; do
	case "$w" in rdinit=*)
		liste="$( (gzip -dc "$(readlink -f "$EXP/initramfs")" 2>/dev/null || zstd -dc "$(readlink -f "$EXP/initramfs")") | cpio -t 2>/dev/null || true)"
		grep -qx "${w#rdinit=/}" <<<"$liste" || die "$w: initramfs does not contain it"
	esac
done

"$HERE/make-bootimg.sh" --only d5 --out "$OUT" \
	--kernel "${KERNEL:-$(readlink -f "$EXP/vmlinuz")}" \
	--ramdisk "$(readlink -f "$EXP/initramfs")" \
	--dtb "${DTB:-$(readlink -f "$EXP/dtbs/sm8350-razer-nicole.dtb")}" \
	--cmdline "$CMDLINE"
echo "pmos kernel.release: $(cat "$WORK/pmbootstrap/chroot_rootfs_razer-nicole/usr/share/kernel/razer-nicole/kernel.release" 2>/dev/null || echo '?')" >> "$OUT/BILGI.txt"
