#!/usr/bin/env bash
# Put the Razer video (iris, VPU 2.0) firmware on the phone (31 Ekim 2026), from the LOCAL dump:
#   vendor_b.img:/firmware/vpu20_4v.mbn -> /lib/firmware/qcom/sm8350/razer/nicole/vpu20_4v.mbn
# Single-file .mbn, signed for this SoC (TZ checks it), so linux-firmware's files do not
# fit (docs/firmware-listesi.md §4). Razer's file: it stays on this Mac and the phone,
# never in a package, a commit or an upload (docs/guvenlik-kurallari.md §2).
#
# Usage: video-firmware.sh   (env: RAZER_IP, default 172.16.42.1 = USB; or the phone's Wi-Fi address)
# Needs: the Lima VM "razer" (debugfs reads the ext4 image), ssh key razer_nicole.
set -euo pipefail
PROJE="$(cd "$(dirname "$0")/../.." && pwd)"
YEDEK=${YEDEK:-$PROJE/yedek}
VENDOR=$YEDEK/firmware-20261028-222216/vendor_b.img
IP=${RAZER_IP:-172.16.42.1}
GECICI="$PROJE/out/tmp/video-firmware"
SSHO=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      -o LogLevel=ERROR -i "$HOME/.ssh/razer_nicole")
[ -f "$VENDOR" ] || { echo "yok: $VENDOR" >&2; exit 1; }

rm -rf "$GECICI"; mkdir -p "$GECICI"
LIMA_HOME=${LIMA_HOME:-$HOME/.lima} limactl shell razer -- \
	debugfs -R "dump /firmware/vpu20_4v.mbn $GECICI/vpu20_4v.mbn" "$VENDOR" 2>/dev/null
[ "$(wc -c < "$GECICI/vpu20_4v.mbn")" -eq 2031460 ] || { echo "çıkarılamadı" >&2; exit 1; }
scp -q "${SSHO[@]}" "$GECICI/vpu20_4v.mbn" "user@$IP:/tmp/vpu20_4v.mbn"
ssh "${SSHO[@]}" "user@$IP" 'doas install -Dm644 /tmp/vpu20_4v.mbn \
	/lib/firmware/qcom/sm8350/razer/nicole/vpu20_4v.mbn && rm /tmp/vpu20_4v.mbn &&
	ls -l /lib/firmware/qcom/sm8350/razer/nicole/vpu20_4v.mbn'
rm -rf "$GECICI"
