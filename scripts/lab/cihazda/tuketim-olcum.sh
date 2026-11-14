#!/bin/sh
# Unplugged battery drain with the stack as booted (1 Kasım 2026, after kernel r14).
# Start as root with
#   doas systemd-run --unit=tuketim-olcum sh /var/lib/uyku-test/tuketim-olcum.sh
# then pull the USB-C cable and stay out of ssh (an open session blocks suspend).
# Nothing is unloaded and the phone is not rebooted (every boot of slot A uses up one
# ABL retry). clk_summary is not read either: reading it resumes clock providers.
# Steps, ~27 min:
#   1) 180 s awake, screen off
#   2) 600 s s2idle, Bluetooth on (the everyday state)
#   3) 600 s s2idle, Bluetooth rfkill-blocked
# Drain per step from charge_counter (uAh) -> average mA. Screen comes back on at the end.
# Results: /var/lib/uyku-test/tuketim-<time>/sonuc.txt
D=/var/lib/uyku-test/tuketim-$(date +%H%M%S); mkdir -p $D; R=$D/sonuc.txt
B=/sys/class/power_supply/qcom-battmgr-bat
Q=/sys/kernel/debug/qcom_stats
modprobe qcom_stats 2>/dev/null
say() { echo "$(date +%T) $*" >> $R; }
sayac() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" a}' $Q/$1; }
anlik() {
	s=""; for f in adsp slpi cdsp aosd cxsd ddr; do [ -e $Q/$f ] && s="$s $f=$(sayac $f)"; done
	say "$1 yuk=$(cat $B/charge_counter) akim=$(cat $B/current_now) usb=$(cat /sys/class/power_supply/qcom-battmgr-usb/online)$s"
}
# average mA between two charge_counter readings taken $3 seconds apart
ortalama() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN{printf "%.0f mA", (a-b)*3600/t/1000}'; }
adim() { # name, seconds, command
	y0=$(cat $B/charge_counter); t0=$(date +%s)
	anlik "$1-once"; eval "$3"; anlik "$1-sonra"
	y1=$(cat $B/charge_counter); t1=$(date +%s)
	say "$1 ortalama: $(ortalama $y0 $y1 $((t1-t0))) ($((t1-t0)) sn, $((y0-y1)) uAh)"
}
uyu() {
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$1 > /sys/class/rtc/rtc0/wakealarm
	systemctl suspend -i 2>>$R || systemctl suspend 2>>$R
	sleep 3
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 2
	w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	say "uyandiran irq=$w $(grep -E "^ *$w:" /proc/interrupts | awk '{$1=""; for(i=2;i<=9;i++)$i=""; print}')"
}
say "çekirdek: $(uname -r) $(uname -v)"
say "bekliyor: kablo"
n=0
while [ "$(cat /sys/class/power_supply/qcom-battmgr-usb/online)" = 1 ] || [ -e /sys/class/typec/port0-partner ]; do
	sleep 2; n=$((n+1)); [ $n -gt 5400 ] && { say "kablo 3 saat çıkmadı, vazgeçtim"; exit 0; }
done
sleep 20  # ssh sessions die, the gauge settles
ekran() { case $1 in kapat) p=off ;; *) p=on ;; esac; su user -c "XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=\$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output '*' power $p" 2>/dev/null; }
ekran kapat
adim 1-uyanik 180 "sleep 180"
adim 2-uyku-bt-acik 600 "uyu 600"
rfkill block bluetooth; sleep 3
adim 3-uyku-bt-kapali 600 "uyu 600"
rfkill unblock bluetooth
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $D/genpd
journalctl -b --since "-30min" --no-pager | grep -E "nicole-uyku|PM: suspend|inhibit|Suspend|wakeup" >> $D/gunluk
ekran ac
say "bitti"
echo $D > /var/lib/uyku-test/son-tuketim
