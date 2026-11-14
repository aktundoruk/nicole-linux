#!/bin/sh
# s2idle drain with the PCIe host really powered off (3 Kasım 2026, kernel r14 + uyku_iz d3=1).
# Until now every PCIe clock stayed on in suspend (empty root port kept in D0, bridge_d3=0), which
# held XO and GPLL0. uyku_iz d3=1 lets the empty root port into D3hot and the host powers off: the
# first 60 s test moved the ddr counter for the first time (1536 entries, 51 s), with the SLPI still
# streaming. Question: what does that buy in mA, and does a sleeping SLPI now move aosd/cxsd?
# Start as root, unplugged, with
#   doas systemd-run --unit=d3-olcum sh /var/lib/uyku-test/pcie-d3-olcum.sh
# 5 min s2idle sensors off, then 45 min s2idle: off, on, off, on (~3 h 5). Plugging the cable ends it.
# Log: /var/lib/uyku-test/d3-<date>.csv
# With a uyku_iz option as argument ("oto": switching rails in AUTO, "wcn": WLAN enable low in sleep,
# BT off first) the question is that option: sensors off throughout, 45 min on, off, on, off (~3 h),
# since two windows under the same conditions already differ by 30 mA (163 and 194 mA in the d3 run).
B=/sys/class/power_supply/qcom-battmgr-bat; U=/sys/class/power_supply/qcom-battmgr-usb
Q=/sys/kernel/debug/qcom_stats
L=/var/lib/uyku-test/d3-$(date +%m%d-%H%M).csv
modprobe qcom_stats 2>/dev/null
yukle() { # rmmod undoes the option
	rmmod uyku_iz 2>/dev/null
	insmod /var/lib/uyku-test/uyku_iz.ko d3=1 $1 kok=0x$(awk '$3=="clk_root_list"{print $1}' /proc/kallsyms) || exit 1
}
yukle ${1:+$1=1}
OTO=$(for p in $(pidof python3); do grep -qa otodondur /proc/$p/cmdline && echo $p; done)
st() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" int(a/19200000)}' $Q/$1; }
satir() {
	echo "$(date +%T),$1,$(cat $B/capacity),$(cat $B/charge_counter),$(cat $B/voltage_now),$(cat $B/current_now),$(cat $B/temp),$(st slpi),$(st adsp),$(st aosd),$(st cxsd),$(st ddr)" >> $L
}
takili() { [ "$(cat $U/voltage_now)" -gt 1000000 ] || [ -e /sys/class/typec/port0-partner ]; }
akis() { # SLPI wake-ups per 5 s: ~25 means the accelerometer stream is flowing
	a=$(awk '/smp2p-slpi/ && /q6v5 ready/{s=0;for(i=2;i<=9;i++)s+=$i;print s}' /proc/interrupts); sleep 5
	b=$(awk '/smp2p-slpi/ && /q6v5 ready/{s=0;for(i=2;i<=9;i++)s+=$i;print s}' /proc/interrupts); echo $((b-a))
}
sensor_kapat() {
	[ -n "$OTO" ] && kill -STOP $OTO
	kill $(pidof monitor-sensor) 2>/dev/null
	systemctl stop iio-sensor-proxy; sleep 10
	satir "sensor-kapali akis=$(akis)"
}
sensor_ac() {
	systemctl start iio-sensor-proxy
	[ -n "$OTO" ] && kill -CONT $OTO
	sleep 15   # the auto-rotate daemon respawns monitor-sensor after 5 s
	satir "sensor-acik akis=$(akis)"
}
geri() { systemctl start iio-sensor-proxy; [ -n "$OTO" ] && kill -CONT $OTO; rmmod uyku_iz; satir son; }
uyu() {
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$1 > /sys/class/rtc/rtc0/wakealarm
	satir "uyku-once $2"
	systemctl suspend -i || systemctl suspend; sleep 5
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 5; satir "uyku-sonra $2 uyandiran=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	takili && { satir "kablo-takildi"; exit 0; }
}
echo "zaman,olay,yuzde,yuk_uAh,gerilim_uV,akim_uA,sicaklik_dC,slpi_n/sn,adsp_n/sn,aosd_n/sn,cxsd_n/sn,ddr_n/sn" > $L
trap geri EXIT
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
satir basla
sensor_kapat
if [ -n "$1" ]; then
	uyu 2700 $1; yukle; uyu 2700 taban
	yukle $1=1; uyu 2700 $1; yukle; uyu 2700 taban
else
	uyu 300 kisa-kapali
	uyu 2700 kapali
	sensor_ac; uyu 2700 acik
	sensor_kapat; uyu 2700 kapali
	sensor_ac; uyu 2700 acik
fi
satir bitti
