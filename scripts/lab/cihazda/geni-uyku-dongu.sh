#!/bin/sh
# BT UART (qcom_geni_serial_uart1) across s2idle cycles: interrupts per cycle, "nobody cared".
# Root, detached: systemd-run --unit=geni-dongu sh geni-uyku-dongu.sh N
# Each cycle: 12 s RTC alarm, suspend (inhibitors ignored), wait for the wake, 4 s awake.
N=${1:-20}
L=/var/lib/uyku-test/geni-$(date +%m%d-%H%M).txt
irq() { awk '/qcom_geni_serial_uart1/ { s = 0; for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i; else break; print s }' /proc/interrupts; }
echo "basla $(date +%T) bt=$(cat /sys/class/bluetooth/hci0/rfkill*/state 2>/dev/null) irq=$(irq)" > $L
dmesg | grep -c "nobody cared" > /tmp/geni-onceki
for i in $(seq 1 $N); do
	a=$(irq); s0=$(cat /sys/power/suspend_stats/success)
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +12 > /sys/class/rtc/rtc0/wakealarm
	systemctl suspend -i
	j=0; while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ] && [ $j -lt 60 ]; do sleep 1; j=$((j+1)); done
	sleep 4
	b=$(irq)
	echo "tur $i $(date +%T) kesme $((b - a)) basarili=$(cat /sys/power/suspend_stats/success) hata=$(cat /sys/power/suspend_stats/fail)" >> $L
done
echo "bitti $(date +%T) nobody_cared_yeni=$(( $(dmesg | grep -c 'nobody cared') - $(cat /tmp/geni-onceki) ))" >> $L
dmesg | grep -i -E "nobody cared|geni|serial" | tail -5 >> $L
