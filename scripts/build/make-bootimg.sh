#!/usr/bin/env bash
# Produce the boot images for every attempt in docs/boot-plani.md §3 (build artifacts only).
#
#   d1-v1-appended.img   header v1, Image.gz + DTB appended, DTB without msm/board-id   (Deneme 1)
#   d2-v2-dtb.img        header v2, DTB in the dtb section AND appended, no IDs        (Deneme 2)
#   emptydtbo.img        2 zero bytes, for dtbo_a (Seviye 2, flashed by hand)          (Deneme 3)
#   dtbo-bos-overlay.img dt_table with one empty overlay carrying nicole's IDs         (Deneme 3 alt.)
#   d4-v2-ids.img        like d2 but DTB has qcom,msm-id <439 0x20001>,
#                        qcom,board-id <0x1001f 0x02>                                  (Deneme 4)
#   d5-boot-v3.img +     header v3 boot + vendor_boot carrying our DTB with the SoC IDs
#   d5-vendor_boot-v3.img  of Razer's/LineageOS' vendor_boot DTBs (msm-id 0x1b7/0x1f6 v2.1,
#   d5-dtbo.img            board-id 0 0) + dtbo (board-id 0x1001f 2 + root model/compatible
#                          + empty __symbols__/__fixups__/__local_fixups__), the stock
#                          layout. Proven 2026-10-25 (lab log): first mainline boot.
#                          boot_a/vendor_boot_a/dtbo_a are Seviye 2 (scripts/lab/yaz-dene.sh)
#                                                                                      (Deneme 5)
#
# THIS SCRIPT NEVER RUNS fastboot (no flash, no erase, no boot). Use scripts/lab/deneme.sh
# on the Mac for "fastboot boot"; partition writes follow docs/guvenlik-kurallari.md levels.
#
# Usage: make-bootimg.sh [options]
#   --kernel FILE     Image.gz            (default: $WORK/out/latest/Image.gz)
#   --dtb FILE        DTB                 (default: $WORK/out/latest/sm8350-razer-nicole.dtb)
#   --ramdisk FILE    initramfs           (default: $WORK/out/initramfs-mini.cpio.gz)
#   --out DIR         output directory    (default: <project>/out/boot)
#   --cmdline "..."   replace the default kernel cmdline
#   --extra "..."     append to the cmdline (e.g. "nicole.sinyal=reboot" or "pmos.debug-shell")
#   --only LIST       comma list of: d1,d2,d3,d4,d5 (default: all)
#   --dtbo FILE       dtbo for d5 (default: out/dtbo-parca/k-hic.img, LineageOS' nicole
#                     overlay with every fragment removed - the only dtbo proven to boot;
#                     our generated board-only overlays were refused and "W1" hung ABL)
# Env: OS_VERSION (default 12.0.0), OS_PATCH_LEVEL (default 2025-01, as slot B).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${RAZER_PROJECT:-$(cd "$HERE/../.." && pwd)}"
WORK="${WORK:-/mnt/lima-razer-build}"
DTS_NAME="sm8350-razer-nicole"

KERNEL="$WORK/out/latest/Image.gz"
DTB="$WORK/out/latest/$DTS_NAME.dtb"
RAMDISK="$WORK/out/initramfs-mini.cpio.gz"
OUT="$PROJECT/out/boot"
CMDLINE="console=tty0 fbcon=rotate:1 fbcon=font:TER16x32 loglevel=8 ignore_loglevel printk.devkmsg=on clk_ignore_unused pd_ignore_unused panic=30 softlockup_panic=1 hung_task_panic=1 hardlockup_panic=1 rcupdate.rcu_cpu_stall_panic=1"
EXTRA=""
ONLY="d1,d2,d3,d4,d5"
DTBO_D5="$PROJECT/out/dtbo-parca/k-hic.img"
OS_VERSION="${OS_VERSION:-12.0.0}"
# 2025-01 = slot B's stock boot image; the working 2026-10-25 chain used it
OS_PATCH_LEVEL="${OS_PATCH_LEVEL:-2025-01}"

# nicole IDs from Razer's DT (docs/boot-plani.md §2.1), as decimal for fdtput
MSM_ID=(439 131073)     # <439 0x20001>   SG8175P v2.1
BOARD_ID=(65567 2)      # <0x1001f 0x02>  HDK platform v1, subtype 2
# SoC DTB IDs as in the vendor_boot DTBs of LineageOS' nicole build (SM8350 0x1b7 and
# 0x1f6, v2.1; the board overlay in dtbo carries the board-id)
SOC_MSM_ID=(439 131073 502 131073)
SOC_BOARD_ID=(0 0)

# Common mkbootimg layout (pmOS defaults; BoardConfig: base 0, pagesize 4096)
BASE=0x00000000 KOFF=0x00008000 ROFF=0x01000000 SOFF=0x00000000 TOFF=0x00000100 DOFF=0x01f00000 PAGE=4096
BOOT_PART_MAX=$((96 * 1024 * 1024))   # BOARD_BOOTIMAGE_PARTITION_SIZE

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
# Hard guard: nothing in here may ever reach the phone.
# shellcheck disable=SC2329  # intentionally never invoked
fastboot() { die "make-bootimg.sh must never call fastboot ($*)"; }
# shellcheck disable=SC2329  # intentionally never invoked
adb() { die "make-bootimg.sh must never call adb ($*)"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--kernel) KERNEL="${2:?}"; shift ;;
		--dtb) DTB="${2:?}"; shift ;;
		--ramdisk) RAMDISK="${2:?}"; shift ;;
		--out) OUT="${2:?}"; shift ;;
		--cmdline) CMDLINE="${2:?}"; shift ;;
		--extra) EXTRA="${2:?}"; shift ;;
		--only) ONLY="${2:?}"; shift ;;
		--dtbo) DTBO_D5="${2:?}"; shift ;;
		-h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done
[ -n "$EXTRA" ] && CMDLINE="$CMDLINE $EXTRA"

for t in mkbootimg fdtput fdtget python3; do
	command -v "$t" >/dev/null || die "$t missing (run vm-setup.sh)"
done
for f in "$KERNEL" "$DTB" "$RAMDISK"; do
	[ -f "$f" ] || die "missing input: $f (build-kernel.sh / mkinitramfs-mini.sh first)"
done
case "$(head -c 2 "$KERNEL" | od -An -tx1 | tr -d ' ')" in
	1f8b) ;;
	*) warn "$KERNEL does not look gzip-compressed (expected Image.gz)" ;;
esac
want() { case ",$ONLY," in *",$1,"*) return 0 ;; esac; return 1; }

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOG="$OUT/BILGI.txt"
{
	echo "# make-bootimg.sh $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "kernel:  $KERNEL"
	echo "dtb:     $DTB"
	echo "ramdisk: $RAMDISK"
	echo "cmdline: $CMDLINE"
	echo "os_version/os_patch_level: $OS_VERSION / $OS_PATCH_LEVEL"
	echo
} > "$LOG"

# Run mkbootimg and record the exact command line.
mkb() {
	{
		printf 'mkbootimg'
		printf ' %q' "$@"
		printf '\n\n'
	} >> "$LOG"
	mkbootimg "$@"
}

# ---------------------------------------------------------------- DTB variants
# No IDs (default; sagami: msm/board-id upsets SM8350 ABL)
DTB_NOIDS="$TMP/$DTS_NAME-noids.dtb"
cp "$DTB" "$DTB_NOIDS"
fdtput -d "$DTB_NOIDS" / qcom,msm-id 2>/dev/null || true
fdtput -d "$DTB_NOIDS" / qcom,board-id 2>/dev/null || true
fdtput -d "$DTB_NOIDS" / qcom,pmic-id 2>/dev/null || true
# With nicole's IDs
DTB_IDS="$TMP/$DTS_NAME-ids.dtb"
cp "$DTB_NOIDS" "$DTB_IDS"
fdtput -t u "$DTB_IDS" / qcom,msm-id "${MSM_ID[@]}"
fdtput -t u "$DTB_IDS" / qcom,board-id "${BOARD_ID[@]}"
if [ -z "$(fdtget -p "$DTB" /__symbols__ 2>/dev/null | head -c1)" ]; then
	warn "DTB has no __symbols__ (not built with -@); ABL dtbo/U-Boot may care (boot-plani.md §2.2)"
fi
# SoC DTB for vendor_boot v3 (stock layout, see SOC_MSM_ID)
DTB_SOC="$TMP/$DTS_NAME-soc.dtb"
cp "$DTB_NOIDS" "$DTB_SOC"
fdtput -t u "$DTB_SOC" / qcom,msm-id "${SOC_MSM_ID[@]}"
fdtput -t u "$DTB_SOC" / qcom,board-id "${SOC_BOARD_ID[@]}"
cp "$DTB_NOIDS" "$OUT/$DTS_NAME-noids.dtb"
cp "$DTB_IDS" "$OUT/$DTS_NAME-ids.dtb"

KDTB_NOIDS="$TMP/Image.gz-dtb-noids"
KDTB_IDS="$TMP/Image.gz-dtb-ids"
cat "$KERNEL" "$DTB_NOIDS" > "$KDTB_NOIDS"
cat "$KERNEL" "$DTB_IDS" > "$KDTB_IDS"

COMMON=(--base "$BASE" --kernel_offset "$KOFF" --ramdisk_offset "$ROFF" --tags_offset "$TOFF"
	--pagesize "$PAGE" --os_version "$OS_VERSION" --os_patch_level "$OS_PATCH_LEVEL")

# ---------------------------------------------------------------- d1: v1 + appended
if want d1; then
	info "d1: header v1, appended DTB, no IDs"
	mkb --header_version 1 --kernel "$KDTB_NOIDS" --ramdisk "$RAMDISK" --cmdline "$CMDLINE" \
		--second_offset "$SOFF" "${COMMON[@]}" -o "$OUT/d1-v1-appended.img"
fi

# ---------------------------------------------------------------- d2: v2 + dtb section (+ appended)
if want d2; then
	info "d2: header v2, dtb section + appended DTB, no IDs"
	mkb --header_version 2 --kernel "$KDTB_NOIDS" --ramdisk "$RAMDISK" --dtb "$DTB_NOIDS" \
		--dtb_offset "$DOFF" --cmdline "$CMDLINE" "${COMMON[@]}" -o "$OUT/d2-v2-dtb.img"
fi

# ---------------------------------------------------------------- d3: dtbo helpers
if want d3; then
	info "d3: emptydtbo.img (2 zero bytes) + dtbo-bos-overlay.img"
	head -c 2 /dev/zero > "$OUT/emptydtbo.img"
	python3 "$HERE/dtbo-araci.py" bos "$OUT/dtbo-bos-overlay.img" \
		--msm-id "439,0x20001" --board-id "0x1001f,0x2" >/dev/null
	{
		echo "emptydtbo.img: head -c 2 /dev/zero  (Seviye 2: fastboot flash dtbo_a emptydtbo.img - BY HAND, after backing up dtbo_a)"
		echo "dtbo-bos-overlay.img: dtbo-araci.py bos --msm-id 439,0x20001 --board-id 0x1001f,0x2"
		echo
	} >> "$LOG"
fi

# ---------------------------------------------------------------- d4: v2 with IDs
if want d4; then
	info "d4: header v2 with qcom,msm-id/board-id"
	mkb --header_version 2 --kernel "$KDTB_IDS" --ramdisk "$RAMDISK" --dtb "$DTB_IDS" \
		--dtb_offset "$DOFF" --cmdline "$CMDLINE" "${COMMON[@]}" -o "$OUT/d4-v2-ids.img"
fi

# ---------------------------------------------------------------- d5: v3 boot + vendor_boot
if want d5; then
	info "d5: header v3 boot.img + vendor_boot.img (DTB in vendor_boot)"
	mkb --header_version 3 --kernel "$KERNEL" --ramdisk "$RAMDISK" --cmdline "$CMDLINE" \
		--os_version "$OS_VERSION" --os_patch_level "$OS_PATCH_LEVEL" -o "$OUT/d5-boot-v3.img"
	# vendor_boot v3 needs a vendor ramdisk: use an empty cpio (only the TRAILER); the
	# kernel unpacks the concatenation vendor ramdisk + boot ramdisk.
	: | cpio -o -H newc --quiet | gzip -9 > "$TMP/vendor-ramdisk-empty.cpio.gz"
	mkb --header_version 3 --vendor_boot "$OUT/d5-vendor_boot-v3.img" --dtb "$DTB_SOC" \
		--vendor_ramdisk "$TMP/vendor-ramdisk-empty.cpio.gz" \
		--vendor_cmdline "" --base "$BASE" --pagesize "$PAGE" --kernel_offset "$KOFF" \
		--ramdisk_offset "$ROFF" --tags_offset "$TOFF" --dtb_offset "$DOFF"
	# ABL v3 needs a valid dtbo here: with an invalid one its single-DTB fallback reads
	# the boot image, not vendor_boot (BootLinux.c DTBImgCheckAndAppendDT). A board-only
	# overlay is not enough either (needs root model/compatible + the special nodes).
	# ABL applies its root properties to our DTB, so its compatible must be ours:
	# with LineageOS' "qcom,lahaina-hdk" the live root lost "qcom,sm8350" and the
	# in-kernel PD mapper (ADSP charger_pd -> battery) refused the platform. ABL
	# selects the dtbo by board/msm-id only (LocateDeviceTree.c), never compatible.
	[ -f "$DTBO_D5" ] || die "missing d5 dtbo: $DTBO_D5 (--dtbo FILE)"
	kok_compat="$(fdtget -t s "$DTB" / compatible | tr ' ' '|')"
	python3 "$HERE/dtbo-araci.py" kok "$DTBO_D5" "$OUT/d5-dtbo.img" "compatible=$kok_compat" >/dev/null
	echo "d5-dtbo.img: $DTBO_D5 ($(sha256sum "$DTBO_D5" | cut -c1-16)) + root compatible=$kok_compat" >> "$LOG"
fi

# ---------------------------------------------------------------- checks + manifest
info "Sanity check"
# only the boot images d1..d5 (dtbo-bos-overlay.img also starts with "d")
for img in "$OUT"/d[0-9]-*.img; do
	[ -f "$img" ] || continue
	sz=$(stat -c %s "$img")
	if [ "$sz" -gt "$BOOT_PART_MAX" ]; then
		warn "$(basename "$img") is $sz bytes > boot partition (96 MiB); fine for RAM boot only if <= max-download-size"
	fi
	if command -v unpack_bootimg >/dev/null; then
		hv="$(unpack_bootimg --boot_img "$img" --out "$TMP/unpack-$(basename "$img")" 2>/dev/null \
			| awk -F': ' '/header version/ {print $2; exit}' || true)"
		printf '  %-26s %10s bytes  header=%s\n' "$(basename "$img")" "$sz" "${hv:-?}"
	else
		printf '  %-26s %10s bytes\n' "$(basename "$img")" "$sz"
	fi
done
( cd "$OUT" && sha256sum ./*.img ./*.dtb > SHA256SUMS )
info "Images in $OUT (commands: $LOG)"
cat <<EOF

On the Mac (one attempt at a time, see docs/boot-plani.md §3):
  scripts/lab/deneme.sh out/boot/d1-v1-appended.img d1-v1-appended
  scripts/lab/deneme.sh out/boot/d2-v2-dtb.img      d2-v2-dtb
Seviye 2 steps (dtbo_a / vendor_boot_a / set-active) are NOT automated here.
EOF
