#!/usr/bin/env bash
# Build a mainline Linux kernel for the Razer Edge Wi-Fi (nicole) inside the Linux VM.
#
#  1. shallow-clones mainline at TAG into the VM build disk (never into the Mac folder)
#  2. resets the tree to the pristine tag, then applies the project's changes:
#       - every drivers/**/*.patch (sorted by path)           -> git apply
#       - drivers/touchscreen/focaltech_ft3658s_spi.c (+Kconfig.fragment, binding)
#       - drivers/haptics/aw8622x.c (+Kconfig.fragment) -> drivers/input/misc
#       - dts/*.dts, dts/*.dtsi -> arch/arm64/boot/dts/qcom/ (+ Makefile entry, built with -@)
#  3. arm64 defconfig + scripts/build/razer.config, checks which fragment lines stuck
#  4. builds Image.gz, qcom/sm8350-razer-nicole.dtb and modules
#  5. collects artifacts in $WORK/out/<kernelrelease>/ (and small ones in the project's out/)
#
# Usage: build-kernel.sh [options]
#   -t, --tag TAG         kernel tag/branch (default: $TAG or v7.3-rc6)
#   -j, --jobs N          parallel jobs (default: nproc)
#       --clean           delete the object directory first (full rebuild)
#       --no-patches      skip drivers/ patches and source drivers (DTS is still added)
#       --menuconfig      run menuconfig after merging the fragment
#       --export-config   copy the final .config and the combined project diff to
#                         pmaports/linux-razer-nicole/ (config-razer-nicole.aarch64,
#                         0001-nicole-local-changes.patch)
#       --export-modules  also copy the modules tarball to the project out/ dir (large!)
#       --no-export       do not copy anything back to the project folder
#   -h, --help
# Env: WORK (default /mnt/lima-razer-build), RAZER_PROJECT, KERNEL_GIT, LLVM=1, EXPORT_DIR
#
# This script only builds. It never talks to the phone (no adb/fastboot).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${RAZER_PROJECT:-$(cd "$HERE/../.." && pwd)}"
WORK="${WORK:-/mnt/lima-razer-build}"
TAG="${TAG:-v7.3-rc6}"
KERNEL_GIT="${KERNEL_GIT:-https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git}"
KERNEL_GIT_MIRROR="https://github.com/torvalds/linux.git"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
DTS_NAME="sm8350-razer-nicole"
EXPORT_DIR="${EXPORT_DIR:-$PROJECT/out/kernel}"

CLEAN=0 PATCHES=1 MENUCONFIG=0 EXPORT=1 EXPORT_CONFIG=0 EXPORT_MODULES=0

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; }

while [ $# -gt 0 ]; do
	case "$1" in
		-t|--tag) TAG="${2:?}"; shift ;;
		-j|--jobs) JOBS="${2:?}"; shift ;;
		--clean) CLEAN=1 ;;
		--no-patches) PATCHES=0 ;;
		--menuconfig) MENUCONFIG=1 ;;
		--export-config) EXPORT_CONFIG=1 ;;
		--export-modules) EXPORT_MODULES=1 ;;
		--no-export) EXPORT=0 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
	shift
done

# ---------------------------------------------------------------- sanity
[ "$(uname -s)" = "Linux" ] || die "Run inside the Linux VM (APFS is case-insensitive and the Mac disk is full)."
if [ ! -d "$WORK" ] || [ ! -w "$WORK" ]; then
	die "WORK=$WORK is not a writable directory (Lima additional disk mounted?)"
fi
case "$WORK" in
	"$PROJECT"|"$PROJECT"/*) die "WORK must not be inside the shared project folder ($PROJECT)" ;;
esac
[ -f "$HERE/razer.config" ] || die "missing $HERE/razer.config"
[ -f "$PROJECT/dts/$DTS_NAME.dts" ] || die "missing $PROJECT/dts/$DTS_NAME.dts"

SRC="$WORK/src/linux-$TAG"
BUILD="$WORK/build/linux-$TAG"
mkdir -p "$WORK/src" "$WORK/build" "$WORK/out"

MAKE_ARGS=(ARCH=arm64 "O=$BUILD" "-j$JOBS")
if [ "$(uname -m)" != "aarch64" ]; then
	MAKE_ARGS+=(CROSS_COMPILE=aarch64-linux-gnu-)
fi
if [ "${LLVM:-0}" = "1" ]; then
	MAKE_ARGS+=(LLVM=1)
fi
kmake() { make -C "$SRC" "${MAKE_ARGS[@]}" "$@"; }

avail_kb() { df -Pk "$1" | awk 'NR==2 {print $4}'; }
if [ "$(avail_kb "$WORK")" -lt $((15 * 1024 * 1024)) ]; then
	warn "less than 15 GiB free on $WORK; a full arm64 defconfig build needs ~10-15 GiB"
fi

# ---------------------------------------------------------------- 1. source
if [ ! -d "$SRC/.git" ]; then
	info "Cloning $TAG (shallow) into $SRC"
	if ! git clone --depth 1 --branch "$TAG" "$KERNEL_GIT" "$SRC"; then
		warn "kernel.org clone failed, trying $KERNEL_GIT_MIRROR"
		rm -rf "$SRC"
		git clone --depth 1 --branch "$TAG" "$KERNEL_GIT_MIRROR" "$SRC"
	fi
	git -C "$SRC" rev-parse HEAD > "$SRC/.git/nicole-base"
fi
[ -f "$SRC/.git/nicole-base" ] || git -C "$SRC" rev-parse HEAD > "$SRC/.git/nicole-base"
BASE="$(cat "$SRC/.git/nicole-base")"

info "Resetting $SRC to pristine $TAG ($BASE)"
git -C "$SRC" reset -q --hard "$BASE"
git -C "$SRC" clean -q -fd

# ---------------------------------------------------------------- 2a. patches
APPLIED=()
if [ "$PATCHES" = "1" ] && [ -d "$PROJECT/drivers" ]; then
	mapfile -t PATCH_LIST < <(find "$PROJECT/drivers" -type f -name '*.patch' | LC_ALL=C sort)
	for p in "${PATCH_LIST[@]}"; do
		rel="${p#"$PROJECT"/}"
		if git -C "$SRC" apply --check --whitespace=nowarn "$p" 2>/dev/null; then
			git -C "$SRC" apply --whitespace=nowarn "$p"
			APPLIED+=("$rel")
			info "applied $rel"
		elif git -C "$SRC" apply --check -3 "$p" 2>/dev/null; then
			git -C "$SRC" apply -3 "$p"
			APPLIED+=("$rel (3-way)")
			warn "applied with 3-way merge: $rel"
		else
			git -C "$SRC" apply --check -v "$p" || true
			die "patch does not apply to $TAG: $rel"
		fi
	done
fi

# ---------------------------------------------------------------- 2b. source-form drivers
integrate_touchscreen() {
	local d="$PROJECT/drivers/touchscreen" kdir="$SRC/drivers/input/touchscreen"
	[ -f "$d/focaltech_ft3658s_spi.c" ] || return 0
	cp "$d/focaltech_ft3658s_spi.c" "$kdir/"
	if [ -f "$d/focaltech,ft3658s.yaml" ]; then
		cp "$d/focaltech,ft3658s.yaml" "$SRC/Documentation/devicetree/bindings/input/touchscreen/"
	fi
	if ! grep -q 'TOUCHSCREEN_FOCALTECH_FT3658S_SPI' "$kdir/Kconfig"; then
		[ -f "$d/Kconfig.fragment" ] || die "$d/Kconfig.fragment missing"
		local block last_endif
		# "config ..." block of the fragment, up to the first comment line after it
		block="$(awk '/^config /{f=1} f && /^#/{exit} f' "$d/Kconfig.fragment")"
		[ -n "$block" ] || die "no config block found in $d/Kconfig.fragment"
		last_endif="$(grep -n '^endif' "$kdir/Kconfig" | tail -1 | cut -d: -f1)"
		[ -n "$last_endif" ] || die "unexpected layout of $kdir/Kconfig"
		{
			head -n $((last_endif - 1)) "$kdir/Kconfig"
			printf '%s\n\n' "$block"
			tail -n +"$last_endif" "$kdir/Kconfig"
		} > "$kdir/Kconfig.new"
		mv "$kdir/Kconfig.new" "$kdir/Kconfig"
	fi
	if ! grep -q 'focaltech_ft3658s_spi.o' "$kdir/Makefile"; then
		# shellcheck disable=SC2016  # literal $(CONFIG_...) for Kbuild
		printf 'obj-$(CONFIG_TOUCHSCREEN_FOCALTECH_FT3658S_SPI)\t+= focaltech_ft3658s_spi.o\n' >> "$kdir/Makefile"
	fi
	APPLIED+=("drivers/touchscreen/focaltech_ft3658s_spi.c (source)")
	info "integrated FT3658S touchscreen driver"
}
integrate_haptics() {
	local d="$PROJECT/drivers/haptics" kdir="$SRC/drivers/input/misc"
	[ -f "$d/aw8622x.c" ] || return 0
	cp "$d/aw8622x.c" "$kdir/"
	if ! grep -q 'INPUT_AW8622X' "$kdir/Kconfig"; then
		local block last_endif
		block="$(awk '/^config /{f=1} f && /^#/{exit} f' "$d/Kconfig.fragment")"
		[ -n "$block" ] || die "no config block found in $d/Kconfig.fragment"
		last_endif="$(grep -n '^endif' "$kdir/Kconfig" | tail -1 | cut -d: -f1)"
		[ -n "$last_endif" ] || die "unexpected layout of $kdir/Kconfig"
		{
			head -n $((last_endif - 1)) "$kdir/Kconfig"
			printf '%s\n\n' "$block"
			tail -n +"$last_endif" "$kdir/Kconfig"
		} > "$kdir/Kconfig.new"
		mv "$kdir/Kconfig.new" "$kdir/Kconfig"
	fi
	if ! grep -q 'aw8622x.o' "$kdir/Makefile"; then
		# shellcheck disable=SC2016  # literal $(CONFIG_...) for Kbuild
		printf 'obj-$(CONFIG_INPUT_AW8622X)\t\t+= aw8622x.o\n' >> "$kdir/Makefile"
	fi
	APPLIED+=("drivers/haptics/aw8622x.c (source)")
	info "integrated AW8622x haptics driver"
}
if [ "$PATCHES" = "1" ]; then
	integrate_touchscreen
	integrate_haptics
	# Report other source files that nothing integrates yet.
	while IFS= read -r f; do
		case "$f" in
			*/touchscreen/focaltech_ft3658s_spi.c|*/haptics/aw8622x.c) ;;
			*) warn "not integrated automatically (add a .patch instead): ${f#"$PROJECT"/}" ;;
		esac
	done < <(find "$PROJECT/drivers" -type f -name '*.c' 2>/dev/null)
fi

# ---------------------------------------------------------------- 2c. device tree
QCOM_DTS="$SRC/arch/arm64/boot/dts/qcom"
for f in "$PROJECT"/dts/*.dts "$PROJECT"/dts/*.dtsi; do
	[ -e "$f" ] || continue
	cp "$f" "$QCOM_DTS/"
done
if ! grep -q "$DTS_NAME.dtb" "$QCOM_DTS/Makefile"; then
	{
		echo
		echo "# Razer Edge Wi-Fi (nicole) - added by scripts/build/build-kernel.sh"
		# shellcheck disable=SC2016  # literal $(CONFIG_...) for Kbuild
		echo 'dtb-$(CONFIG_ARCH_QCOM)	+= '"$DTS_NAME.dtb"
		# -@ keeps __symbols__: needed by ABL's dtbo logic and by U-Boot (docs/boot-plani.md §2)
		echo "DTC_FLAGS_$DTS_NAME := -@"
	} >> "$QCOM_DTS/Makefile"
fi
APPLIED+=("dts/$DTS_NAME.dts")

# Commit everything so `git diff BASE` documents exactly what was built.
git -C "$SRC" add -A
git -C "$SRC" -c user.name=nicole-builder -c user.email=nicole-builder@localhost \
	commit -q -m "nicole: local changes ($(date -u +%Y-%m-%dT%H:%MZ))" || true

# ---------------------------------------------------------------- 3. config
if [ "$CLEAN" = "1" ]; then
	info "Removing $BUILD"
	rm -rf "$BUILD"
fi
mkdir -p "$BUILD"
cp "$HERE/razer.config" "$SRC/arch/arm64/configs/razer.config"
info "Configuring: defconfig + razer.config"
kmake defconfig razer.config >/dev/null
if [ "$MENUCONFIG" = "1" ]; then
	kmake menuconfig
fi

info "Checking fragment lines against the final .config"
missing=0
while IFS= read -r line; do
	case "$line" in
		CONFIG_*=*)
			grep -qxF "$line" "$BUILD/.config" || { warn "did not stick: $line (now: $(grep -E "^(# )?${line%%=*}[= ]" "$BUILD/.config" || echo 'absent'))"; missing=$((missing + 1)); }
			;;
		"# CONFIG_"*" is not set")
			sym="${line#\# }"; sym="${sym%% *}"
			if grep -q "^$sym=" "$BUILD/.config"; then
				warn "should be unset: $sym"; missing=$((missing + 1))
			fi
			;;
	esac
done < "$HERE/razer.config"
if [ "$missing" -eq 0 ]; then
	info "all fragment lines applied"
else
	warn "$missing fragment line(s) not applied (renamed/missing symbols or unmet deps)"
fi

# ---------------------------------------------------------------- 4. build
info "Building Image.gz, qcom/$DTS_NAME.dtb, modules (-j$JOBS)"
kmake Image.gz "qcom/$DTS_NAME.dtb" modules

REL="$(kmake -s kernelrelease)"
ART="$WORK/out/$REL"
rm -rf "$ART"
mkdir -p "$ART"
cp "$BUILD/arch/arm64/boot/Image.gz" "$ART/Image.gz"
cp "$BUILD/arch/arm64/boot/dts/qcom/$DTS_NAME.dtb" "$ART/$DTS_NAME.dtb"
cp "$BUILD/System.map" "$ART/System.map"
cp "$BUILD/.config" "$ART/config"

info "Installing modules (stripped)"
kmake modules_install INSTALL_MOD_PATH="$ART/modules-root" INSTALL_MOD_STRIP=1 >/dev/null
find "$ART/modules-root" -maxdepth 4 \( -name build -o -name source \) -type l -delete
tar --zstd -cf "$ART/modules-$REL.tar.zst" -C "$ART/modules-root" .
{
	echo "kernelrelease: $REL"
	echo "tag: $TAG"
	echo "base: $BASE"
	echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "applied:"
	printf '  - %s\n' "${APPLIED[@]}"
} > "$ART/BUILDINFO"
git -C "$SRC" diff "$BASE" HEAD > "$ART/nicole-changes.diff"
( cd "$ART" && sha256sum Image.gz "$DTS_NAME.dtb" "modules-$REL.tar.zst" > SHA256SUMS )
ln -sfn "$ART" "$WORK/out/latest"

# ---------------------------------------------------------------- 5. export
if [ "$EXPORT_CONFIG" = "1" ]; then
	PMA="$PROJECT/pmaports/linux-razer-nicole"
	cp "$BUILD/.config" "$PMA/config-razer-nicole.aarch64"
	cp "$ART/nicole-changes.diff" "$PMA/0001-nicole-local-changes.patch"
	info "exported .config + nicole-changes.diff -> pmaports/linux-razer-nicole/ (pkgver must match $TAG)"
fi
if [ "$EXPORT" = "1" ]; then
	mkdir -p "$EXPORT_DIR"
	if [ "$(avail_kb "$EXPORT_DIR")" -lt $((1024 * 1024)) ]; then
		warn "less than 1 GiB free behind $EXPORT_DIR (Mac disk?): skipping export"
	else
		dst="$EXPORT_DIR/$REL"
		mkdir -p "$dst"
		cp "$ART/Image.gz" "$ART/$DTS_NAME.dtb" "$ART/config" "$ART/BUILDINFO" "$ART/SHA256SUMS" "$dst/"
		if [ "$EXPORT_MODULES" = "1" ]; then
			cp "$ART/modules-$REL.tar.zst" "$dst/"
		fi
		info "exported small artifacts -> $dst"
	fi
fi

info "Done: $ART"
find "$ART" -maxdepth 1 -type f -exec ls -lh {} + | sed 's/^/    /'
echo "Next: scripts/build/make-bootimg.sh   (uses \$WORK/out/latest by default)"
