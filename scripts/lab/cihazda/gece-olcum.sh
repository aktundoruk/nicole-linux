#!/bin/sh
# Overnight unplugged drain (1 Kasım 2026, kernel r14; replaces the 31 Ekim gece-olc.sh, which
# gave up after 6 h of waiting for the cable). Question: is s2idle really costlier than staying
# awake with the screen off (the short run said 936 vs 413 mA), or was that the fuel gauge?
# Start as root with
#   doas systemd-run --unit=gece-olcum sh /var/lib/uyku-test/gece-olcum.sh
# It waits for the cable to be plugged in (if it is not already), then up to 14 h for USB-C
# to be empty, so starting it unplugged does not begin the run before bedtime. Then it
# settles 20 min awake (the gauge corrects itself right after a full charge) and alternates 45 min s2idle / 30 min awake, screen off, up to
# 6 cycles (~7.5 h). Plugging the cable back in ends it. No reboot (slot A retries), no sound,
# the screen stays off at the end (night). Log: /var/lib/uyku-test/gece-<date>.csv
B=/sys/class/power_supply/qcom-battmgr-bat; U=/sys/class/power_supply/qcom-battmgr-usb
Q=/sys/kernel/debug/qcom_stats
L=/var/lib/uyku-test/gece-$(date +%m%d-%H%M).csv
modprobe qcom_stats 2>/dev/null
st() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" int(a/19200000)}' $Q/$1; }   # count/seconds
satir() {
	echo "$(date +%T),$1,$(cat $B/capacity),$(cat $B/charge_counter),$(cat $B/voltage_now),$(cat $B/current_now),$(cat $B/temp),$(st adsp),$(st aosd),$(st cxsd),$(st ddr)" >> $L
}
takili() { [ "$(cat $U/voltage_now)" -gt 1000000 ] || [ -e /sys/class/typec/port0-partner ]; }
echo "zaman,olay,yuzde,yuk_uAh,gerilim_uV,akim_uA,sicaklik_dC,adsp_n/sn,aosd_n/sn,cxsd_n/sn,ddr_n/sn" > $L
n=0
until takili; do sleep 10; n=$((n+1)); [ $n -gt 5040 ] && { satir "kablo-hic-takilmadi"; exit 0; }; done
satir "kablo-goruldu"
bos=0; n=0
while [ $bos -lt 6 ]; do
	if takili; then bos=0; else bos=$((bos+1)); fi
	sleep 10; n=$((n+1)); [ $n -gt 5040 ] && { satir "vazgecti"; exit 0; }   # 14 h
done
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
satir basla
sleep 1200; satir "oturma-sonra"
i=0
while [ $i -lt 6 ]; do
	takili && { satir "kablo-takildi"; exit 0; }
	satir "uyku-once"
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +2700 > /sys/class/rtc/rtc0/wakealarm
	systemctl suspend -i || systemctl suspend; sleep 5
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 10; satir "uyku-sonra uyandiran=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	takili && { satir "kablo-takildi"; exit 0; }
	sleep 1790; satir "uyanik-sonra"
	i=$((i+1))
done
satir bitti
