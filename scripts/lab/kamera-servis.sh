#!/usr/bin/env bash
# Camera helper that runs in the Claude app's Terminal panel.
#
# Why: macOS gives camera access to the Claude app (and the shells of its Terminal
# panel), but not to the agent's own Bash tool, which gets "Camera access not granted"
# with no prompt. This loop runs in a Terminal-panel tab and takes a photo whenever
# scripts/lab/kamera.sh drops a request file.
#
# Usage (Terminal panel): scripts/lab/kamera-servis.sh      Ctrl-C to stop
# Protocol: kamera.sh writes "<output.jpg>" into $DIZIN/istek; this loop captures to
# that path, then writes "tamam <path>" or "hata <msg>" into $DIZIN/sonuc.
set -uo pipefail

DIZIN="${RAZER_KAMERA_DIZIN:-/tmp/razer-kamera}"
KAMERA="${RAZER_KAMERA:-}"
BEKLE="${RAZER_KAMERA_BEKLE:-1.5}"   # warm-up seconds (Continuity iPhone needs ~4)
mkdir -p "$DIZIN"
rm -f "$DIZIN/istek" "$DIZIN/sonuc"
echo "$$" > "$DIZIN/servis.pid"
trap 'rm -f "$DIZIN/servis.pid"; exit 0' INT TERM
echo "kamera-servis: istek bekleniyor ($DIZIN/istek). Durdurmak için Ctrl-C."

while :; do
	if [ -f "$DIZIN/istek" ]; then
		hedef="$(cat "$DIZIN/istek")"
		rm -f "$DIZIN/istek"
		if [ -n "$KAMERA" ]; then
			imagesnap -q -w "$BEKLE" -d "$KAMERA" "$hedef" >/dev/null 2>&1
		else
			imagesnap -q -w "$BEKLE" "$hedef" >/dev/null 2>&1
		fi
		if [ -s "$hedef" ]; then echo "tamam $hedef" > "$DIZIN/sonuc"; else echo "hata imagesnap" > "$DIZIN/sonuc"; fi
		echo "$(date +%T) $hedef"
	fi
	sleep 0.3
done
