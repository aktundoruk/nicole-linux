#!/bin/bash
# Build uyku_iz.ko in the Lima VM against the kernel build tree and fix its vermagic to match the
# packaged kernel (no MODVERSIONS, same config; the build tree's release just carries a "+").
# Output: out/tmp/uyku_iz.ko
set -euo pipefail
W=/mnt/lima-razer-build; K=$W/src/linux-v7.3-rc6; B=$W/build/linux-v7.3-rc6
P=$(cd "$(dirname "$0")/../../../.." && pwd); D=$W/uyku-iz
rm -rf "$D"; mkdir -p "$D"; cp "$P/scripts/lab/modul/uyku-iz/uyku_iz.c" "$D/"
{ echo '/* copied from drivers/clk/clk.c: the struct is private there */'
  awk '/^struct clk_core \{/{f=1} f{print} f&&/^\};/{exit}' "$K/drivers/clk/clk.c"; } > "$D/clk_core.h"
cp "$K/drivers/pci/controller/dwc/pcie-designware.h" "$K/drivers/regulator/internal.h" "$D/"
cp "$K/drivers/interconnect/internal.h" "$D/icc_internal.h"
cat > "$D/Makefile" <<M
obj-m := uyku_iz.o
ccflags-y := -I\$(src) -I$K/drivers/pci/controller/dwc -Wno-missing-prototypes
M
make -C "$K" O="$B" M="$D" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules 2>&1 | tail -15
perl -0pi -e 's/(vermagic=7\.3\.0-rc6-nicole)\+( SMP[^\0]*)\0/$1$2\0\0/' "$D/uyku_iz.ko"
mkdir -p "$P/out/tmp"; cp "$D/uyku_iz.ko" "$P/out/tmp/uyku_iz.ko"
strings "$D/uyku_iz.ko" | grep -m1 vermagic=
diff <(grep -E '^(# )?CONFIG_' "$B/.config" | grep -vE 'CC_VERSION|GCC_VERSION|AS_VERSION|LD_VERSION|PAHOLE|CC_IS|LD_IS|AS_IS|RUSTC|BUILD_SALT') \
     <(grep -E '^(# )?CONFIG_' "$P/pmaports/linux-razer-nicole/config-razer-nicole.aarch64" | grep -vE 'CC_VERSION|GCC_VERSION|AS_VERSION|LD_VERSION|PAHOLE|CC_IS|LD_IS|AS_IS|RUSTC|BUILD_SALT') | head -20 || true
