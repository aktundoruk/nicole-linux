#!/usr/bin/env bash
# Prepare the Ubuntu 26.04 (arm64) build VM for the Razer Edge (nicole) mainline port.
#
# Installs: kernel build dependencies, dtc/fdtput, mkbootimg + unpack_bootimg (AOSP,
# Ubuntu package "mkbootimg"), abootimg, simg2img (android-sdk-libsparse-utils),
# mtools/e2fsprogs (to read modem/bluetooth/dsp partition images), busybox-static +
# fakeroot (mini initramfs), pil-squasher (built from source, not packaged in Ubuntu),
# ath11k-bdencoder (qca-swiss-army-knife script) and pmbootstrap from git (Ubuntu's
# pmbootstrap 3.9 is older than pmaports' pmbootstrap_min_version 3.11).
#
# Usage (inside the VM):  bash scripts/build/vm-setup.sh
# Env:   WORK=/mnt/lima-razer-build   (tools are cloned to $WORK/tools)
#
# Safe to re-run. Never touches the phone (no adb/fastboot here: USB stays on the Mac).
set -euo pipefail

WORK="${WORK:-/mnt/lima-razer-build}"
TOOLS="$WORK/tools"
BIN="$HOME/.local/bin"

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "Run this inside the Linux VM, not on macOS."
[ "$(id -u)" -ne 0 ] || die "Run as the normal VM user (sudo is used where needed)."
command -v apt-get >/dev/null || die "apt-get not found: this script targets Ubuntu."

case "$(uname -m)" in
	aarch64) ;;
	*) warn "Host is $(uname -m): kernel builds will need CROSS_COMPILE=aarch64-linux-gnu- (installed below)." ;;
esac

if [ ! -d "$WORK" ] || [ ! -w "$WORK" ]; then
	die "$WORK missing or not writable. Create the Lima additional disk first (see lima-razer.yaml)."
fi
mkdir -p "$TOOLS" "$BIN"

# ---------------------------------------------------------------------------
# 1. Distribution packages
# ---------------------------------------------------------------------------
PKGS=(
	# kernel build
	build-essential bc bison flex libssl-dev libelf-dev dwarves pahole cpio kmod
	rsync python3 python3-venv git ccache zstd lz4 xz-utils gzip lzop
	libncurses-dev pkg-config gawk
	# optional LLVM build (pmOS kernels use LLVM=1)
	clang lld llvm
	# device tree tools: dtc, fdtput, fdtget, fdtdump
	device-tree-compiler python3-libfdt
	# Android boot image tools (AOSP mkbootimg/unpack_bootimg/repack_bootimg)
	mkbootimg abootimg android-sdk-libsparse-utils
	# reading partition dumps: modem.img/bluetooth.img are vfat, dsp.img is ext4
	mtools e2fsprogs dosfstools
	# mini initramfs
	busybox-static fakeroot
	# dt-schema validation (make dtbs_check): pylibfdt wheel needs Python.h + swig
	python3-dev swig yamllint
	# misc
	u-boot-tools shellcheck curl ca-certificates file jq unzip sudo
	openssl
)
if [ "$(uname -m)" != "aarch64" ]; then
	PKGS+=(gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu)
fi

info "Installing packages (${#PKGS[@]})"
sudo apt-get update -qq
# Install one by one on failure so a single renamed package does not block the rest.
if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${PKGS[@]}"; then
	warn "Bulk install failed, retrying per package"
	for p in "${PKGS[@]}"; do
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$p" || warn "package not installed: $p"
	done
fi

# ---------------------------------------------------------------------------
# 2. pil-squasher (mdt+bNN -> single mbn), from source
# ---------------------------------------------------------------------------
if ! command -v pil-squasher >/dev/null; then
	info "Building pil-squasher"
	if [ ! -d "$TOOLS/pil-squasher/.git" ]; then
		git clone --depth 1 https://github.com/linux-msm/pil-squasher.git "$TOOLS/pil-squasher"
	fi
	make -C "$TOOLS/pil-squasher"
	install -m 0755 "$TOOLS/pil-squasher/pil-squasher" "$BIN/pil-squasher"
	if [ -x "$TOOLS/pil-squasher/pil-splitter" ]; then
		install -m 0755 "$TOOLS/pil-squasher/pil-splitter" "$BIN/pil-splitter"
	fi
fi

# ---------------------------------------------------------------------------
# 3. ath11k-bdencoder (board-2.bin builder) from qca-swiss-army-knife
# ---------------------------------------------------------------------------
if ! command -v ath11k-bdencoder >/dev/null; then
	info "Fetching ath11k-bdencoder"
	if [ ! -d "$TOOLS/qca-swiss-army-knife/.git" ]; then
		git clone --depth 1 --filter=blob:none --sparse \
			https://github.com/qca/qca-swiss-army-knife.git "$TOOLS/qca-swiss-army-knife"
		git -C "$TOOLS/qca-swiss-army-knife" sparse-checkout set tools/scripts/ath11k tools/scripts/ath10k
	fi
	ln -sf "$TOOLS/qca-swiss-army-knife/tools/scripts/ath11k/ath11k-bdencoder" "$BIN/ath11k-bdencoder"
fi

# ---------------------------------------------------------------------------
# 4. pmbootstrap from git
# ---------------------------------------------------------------------------
if [ ! -d "$TOOLS/pmbootstrap/.git" ]; then
	info "Cloning pmbootstrap"
	git clone --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$TOOLS/pmbootstrap"
else
	git -C "$TOOLS/pmbootstrap" pull --ff-only -q || warn "pmbootstrap update failed (offline?)"
fi
ln -sf "$TOOLS/pmbootstrap/pmbootstrap.py" "$BIN/pmbootstrap"

# ---------------------------------------------------------------------------
# 4b. dtschema (dt-validate) in a venv for `make dtbs_check`
# ---------------------------------------------------------------------------
if [ ! -x "$WORK/venv-dt/bin/dt-validate" ]; then
	info "Installing dtschema into $WORK/venv-dt"
	python3 -m venv "$WORK/venv-dt"
	"$WORK/venv-dt/bin/pip" install -q dtschema || warn "dtschema install failed (dtbs_check unavailable)"
fi
for t in dt-validate dt-mk-schema dt-doc-validate; do
	[ -x "$WORK/venv-dt/bin/$t" ] && ln -sf "$WORK/venv-dt/bin/$t" "$BIN/$t"
done

# ---------------------------------------------------------------------------
# 5. PATH and summary
# ---------------------------------------------------------------------------
if ! grep -qs 'HOME/.local/bin' "$HOME/.profile"; then
	# shellcheck disable=SC2016  # literal $HOME/$PATH wanted in .profile
	echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
fi
export PATH="$BIN:$PATH"

git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "nicole-builder"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "nicole-builder@localhost"

info "Tool check:"
for t in gcc make dtc fdtput mkbootimg unpack_bootimg abootimg simg2img mcopy debugfs \
	busybox fakeroot pil-squasher ath11k-bdencoder pmbootstrap shellcheck dt-validate; do
	if command -v "$t" >/dev/null; then
		printf '  %-18s %s\n' "$t" "$(command -v "$t")"
	else
		printf '  %-18s MISSING\n' "$t"
	fi
done
if busybox --list 2>/dev/null | grep -qx telnetd; then
	info "busybox-static has telnetd (mini initramfs will use it)"
else
	warn "busybox-static has no telnetd: mini initramfs falls back to 'nc -ll -e' + USB ACM shell"
fi

cat <<EOF

Next steps:
  1) pmbootstrap init           # work dir: $WORK/pmbootstrap ; device: later 'razer-nicole'
     (copy the drafts from <project>/pmaports/* into \$(pmbootstrap config aports)/device/testing/)
  2) bash <project>/scripts/build/build-kernel.sh            # mainline + nicole DTS/patches
  3) bash <project>/scripts/build/mkinitramfs-mini.sh
  4) bash <project>/scripts/build/make-bootimg.sh            # boot images for docs/boot-plani.md
EOF
