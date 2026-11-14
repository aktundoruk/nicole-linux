#!/usr/bin/env bash
# Build the Faz 3 firmware-extraction boot set (inside the build VM): mini initramfs
# with "nicole.ufsro" (every sd* set read-only on appearance) + the latest DTB with
# ufs_mem_hc / ufs_mem_phy enabled. Only for scripts/lab/ufs-oku.sh; the normal DTS
# keeps UFS disabled (docs/guvenlik-kurallari.md §8, Faz 3 dar).
#
# Usage: ufs-oku-imaj.sh            -> <project>/out/ufs-oku/d5-*.img
# Never touches the phone.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${RAZER_PROJECT:-$(cd "$HERE/../.." && pwd)}"
WORK="${WORK:-/mnt/lima-razer-build}"
OUT="$PROJECT/out/ufs-oku"
DTB_IN="$WORK/out/latest/sm8350-razer-nicole.dtb"

die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = "Linux" ] || die "run inside the build VM"
[ -f "$DTB_IN" ] || die "missing $DTB_IN (build-kernel.sh)"

mkdir -p "$OUT"
DTB="$OUT/sm8350-razer-nicole-ufs.dtb"
cp "$DTB_IN" "$DTB"
ufs=$(fdtget -l "$DTB" /soc@0 | grep -E '^ufshc@|^ufs@' | head -1)
phy=$(fdtget -l "$DTB" /soc@0 | grep -E '^phy@1d87000' | head -1)
[ -n "$ufs" ] && [ -n "$phy" ] || die "UFS nodes not found in $DTB_IN"
fdtput -t s "$DTB" "/soc@0/$ufs" status okay
fdtput -t s "$DTB" "/soc@0/$phy" status okay
echo "enabled: /soc@0/$ufs /soc@0/$phy"

"$HERE/mkinitramfs-mini.sh"
"$HERE/make-bootimg.sh" --only d5 --out "$OUT" --dtb "$DTB" --extra "nicole.ufsro nicole.oto_donus=200"
