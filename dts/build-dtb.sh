#!/usr/bin/env bash
# Build the Razer Edge Wi-Fi ("nicole") draft DTB against the mainline tree.
#
# Usage: dts/build-dtb.sh [file.dts]   (default: dts/sm8350-razer-nicole.dts)
# Output: dts/out/<name>.dtb (+ preprocessed .dts.tmp for debugging)
#
# Env overrides: LINUX=<mainline tree>  DTC=<dtc binary>  CPP=<cpp binary>
#                DTC_FLAGS="extra dtc flags"
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LINUX="${LINUX:-$ROOT/sources/linux-mainline}"
DTC="${DTC:-dtc}"
# Apple's /usr/bin/cpp wrapper mangles "-x assembler-with-cpp"; on macOS
# call the clang driver in preprocess mode instead (same preprocessor).
if [ -z "${CPP:-}" ]; then
	if [ "$(uname -s)" = "Darwin" ]; then CPP="clang -E"; else CPP="cpp"; fi
fi
SRC="${1:-$HERE/sm8350-razer-nicole.dts}"
NAME="$(basename "$SRC" .dts)"
OUT="$HERE/out"

mkdir -p "$OUT"

for d in include arch/arm64/boot/dts/qcom scripts/dtc/include-prefixes; do
	if [ ! -d "$LINUX/$d" ]; then
		echo "error: $LINUX/$d missing (sparse checkout?)" >&2
		exit 1
	fi
done

# Same preprocessing as the kernel's cmd_dtc (scripts/Makefile.dtbs).
$CPP -nostdinc -undef -D__DTS__ -x assembler-with-cpp -P \
	-I "$LINUX/include" \
	-I "$LINUX/arch/arm64/boot/dts/qcom" \
	-I "$LINUX/scripts/dtc/include-prefixes" \
	-I "$HERE" \
	"$SRC" -o "$OUT/$NAME.dts.tmp"

# -@ : keep symbols so overlays can be applied later.
# The two silenced checks only fire on sm8350.dtsi itself (QUP i2c/spi/uart
# nodes sharing a unit address, dsi1 #address-cells); the kernel's own
# Makefile.dtbs silences them too. Everything else stays enabled.
"$DTC" -I dts -O dtb -@ \
	-Wno-unique_unit_address \
	-Wno-avoid_unnecessary_addr_size \
	${DTC_FLAGS:-} \
	-o "$OUT/$NAME.dtb" "$OUT/$NAME.dts.tmp"

echo "OK: $OUT/$NAME.dtb ($(wc -c < "$OUT/$NAME.dtb") bytes)"
