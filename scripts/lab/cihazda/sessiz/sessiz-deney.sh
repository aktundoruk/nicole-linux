#!/bin/sh
# Silent-boot ADSP / deep-sleep experiment (1 Kasım 2026). Runs from sessiz-deney.service only
# on a boot where sessiz-erken.service kept the LPASS audio stack out (uyku-sessiz.conf).
# Question: with no macro, SoundWire, WCD938x or LPI pinctrl ever loaded (no LPASS votes),
# does the ADSP power-collapse, and does the SoC reach AOSD/CXSD? Pull the USB-C cable
# (nothing may stay plugged in) and don't ssh in (sshd blocks suspend). ~10 min:
#   1) awake, screen off, 180 s
#   2) 120 s s2idle, Bluetooth rfkill-blocked
#   3) 120 s s2idle, Bluetooth on
# Ends with a reboot; the next boot has audio again (/run is tmpfs).
# Results: /var/lib/uyku-test/sessiz-<time>/sonuc.txt, path in /var/lib/uyku-test/son-sessiz
D=/var/lib/uyku-test/sessiz-$(date +%H%M%S); mkdir -p $D; R=$D/sonuc.txt
echo $D > /var/lib/uyku-test/son-sessiz
rm -f /var/lib/uyku-test/sessiz-bir-kez  # one boot only
B=/sys/class/power_supply/qcom-battmgr-bat
Q=/sys/kernel/debug/qcom_stats
modprobe qcom_stats 2>/dev/null
say() { echo "$(date +%T) $*" >> $R; }
sayac() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" a}' $Q/$1; }
anlik() {
	s=""; for f in adsp slpi aosd cxsd ddr; do s="$s $f=$(sayac $f)"; done
	say "$1 yuk=$(cat $B/charge_counter) akim=$(cat $B/current_now) usb=$(cat /sys/class/power_supply/qcom-battmgr-usb/online)$s"
}
oy() { awk '/LPASS_HW_MACRO|LPASS_HW_DCODEC|TX_CORE_MCLK|VA_CORE_MCLK/{printf "%s=%s ", $1, $2}' /sys/kernel/debug/clk/clk_summary; }
uyu() {
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$1 > /sys/class/rtc/rtc0/wakealarm
	systemctl suspend -i 2>>$R || systemctl suspend 2>>$R
	sleep 3
	while systemctl -q is-active systemd-suspend.service ||
		[ "$(systemctl show -P ActiveState systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 2
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	say "uyandiran irq=$w $(grep -E "^ *$w:" /proc/interrupts | awk '{$1=""; for(i=2;i<=9;i++)$i=""; print}')"
	say "suspend sonucu: $(systemctl show -P Result systemd-suspend.service)"
}
say "engel: $(grep -o '^install [^ ]*' /run/modprobe.d/uyku-sessiz.conf | cut -d' ' -f2 | tr '\n' ' ')"
say "yüklü ses modülleri: $(lsmod | awk '/snd_soc_sm8250|lpass|wcd938x|soundwire_qcom/{printf "%s ", $1}')"
say "kart: $(cat /proc/asound/cards | head -1)"
say "oy (açılış): $(oy)"
say "bekliyor: kablo (USB-C boş olmalı)"
n=0
while [ "$(cat /sys/class/power_supply/qcom-battmgr-usb/online)" = 1 ] || [ -e /sys/class/typec/port0-partner ]; do
	sleep 2; n=$((n+1)); [ $n -gt 5400 ] && { say "kablo 3 saat çıkmadı, vazgeçtim"; rm -f /run/modprobe.d/uyku-sessiz.conf; exit 0; }
done
sleep 20  # ssh sessions die, the gauge settles
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
anlik "1-once (uyanik, ekran kapali) oy: $(oy)"; sleep 180; anlik "1-sonra"
rfkill block bluetooth; sleep 3
anlik "2-once (uyku, BT kapali)"; uyu 120; anlik "2-sonra"
rfkill unblock bluetooth; sleep 3
anlik "3-once (uyku, BT acik)"; uyu 120; anlik "3-sonra"
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $D/genpd
cat /sys/kernel/debug/interconnect/interconnect_summary > $D/icc 2>/dev/null
journalctl -b --since "-15min" --no-pager | grep -E "nicole-uyku|PM: suspend|inhibit|Suspend|wakeup|Oops|BUG" >> $D/gunluk
say "bitti, yeniden başlatılıyor"
sync
# A suspend still in flight refuses a reboot ("Action suspend already in progress"): retry.
for i in 1 2 3 4 5; do systemctl reboot && exit 0; say "reboot reddedildi ($i)"; sleep 20; done
sync; systemctl reboot --force
