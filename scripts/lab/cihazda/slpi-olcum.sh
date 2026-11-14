#!/bin/sh
# Does the accelerometer stream cost battery in s2idle? (2 Kasım 2026, kernel r14)
# With an auto-rotate daemon + monitor-sensor + iio-sensor-proxy running, the SLPI sends the AP
# ~32 glink messages a second and never sleeps; with them stopped it sleeps 100%. This compares
# s2idle with and without the stream, in windows long enough for the fuel gauge, and shows
# whether a sleeping SLPI lets aosd/cxsd/ddr move at all.
# Start as root with
#   doas systemd-run --unit=slpi-olcum sh /var/lib/uyku-test/slpi-olcum.sh
# It waits for the cable to be plugged and then pulled, settles 10 min awake, sleeps 5 min with
# sensors off (quick look at the deep counters), then 45 min s2idle: off, on, off, on (~3 h 15).
# Plugging the cable back in ends it. No reboot; sensors always come back (trap).
# Log: /var/lib/uyku-test/slpi-<date>.csv
B=/sys/class/power_supply/qcom-battmgr-bat; U=/sys/class/power_supply/qcom-battmgr-usb
Q=/sys/kernel/debug/qcom_stats
L=/var/lib/uyku-test/slpi-$(date +%m%d-%H%M).csv
modprobe qcom_stats 2>/dev/null
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
geri() { systemctl start iio-sensor-proxy; [ -n "$OTO" ] && kill -CONT $OTO; satir son; }
uyu() {
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$1 > /sys/class/rtc/rtc0/wakealarm
	satir "uyku-once $2"
	systemctl suspend -i || systemctl suspend; sleep 5
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 5; satir "uyku-sonra $2 uyandiran=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	takili && { satir "kablo-takildi"; exit 0; }
}
echo "zaman,olay,yuzde,yuk_uAh,gerilim_uV,akim_uA,sicaklik_dC,slpi_n/sn,adsp_n/sn,aosd_n/sn,cxsd_n/sn,ddr_n/sn" > $L
n=0
until takili; do sleep 10; n=$((n+1)); [ $n -gt 5040 ] && { satir "kablo-hic-takilmadi"; exit 0; }; done
satir "kablo-goruldu"
bos=0; n=0
while [ $bos -lt 6 ]; do
	if takili; then bos=0; else bos=$((bos+1)); fi
	sleep 10; n=$((n+1)); [ $n -gt 5040 ] && { satir "vazgecti"; exit 0; }   # 14 h
done
trap geri EXIT
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
satir basla
sleep 600; satir "oturma-sonra"
sensor_kapat; uyu 300 kisa-kapali
uyu 2700 kapali
sensor_ac; uyu 2700 acik
sensor_kapat; uyu 2700 kapali
sensor_ac; uyu 2700 acik
satir bitti
