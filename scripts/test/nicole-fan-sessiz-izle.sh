#!/bin/sh
# Quiet fan profile test: log skin/battery/SoC temperature, fan and power every 30 s.
O=/tmp/sessiz.txt
B=/sys/class/power_supply/qcom-battmgr-bat
Q=$(ls /sys/bus/iio/devices/iio:device*/in_temp_*quiet_therm*_input | head -1)
: > $O
for i in $(seq 50); do
	t=0; for z in /sys/class/thermal/thermal_zone*/temp; do v=$(cat $z 2>/dev/null) && [ "${v:-0}" -gt $t ] && t=$v; done
	I=$(cat $B/current_now); V=$(cat $B/voltage_now)
	echo "$(date +%T) kasa=$(cat $Q) pil=$(cat $B/temp) soc=$t st=$(cat $B/status) cap=$(cat $B/capacity) P_mW=$(( -I / 1000 * (V / 1000) / 1000 )) fan=[$(cat /run/nicole-fan)]" >> $O
	sleep 30
done
echo bitti >> $O
