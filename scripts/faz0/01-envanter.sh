#!/usr/bin/env bash
# Faz 0 / Adım 1 — Read-only hardware and software inventory over adb.
# Works without root; collects more when root (Magisk `su`) is available.
# Writes nothing to the device.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"

gerekli adb dtc
dur_kontrol

CIKTI="$YEDEK_KOK/envanter-$(damga)"
mkdir -p "$CIKTI"/{props,sys,dumpsys,dt}
eylem_kaydet "envanter başladı → $CIKTI"

[ "$(ab get-state 2>/dev/null)" = "device" ] || hata "adb ile bağlı cihaz yok (USB hata ayıklama açık mı, izin verildi mi?)"

ab shell getprop > "$CIKTI/props/getprop.txt"
sku=$(ab shell getprop ro.boot.hardware.sku | tr -d '\r')
cihaz=$(ab shell getprop ro.product.device | tr -d '\r')
bilgi "Cihaz: $cihaz  SKU: $sku"
case "$cihaz" in
	nicole|Razer-Edge-WiFi|RZ45-0460) ;;
	*) hata "Beklenmeyen cihaz: '$cihaz'. Bu betik yalnız Razer Edge (nicole) içindir.";;
esac
[ "$sku" = "wifi" ] || uyari "SKU 'wifi' değil ('$sku'). Plan Wi‑Fi modeline göre yazıldı."

kok_var=false
if ab shell 'su -c id' 2>/dev/null | grep -q 'uid=0'; then
	kok_var=true
	bilgi "Root erişimi var, ayrıntılı envanter alınacak"
else
	uyari "Root yok: bazı dosyalar (dmesg, cmdline, DT) eksik kalabilir"
fi

# Run a command on the device, as root if available; stdout only
cihazda() {
	if $kok_var; then
		ab exec-out "su -c '$1'" 2>/dev/null || true
	else
		ab exec-out "$1" 2>/dev/null || true
	fi
}

bilgi "Sistem bilgisi"
for f in /proc/cpuinfo /proc/meminfo /proc/cmdline /proc/version /proc/modules /proc/partitions /proc/iomem /proc/interrupts /proc/bootconfig; do
	cihazda "cat $f" > "$CIKTI/sys/$(basename "$f").txt"
done
cihazda "dmesg" > "$CIKTI/sys/dmesg.txt"
cihazda "ls -l /dev/block/by-name/" > "$CIKTI/sys/by-name.txt"
cihazda "for b in /sys/class/block/sd*; do echo \$(basename \$b) \$(cat \$b/size 2>/dev/null) \$(cat \$b/device/model 2>/dev/null); done" > "$CIKTI/sys/block-sizes.txt"
cihazda "cat /sys/devices/soc0/*" > "$CIKTI/sys/soc0.txt"
cihazda "for f in /sys/devices/soc0/*; do echo \$f: \$(cat \$f 2>/dev/null); done" > "$CIKTI/sys/soc0-detay.txt"

bilgi "Termal bölgeler ve güç kaynakları"
cihazda 'for z in /sys/class/thermal/thermal_zone*; do echo "$(basename $z) $(cat $z/type) $(cat $z/temp)"; done' > "$CIKTI/sys/thermal.txt"
cihazda 'for c in /sys/class/thermal/cooling_device*; do echo "$(basename $c) $(cat $c/type) $(cat $c/cur_state)/$(cat $c/max_state)"; done' > "$CIKTI/sys/cooling.txt"
cihazda 'for p in /sys/class/power_supply/*; do echo "== $p"; cat $p/uevent; done' > "$CIKTI/sys/power_supply.txt"
cihazda 'for t in /sys/class/typec/*; do echo "== $t"; ls $t; cat $t/*role 2>/dev/null; done' > "$CIKTI/sys/typec.txt"
cihazda 'ls -l /sys/class/hwmon/; for h in /sys/class/hwmon/*; do echo "== $h $(cat $h/name)"; ls $h; done' > "$CIKTI/sys/hwmon.txt"

bilgi "Veri yolları (I2C/SPI/PCIe/USB) ve giriş aygıtları"
cihazda 'for d in /sys/bus/i2c/devices/*; do echo "$(basename $d) $(cat $d/name 2>/dev/null) drv=$(basename $(readlink $d/driver) 2>/dev/null)"; done' > "$CIKTI/sys/i2c.txt"
cihazda 'for d in /sys/bus/spi/devices/*; do echo "$(basename $d) $(cat $d/modalias 2>/dev/null) drv=$(basename $(readlink $d/driver) 2>/dev/null)"; done' > "$CIKTI/sys/spi.txt"
cihazda 'for d in /sys/bus/pci/devices/*; do echo "$(basename $d) $(cat $d/vendor):$(cat $d/device) class=$(cat $d/class)"; done' > "$CIKTI/sys/pci.txt"
cihazda 'cat /sys/kernel/debug/usb/devices 2>/dev/null; for d in /sys/bus/usb/devices/*; do echo "$(basename $d) $(cat $d/idVendor 2>/dev/null):$(cat $d/idProduct 2>/dev/null) $(cat $d/product 2>/dev/null)"; done' > "$CIKTI/sys/usb.txt"
cihazda 'getevent -pl' > "$CIKTI/sys/getevent.txt"
cihazda 'cat /proc/bus/input/devices' > "$CIKTI/sys/input-devices.txt"
# FocalTech touch: vendor driver usually exposes chip/firmware info under sysfs
cihazda 'find /sys -maxdepth 6 -iname "*fts*" 2>/dev/null | head -50; cat /sys/bus/spi/devices/spi*/fts_fw_version 2>/dev/null' > "$CIKTI/sys/touch-fts.txt"
# Fan controller (MAX31760) as seen by the vendor driver
cihazda 'find /sys -maxdepth 6 -iname "*max31760*" 2>/dev/null; find /sys -maxdepth 6 -iname "*fan*" -path "*i2c*" 2>/dev/null | head -20' > "$CIKTI/sys/fan.txt"
# Display panel / DSI
cihazda 'cat /sys/class/drm/*/modes 2>/dev/null; ls /sys/class/drm/; cat /sys/kernel/debug/dri/0/name 2>/dev/null' > "$CIKTI/sys/drm.txt"
cihazda 'cat /sys/class/backlight/*/max_brightness /sys/class/backlight/*/brightness 2>/dev/null' > "$CIKTI/sys/backlight.txt"
# Regulators (names, voltages, enable state)
cihazda 'for r in /sys/class/regulator/regulator.*; do echo "$(cat $r/name 2>/dev/null) $(cat $r/microvolts 2>/dev/null) $(cat $r/state 2>/dev/null)"; done' > "$CIKTI/sys/regulators.txt"
# GPIO usage (needs debugfs + root)
cihazda 'cat /sys/kernel/debug/gpio 2>/dev/null; cat /sys/kernel/debug/pinctrl/*/pinmux-pins 2>/dev/null | head -400' > "$CIKTI/sys/gpio.txt"
# Clocks summary (for clk_ignore_unused decisions)
cihazda 'cat /sys/kernel/debug/clk/clk_summary 2>/dev/null | head -600' > "$CIKTI/sys/clk_summary.txt"
# Reserved memory as the running kernel sees it
cihazda 'ls /proc/device-tree/reserved-memory/; for n in /proc/device-tree/reserved-memory/*; do echo "== $n"; xxd -p $n/reg 2>/dev/null || od -An -tx1 $n/reg 2>/dev/null; done' > "$CIKTI/sys/reserved-memory.txt"

bilgi "dumpsys (referans davranış)"
for s in battery display SurfaceFlinger thermalservice power usb input wifi; do
	ab shell dumpsys "$s" > "$CIKTI/dumpsys/$s.txt" 2>/dev/null || true
done

bilgi "Çalışan cihaz ağacı"
if $kok_var; then
	ab exec-out "su -c 'cat /sys/firmware/fdt'" > "$CIKTI/dt/fdt.dtb"
	if [ -s "$CIKTI/dt/fdt.dtb" ]; then
		dtc -I dtb -O dts -o "$CIKTI/dt/fdt.dts" "$CIKTI/dt/fdt.dtb" 2>"$CIKTI/dt/dtc-uyarilar.txt" || uyari "dtc çözümlemesi kısmen başarısız"
		bilgi "DT çözüldü: $CIKTI/dt/fdt.dts"
	else
		uyari "/sys/firmware/fdt okunamadı"
	fi
fi

bilgi "Firmware dosya listesi (içerik değil)"
cihazda 'ls -lR /vendor/firmware_mnt/image /vendor/firmware /vendor/dsp /vendor/bt_firmware /odm/firmware 2>/dev/null' > "$CIKTI/sys/firmware-liste.txt"
cihazda 'ls -lR /mnt/vendor/persist 2>/dev/null' > "$CIKTI/sys/persist-liste.txt"

find "$CIKTI" -type f -empty -delete
( cd "$CIKTI" && find . -type f -exec shasum -a 256 {} + > SHA256SUMS )
eylem_kaydet "envanter tamam → $CIKTI"
bilgi "Bitti: $CIKTI ($(du -sh "$CIKTI" | cut -f1))"
