#!/usr/bin/env bash
# Put the Razer files the sensors need on the phone (30 Ekim 2026), from the LOCAL dump:
#   slpi.mbn                     -> /lib/firmware/qcom/sm8350/razer/nicole/
#   dsp_b.img:/sdsp              -> /usr/share/qcom/sm8350/razer/nicole/dsp/sdsp/
#   vendor_b.img:/etc/sensors/config, sns_reg_config
#                                -> /usr/share/qcom/sm8350/razer/nicole/sensors/
# The rest (socinfo, writable registry, hexagonrpcd-yazma, services) comes from
# device-razer-nicole. These files are Razer's: they stay on this Mac and the phone,
# never in a package, a commit or an upload (docs/guvenlik-kurallari.md §2). persist is not touched: the
# SLPI builds its own registry in /var/lib/hexagonrpcd/persist-sensors.
#
# Usage: sensor-dosyalari.sh   (env: RAZER_IP, default 172.16.42.1 = USB)
# Needs: the Lima VM "razer" (debugfs reads the ext4 images), ssh key razer_nicole.
set -euo pipefail
PROJE="$(cd "$(dirname "$0")/../.." && pwd)"
YEDEK=${YEDEK:-$PROJE/yedek}
MBN=$YEDEK/firmware-20261025-125529/mbn/slpi.mbn
DSP=$YEDEK/firmware-20261025-125529/dsp_b.img
VENDOR=$YEDEK/firmware-20261028-222216/vendor_b.img
IP=${RAZER_IP:-172.16.42.1}
GECICI="$PROJE/out/tmp/sensor-dosyalari"
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o LogLevel=ERROR -i "$HOME/.ssh/razer_nicole" "user@$IP")
for f in "$MBN" "$DSP" "$VENDOR"; do [ -f "$f" ] || { echo "yok: $f" >&2; exit 1; }; done

rm -rf "$GECICI"; mkdir -p "$GECICI/q/dsp" "$GECICI/q/sensors"
LIMA_HOME=${LIMA_HOME:-$HOME/.lima} limactl shell razer -- bash -c "
	set -e
	debugfs -R 'rdump /sdsp $GECICI/q/dsp' '$DSP' 2>/dev/null
	debugfs -R 'rdump /etc/sensors/config $GECICI/q/sensors' '$VENDOR' 2>/dev/null
	debugfs -R 'dump /etc/sensors/sns_reg_config $GECICI/q/sensors/sns_reg.conf' '$VENDOR' 2>/dev/null"
[ -s "$GECICI/q/sensors/sns_reg.conf" ] && [ -d "$GECICI/q/dsp/sdsp" ] || { echo "çıkarılamadı" >&2; exit 1; }
cp "$MBN" "$GECICI/slpi.mbn"
COPYFILE_DISABLE=1 tar czf "$GECICI.tgz" -C "$GECICI" .
scp -q -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR -i "$HOME/.ssh/razer_nicole" "$GECICI.tgz" "user@$IP:/tmp/sensor-dosyalari.tgz"
"${SSH[@]}" 'set -e
	t=$(mktemp -d); tar xzf /tmp/sensor-dosyalari.tgz -C $t; rm /tmp/sensor-dosyalari.tgz
	doas install -Dm644 $t/slpi.mbn /lib/firmware/qcom/sm8350/razer/nicole/slpi.mbn
	D=/usr/share/qcom/sm8350/razer/nicole; doas mkdir -p $D
	doas cp -r $t/q/dsp $t/q/sensors $D/ && doas chmod -R a+rX $D
	rm -rf $t; echo "telefonda: $(ls $D/dsp/sdsp | wc -l) dsp, $(ls $D/sensors/config | wc -l) ayar"'
rm -rf "$GECICI" "$GECICI.tgz"
