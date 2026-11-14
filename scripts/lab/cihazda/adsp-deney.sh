#!/bin/sh
# Unplugged ADSP / deep-sleep experiment (1 Kasım 2026). Start as root with
#   doas systemd-run --unit=adsp-deney sh /var/lib/uyku-test/adsp-deney.sh
# then pull the USB-C cable and don't ssh in (sshd blocks suspend). Steps, ~12 min:
#   1) awake, screen off, audio stack as booted: does the ADSP ever power-collapse?
#   2) audio stack + LPASS LPI pinctrl unloaded (all LPASS votes gone): same question
#   3) 120 s s2idle, Bluetooth rfkill-blocked: aosd / cxsd / ddr
#   4) 120 s s2idle, Bluetooth on
# Ends with a reboot to bring audio back. Results: /var/lib/uyku-test/adsp-<time>/sonuc.txt
D=/var/lib/uyku-test/adsp-$(date +%H%M%S); mkdir -p $D; R=$D/sonuc.txt
B=/sys/class/power_supply/qcom-battmgr-bat
Q=/sys/kernel/debug/qcom_stats
modprobe qcom_stats 2>/dev/null
say() { echo "$(date +%T) $*" >> $R; }
sayac() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" a}' $Q/$1; }
anlik() {
	s=""; for f in adsp slpi aosd cxsd ddr; do s="$s $f=$(sayac $f)"; done
	say "$1 yuk=$(cat $B/charge_counter) akim=$(cat $B/current_now) usb=$(cat /sys/class/power_supply/qcom-battmgr-usb/online)$s"
}
oy() { awk '/LPASS_HW_MACRO|LPASS_HW_DCODEC/{printf "%s=%s ", $1, $2}' /sys/kernel/debug/clk/clk_summary; }
uyu() {
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$1 > /sys/class/rtc/rtc0/wakealarm
	systemctl suspend -i 2>>$R || systemctl suspend 2>>$R
	sleep 3
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 2
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	say "uyandiran irq=$w $(grep -E "^ *$w:" /proc/interrupts | awk '{$1=""; for(i=2;i<=9;i++)$i=""; print}')"
}
say "bekliyor: kablo"
n=0
# Nothing on USB-C at all: with a monitor the phone is the source (online=0) but DP and
# VBUS out keep the SoC busy, so wait for the partner to go away as well.
while [ "$(cat /sys/class/power_supply/qcom-battmgr-usb/online)" = 1 ] || [ -e /sys/class/typec/port0-partner ]; do
	sleep 2; n=$((n+1)); [ $n -gt 5400 ] && { say "kablo 3 saat çıkmadı, vazgeçtim"; exit 0; }
done
sleep 20  # ssh sessions die, the gauge settles
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
anlik "1-once (uyanik, ses yigini acik) oy: $(oy)"; sleep 120; anlik "1-sonra"
modprobe -r snd_soc_sm8250 snd_soc_wcd938x snd_soc_wcd938x_sdw snd_soc_lpass_rx_macro \
	snd_soc_lpass_tx_macro pinctrl_sc7280_lpass_lpi snd_soc_lpass_va_macro 2>>$R
anlik "2-once (uyanik, ses yigini kapali) oy: $(oy)"; sleep 120; anlik "2-sonra"
rfkill block bluetooth; sleep 3
anlik "3-once (uyku, BT kapali)"; uyu 120; anlik "3-sonra"
rfkill unblock bluetooth; sleep 3
anlik "4-once (uyku, BT acik)"; uyu 120; anlik "4-sonra"
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $D/genpd
cat /sys/kernel/debug/interconnect/interconnect_summary > $D/icc 2>/dev/null
journalctl -b --since "-15min" --no-pager | grep -E "nicole-uyku|PM: suspend|inhibit|Suspend|wakeup" >> $D/gunluk
say "bitti, yeniden başlatılıyor"
echo $D > /var/lib/uyku-test/son-adsp
sync; systemctl reboot
