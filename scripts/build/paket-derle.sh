#!/bin/bash
# Sync this checkout's pmaports packages into pmbootstrap's aports, checksum and build them.
# Run inside the build VM (or any Linux host with pmbootstrap set up for razer-nicole).
# Usage: paket-derle.sh [package ...]   (default: device-razer-nicole linux-razer-nicole)
set -euo pipefail
P=$(cd "$(dirname "$0")/../.." && pwd)
A=$(pmbootstrap config aports)
PKGS=("$@"); [ ${#PKGS[@]} -gt 0 ] || PKGS=(device-razer-nicole linux-razer-nicole)
for p in "${PKGS[@]}"; do
	# a fork of an existing aport (e.g. temp/libcamera) replaces it in place, else device/testing
	d=$(find "$A" -mindepth 2 -maxdepth 3 -type d -name "$p" -not -path "*/.git/*" | head -1)
	[ -n "$d" ] || d="$A/device/testing/$p"
	rm -rf "$d"; cp -R "$P/pmaports/$p" "$d"
done
pmbootstrap -q checksum "${PKGS[@]}"
for p in "${PKGS[@]}"; do
	d=$(find "$A" -mindepth 2 -maxdepth 3 -type d -name "$p" -not -path "*/.git/*" | head -1)
	cp "$d/APKBUILD" "$P/pmaports/$p/APKBUILD"
done
for p in "${PKGS[@]}"; do date; pmbootstrap -q build --force "$p" && echo "$p OK"; done
date; ls -la "$(pmbootstrap config work)"/packages/edge/*/ | grep -E "razer|nicole|libcamera"
