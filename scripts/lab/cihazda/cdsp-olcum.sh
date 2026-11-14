#!/bin/sh
# Does a running but sleeping CDSP cost current in s2idle? (4 Kasım 2026, kernel r14 + uyku_iz d3=1)
# The baseline went from ~750 mW (d3 and oto runs, CDSP never booted) to ~945 mW (wcn run, CDSP
# running), while WLAN enable low changed nothing. Same boot, so no reboot between the states; a
# started CDSP cannot be stopped again (a stopped DSP blocks DDR), hence one direction only.
# Before it: firmware moved to /var/lib/uyku-test/cdsp.mbn and a reboot, so CDSP has never booted.
# Start as root on the cable with
#   doas systemd-run --unit=cdsp-olcum sh /var/lib/uyku-test/cdsp-olcum.sh
# It waits for the unplug, then 45 min s2idle sensors off: warm-up (discard), base x3, cdsp x3, then
# keeps sleeping in 45 min windows until the cable returns. At 15 % it powers off: the wcn run stayed
# awake after its last window and ran the battery flat in 5 hours.
# Log: /var/lib/uyku-test/cdsp-<date>.csv
B=/sys/class/power_supply/qcom-battmgr-bat; U=/sys/class/power_supply/qcom-battmgr-usb
Q=/sys/kernel/debug/qcom_stats; F=/lib/firmware/qcom/sm8350/razer/nicole/cdsp.mbn
L=/var/lib/uyku-test/cdsp-$(date +%m%d-%H%M).csv
modprobe qcom_stats 2>/dev/null
OTO=$(for p in $(pidof python3); do grep -qa otodondur /proc/$p/cmdline && echo $p; done)
st() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" int(a/19200000)}' $Q/$1; }
satir() {
	echo "$(date +%T),$1,$(cat $B/capacity),$(cat $B/charge_counter),$(cat $B/voltage_now),$(cat $B/current_now),$(cat $B/temp),$(st slpi),$(st adsp),$(st aosd),$(st cxsd),$(st ddr),$(st cdsp)" >> $L
}
takili() { [ "$(cat $U/voltage_now)" -gt 1000000 ] || [ -e /sys/class/typec/port0-partner ]; }
ort() { # 60 s awake mean of current_now, a second opinion that does not depend on the gauge settling
	t=0; for i in $(seq 60); do t=$((t+$(cat $B/current_now))); sleep 1; done; echo $((t/60))
}
geri() { systemctl start iio-sensor-proxy; [ -n "$OTO" ] && kill -CONT $OTO; rmmod uyku_iz; satir son; }
uyu() {
	satir "uyanik-ort=$(ort) $1"
	takili && { satir kablo-takildi; exit 0; }   # the partner can take longer than the 10 s after resume
	[ "$(cat $B/capacity)" -le 15 ] && { satir dusuk-pil; systemctl poweroff; exit 0; }
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +2700 > /sys/class/rtc/rtc0/wakealarm
	satir "uyku-once $1"
	systemctl suspend -i || systemctl suspend; sleep 5
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 5; satir "uyku-sonra $1 uyandiran=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	takili && { satir kablo-takildi; exit 0; }
}
echo "zaman,olay,yuzde,yuk_uAh,gerilim_uV,akim_uA,sicaklik_dC,slpi_n/sn,adsp_n/sn,aosd_n/sn,cxsd_n/sn,ddr_n/sn,cdsp_n/sn" > $L
while takili; do sleep 10; done
sleep 30
rmmod uyku_iz 2>/dev/null
insmod /var/lib/uyku-test/uyku_iz.ko d3=1 kok=0x$(awk '$3=="clk_root_list"{print $1}' /proc/kallsyms) || exit 1
trap geri EXIT
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
satir basla
[ -n "$OTO" ] && kill -STOP $OTO
kill $(pidof monitor-sensor) 2>/dev/null
systemctl stop iio-sensor-proxy; sleep 10
uyu isinma
uyu taban; uyu taban; uyu taban
install -m 600 /var/lib/uyku-test/cdsp.mbn $F
for r in /sys/class/remoteproc/*; do [ "$(cat $r/name)" = cdsp ] && echo start > $r/state; done
sleep 20; satir "cdsp-basladi durum=$(for r in /sys/class/remoteproc/*; do [ "$(cat $r/name)" = cdsp ] && cat $r/state; done)"
uyu cdsp; uyu cdsp; uyu cdsp
while :; do uyu son-cdsp; done
