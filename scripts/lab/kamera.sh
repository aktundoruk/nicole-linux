#!/usr/bin/env bash
# Take a photo of the device screen with the webcam.
# Usage: kamera.sh [etiket]   → prints the path of the saved JPEG
# The agent's Bash tool has no camera access on macOS: when kamera-servis.sh runs in a
# Terminal-panel tab, the photo is taken there; otherwise imagesnap is called directly.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli imagesnap

KAMERA="${RAZER_KAMERA:-}"   # device name from `imagesnap -l`; empty = default camera
SERVIS="${RAZER_KAMERA_DIZIN:-/tmp/razer-kamera}"
DIZIN="$LOG_DIR/kamera/$(date +%Y-%m-%d)"
mkdir -p "$DIZIN"
DOSYA="$DIZIN/$(damga)-${1:-ekran}.jpg"

if [ -f "$SERVIS/servis.pid" ] && kill -0 "$(cat "$SERVIS/servis.pid")" 2>/dev/null; then
	rm -f "$SERVIS/sonuc"
	echo "$DOSYA" > "$SERVIS/istek"
	for _ in $(seq 1 50); do [ -f "$SERVIS/sonuc" ] && break; sleep 0.2; done
	case "$(cat "$SERVIS/sonuc" 2>/dev/null)" in
		tamam*) ;;
		*) hata "kamera-servis fotoğraf çekemedi ($(cat "$SERVIS/sonuc" 2>/dev/null || echo zaman aşımı))" ;;
	esac
elif [ -n "$KAMERA" ]; then
	imagesnap -q -w 1.5 -d "$KAMERA" "$DOSYA"
else
	imagesnap -q -w 1.5 "$DOSYA"
fi
echo "$DOSYA"
