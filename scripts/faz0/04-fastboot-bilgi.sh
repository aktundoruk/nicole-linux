#!/usr/bin/env bash
# Faz 0 / Adım 4 — Read-only bootloader information (fastboot getvar).
# The device must already be in fastboot mode (adb reboot bootloader).
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"

gerekli fastboot
dur_kontrol

fastboot devices | grep -q fastboot || hata "fastboot modunda cihaz yok. 'adb reboot bootloader' ile girin."

CIKTI="$YEDEK_KOK/fastboot-$(damga)"
mkdir -p "$CIKTI"
# getvar prints to stderr
fb getvar all > "$CIKTI/getvar-all.txt" 2>&1 || true
for v in product current-slot unlocked secure slot-count max-download-size is-userspace version-bootloader version-baseband hw-revision; do
	printf '%s: ' "$v" >> "$CIKTI/ozet.txt"
	fb getvar "$v" 2>&1 | head -1 | sed 's/^[^:]*: //' >> "$CIKTI/ozet.txt" || true
done
cat "$CIKTI/ozet.txt"
grep -qi 'unlocked: *yes' "$CIKTI/ozet.txt" || uyari "Bootloader kilitli görünüyor; fastboot boot çalışmaz."
bilgi "Bitti: $CIKTI"
