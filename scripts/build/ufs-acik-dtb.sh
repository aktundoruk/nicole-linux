#!/usr/bin/env bash
# DTB for a full-system boot that can see the internal UFS. The normal DTS keeps both
# nodes disabled (docs/guvenlik-kurallari.md §2); this flips them in a copy, for one flash at a time.
# What protects the disk is the kernel's write guard (drivers/ufs/0001-*), so only use
# this with a kernel that has it: /sys/module/ufshcd_core/parameters/write_ranges exists.
#
# Usage (in the build VM): ufs-acik-dtb.sh IN.dtb OUT.dtb
set -euo pipefail
in=${1:?girdi dtb}; out=${2:?cikti dtb}
cp "$in" "$out"
ufs=$(fdtget -l "$out" /soc@0 | grep -E '^ufshc@|^ufs@' | head -1)
phy=$(fdtget -l "$out" /soc@0 | grep -E '^phy@1d87000' | head -1)
[ -n "$ufs" ] && [ -n "$phy" ] || { echo "UFS düğümleri yok: $in" >&2; exit 1; }
fdtput -t s "$out" "/soc@0/$ufs" status okay
fdtput -t s "$out" "/soc@0/$phy" status okay
echo "açıldı: /soc@0/$ufs /soc@0/$phy"
