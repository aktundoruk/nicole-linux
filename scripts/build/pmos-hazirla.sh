#!/usr/bin/env bash
# Build a postmarketOS (console UI) image for the Razer Edge Wi-Fi (nicole) inside the
# build VM, WITHOUT the device. The result is meant for the microSD card: the kernel is
# RAM-booted with "fastboot boot" (deneme.sh), the pmOS initramfs then finds the
# pmOS_root partition on the card. Nothing is ever flashed (docs/guvenlik-kurallari.md).
#
#   1. clone pmaports (edge) into $WORK/pmbootstrap/cache_git/pmaports
#   2. write the pmbootstrap config non-interactively (pmbootstrap init is interactive)
#   3. copy <project>/pmaports/{device,linux}-razer-nicole into device/testing
#   4. pmbootstrap checksum + kconfig check + build linux-razer-nicole
#   5. pmbootstrap install (image file, not --sdcard) + export
#   6. copy the image (zstd) and the pmOS boot.img to <project>/out/pmos/
#
# Login: user "user", SSH key ~/.ssh/razer_nicole (Mac), password in out/pmos/parola.txt
# (generated, local test password for this image only; out/ is git-ignored).
#
# --yayin (release, 7 Kasım): no razer-nicole-lab (passwordless doas), no debug tools, no
# SSH key from this Mac, output in out/pmos-yayin/. The firmware is never in the image:
# on the phone, `doas nicole-firmware-cek` copies it from the Android partitions.
# NOTE: the package list here predates the shell and libcamera; refresh it before v0.1.
#
# Usage: pmos-hazirla.sh [--no-build-kernel] [--only-config] [--yayin]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${RAZER_PROJECT:-$(cd "$HERE/../.." && pwd)}"
WORK="${WORK:-/mnt/lima-razer-build}"
PMB_WORK="$WORK/pmbootstrap"
APORTS="$PMB_WORK/cache_git/pmaports"
OUT="$PROJECT/out/pmos"
DEVICE="razer-nicole"
EXTRA="openssh-server,usbutils,pciutils,i2c-tools,dtc,evtest,htop,tmux,lm-sensors"
EXTRA_YAYIN="openssh-server"
BUILD_KERNEL=1
ONLY_CONFIG=0
YAYIN=0

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
# Hard guard: this script must never reach the phone.
# shellcheck disable=SC2329  # intentionally never invoked
fastboot() { die "pmos-hazirla.sh must never call fastboot ($*)"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--no-build-kernel) BUILD_KERNEL=0 ;;
		--only-config) ONLY_CONFIG=1 ;;
		--yayin) YAYIN=1 ;;
		-h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done

[ "$(uname -s)" = "Linux" ] || die "run inside the build VM"
command -v pmbootstrap >/dev/null || die "pmbootstrap missing (vm-setup.sh)"
[ -f "$OUT/parola.txt" ] || die "missing $OUT/parola.txt (created on the Mac, see lab log 2026-10-07)"
LABPKG=()  # the author's lab package (passwordless doas) is not published
if [ "$YAYIN" = 1 ]; then
	EXTRA="$EXTRA_YAYIN"
	LABPKG=()
	PAROLA="$OUT/parola.txt"
	OUT="$PROJECT/out/pmos-yayin"
	info "release image: no razer-nicole-lab, no debug tools, no SSH key"
else
	[ -f "$OUT/razer_nicole.pub" ] || die "missing $OUT/razer_nicole.pub"
	# SSH key for the image: pmbootstrap copies files matching ssh_key_glob
	install -d -m 0700 "$HOME/.ssh"
	install -m 0644 "$OUT/razer_nicole.pub" "$HOME/.ssh/razer_nicole.pub"
	PAROLA="$OUT/parola.txt"
fi

# ---------------------------------------------------------------- 1. pmaports
mkdir -p "$PMB_WORK/cache_git"
if [ ! -d "$APORTS/.git" ]; then
	info "cloning pmaports (shallow)"
	git clone --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$APORTS"
fi
# work dir marker normally written by "pmbootstrap init"
if [ ! -f "$PMB_WORK/version" ]; then
	python3 - "$PMB_WORK/version" <<'PY'
import sys, re, pathlib
src = pathlib.Path.home() / ".local/bin/pmbootstrap"
cfg = src.resolve().parent / "pmb/config/__init__.py"
m = re.search(r"^work_version = (\d+)", cfg.read_text(), re.M)
open(sys.argv[1], "w").write(m.group(1) + "\n")
PY
fi

# ---------------------------------------------------------------- 3. device packages
for p in device-razer-nicole linux-razer-nicole "${LABPKG[@]}"; do
	rm -rf "$APORTS/device/testing/$p"
	cp -R "$PROJECT/pmaports/$p" "$APORTS/device/testing/$p"
done

# ---------------------------------------------------------------- 2. config
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/pmbootstrap_v3.cfg"
if [ ! -f "$CFG" ]; then
	# minimal file instead of the interactive "pmbootstrap init"; the rest is set below
	mkdir -p "$(dirname "$CFG")"
	printf '[pmbootstrap]\nwork = %s\naports = %s\ndevice = %s\n' \
		"$PMB_WORK" "$APORTS" "$DEVICE" > "$CFG"
fi
pmb() { pmbootstrap -q "$@"; }
pmb config work "$PMB_WORK"
pmb config aports "$APORTS"
pmb config device "$DEVICE"
pmb config ui console
# "pmbootstrap config ui_extras False" stores True (string->bool), so edit the file
sed -i 's/^ui_extras = .*/ui_extras = False/' "$CFG"
pmb config user user
pmb config hostname nicole
pmb config timezone Europe/Istanbul
if [ "$YAYIN" = 1 ]; then
	# same string->bool trap as ui_extras: "config ssh_keys False" stores True
	sed -i 's/^ssh_keys = .*/ssh_keys = False/' "$CFG"
else
	pmb config ssh_keys True
	pmb config ssh_key_glob "$HOME/.ssh/razer_nicole.pub"
fi
pmb config extra_packages "$EXTRA"
pmb config build_pkgs_on_install True
pmb config jobs "$(nproc)"
info "pmbootstrap config:"
pmbootstrap config | sed 's/^/    /'
[ "$ONLY_CONFIG" = 1 ] && exit 0

# ---------------------------------------------------------------- 4. kernel package
info "checksums (downloads the kernel tarball once)"
pmbootstrap checksum device-razer-nicole linux-razer-nicole "${LABPKG[@]}"
# keep the filled checksums in the project copy too
for p in device-razer-nicole linux-razer-nicole "${LABPKG[@]}"; do
	cp "$APORTS/device/testing/$p/APKBUILD" "$PROJECT/pmaports/$p/APKBUILD"
done

info "kconfig check (postmarketOS requirements)"
if ! pmbootstrap kconfig check linux-razer-nicole; then
	warn "kconfig check reported missing options: add them to scripts/build/razer.config,"
	warn "re-run build-kernel.sh --export-config, then this script"
	exit 2
fi

if [ "$BUILD_KERNEL" = 1 ]; then
	info "building linux-razer-nicole (~15-25 min)"
	pmbootstrap build --force linux-razer-nicole
fi

# ---------------------------------------------------------------- 5. install + export
info "pmbootstrap install (image file)"
pmbootstrap install --no-fde --password "$(cat "$PAROLA")"
EXP="$WORK/pmos-export"
rm -rf "$EXP"
pmbootstrap export "$EXP"

# ---------------------------------------------------------------- 6. copy to project
mkdir -p "$OUT"
img="$(readlink -f "$EXP/$DEVICE.img")"
[ -f "$img" ] || die "no $DEVICE.img in export"
info "compressing image -> $OUT/$DEVICE.img.zst"
zstd -T0 -q -f "$img" -o "$OUT/$DEVICE.img.zst"
cp -L "$EXP/boot.img" "$OUT/pmos-boot.img"
( cd "$OUT" && sha256sum "$DEVICE.img.zst" pmos-boot.img > SHA256SUMS )
{
	echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "pmaports: $(git -C "$APORTS" rev-parse --short HEAD)"
	echo "kernel: $(pmbootstrap -q chroot -r -- cat /usr/share/kernel/$DEVICE/kernel.release 2>/dev/null || echo '?')"
	echo "image size (raw): $(stat -c %s "$img") bytes"
	if [ "$YAYIN" = 1 ]; then echo "login: user / password in out/pmos/parola.txt (no SSH key)"
	else echo "login: user / SSH key razer_nicole / password in parola.txt"; fi
	echo "write to microSD (Mac): see docs/boot-plani.md"
} > "$OUT/BILGI.txt"
info "done:"
ls -lh "$OUT" | sed 's/^/    /'
