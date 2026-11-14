#!/bin/sh
# Offline test for pmaports/device-razer-nicole/nicole-fan against a fake sysfs tree.
# Usage: nicole-fan-test.sh [shell]   (default: busybox sh if present, else sh)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FAN="$HERE/../../pmaports/device-razer-nicole/nicole-fan"
SH="${1:-$(command -v busybox >/dev/null && echo "busybox sh" || echo sh)}"
T="$(mktemp -d)"
trap 'kill $PID 2>/dev/null; rm -rf "$T"' EXIT
fail=0

S="$T/sys"
mkdir -p "$S/class/hwmon/hwmon0" "$S/bus/iio/devices/iio:device0" "$S/class/power_supply/qcom-battmgr-bat"
echo max31760 > "$S/class/hwmon/hwmon0/name"
echo 0 > "$S/class/hwmon/hwmon0/pwm1"; echo 2 > "$S/class/hwmon/hwmon0/pwm1_enable"
echo 1500 > "$S/class/hwmon/hwmon0/pwm1_freq"; echo 4000 > "$S/class/hwmon/hwmon0/fan1_input"
n=0
for z in cpu6-bottom-thermal cpu7-bottom-thermal gpu-top-thermal gpu-bottom-thermal video-thermal cpu0-top-thermal; do
	mkdir -p "$S/class/thermal/thermal_zone$n"; echo "$z" > "$S/class/thermal/thermal_zone$n/type"
	echo 45000 > "$S/class/thermal/thermal_zone$n/temp"; n=$((n + 1))
done
Q="$S/bus/iio/devices/iio:device0/in_temp_pm8350_quiet_therm_input"; echo 30000 > "$Q"
B="$S/class/power_supply/qcom-battmgr-bat"; echo 300 > "$B/temp"; echo Discharging > "$B/status"
zt() { echo "$2" > "$S/class/thermal/thermal_zone$1/temp"; }

NICOLE_FAN_SYS="$S" NICOLE_FAN_STATE="$T/state" NICOLE_FAN_PROFILE="$T/profil" NICOLE_FAN_PERIOD=0.2 $SH "$FAN" > "$T/log" 2>&1 &
PID=$!

# expect LEVEL DUTY: waits up to 3 s for the state file to show it
expect() {
	i=0
	while [ $i -lt 30 ]; do
		set -- "$1" "$2" "$3"
		{ read -r l d _ < "$T/state"; } 2>/dev/null && [ "$l" = "$1" ] && [ "$d" = "$2" ] && { echo "ok   $3"; return; }
		sleep 0.1; i=$((i + 1))
	done
	echo "FAIL $3: want $1/$2, state: $(cat "$T/state" 2>/dev/null)"; fail=1
}

expect 0 0 "idle, cool -> fan stopped"
[ "$(cat "$S/class/hwmon/hwmon0/pwm1_enable")" = 1 ] && echo "ok   manual mode" || { echo "FAIL manual mode"; fail=1; }
[ "$(cat "$S/class/hwmon/hwmon0/pwm1_freq")" = 25000 ] && echo "ok   25 kHz" || { echo "FAIL pwm freq"; fail=1; }
echo 32000 > "$Q";  expect 2 113 "skin 32 C -> level 2"
echo 31000 > "$Q";  expect 2 113 "skin 31 C stays (hysteresis 2)"
echo 29900 > "$Q";  expect 0 0   "skin 29.9 C -> off"
zt 5 61000;         expect 2 113 "hottest zone 61 C -> level 2"
zt 5 45000;         expect 0 0   "zone back to 45 C"
zt 0 82000;         expect 5 204 "cpu6-bottom 82 C -> level 5"
zt 0 96000;         expect 7 255 "cpu6-bottom 96 C -> level 7"
zt 0 45000; zt 5 91000; expect 7 255 "any zone 91 C -> level 7"
zt 5 45000;
zt 0 45000;         expect 0 0   "cpu cooled down"
echo 365 > "$B/temp"; expect 0 0 "battery 36.5 C discharging -> off"
echo Charging > "$B/status"; expect 2 113 "battery 36.5 C charging -> level 2"
echo 405 > "$B/temp"; expect 5 204 "battery 40.5 C -> level 5"
echo 300 > "$B/temp"; echo Discharging > "$B/status"; expect 0 0 "battery cool"
echo garbage > "$S/class/thermal/thermal_zone2/temp"; expect 7 255 "unreadable gpu zone -> full"
echo 45000 > "$S/class/thermal/thermal_zone2/temp"; expect 0 0 "zone readable again"
echo sessiz > "$T/profil"
echo 39000 > "$Q";  expect 0 0   "sessiz: skin 39 C -> off"
echo 40000 > "$Q";  expect 2 113 "sessiz: skin 40 C -> level 2"
echo 42000 > "$Q";  expect 7 255 "sessiz: skin 42 C -> full (contract ceiling)"
echo 30000 > "$Q";  expect 0 0   "sessiz: skin 30 C -> off"
zt 0 82000;         expect 5 204 "sessiz: cpu6-bottom 82 C still -> level 5 (floor)"
zt 0 45000;         expect 0 0   "sessiz: cpu cooled"
echo 405 > "$B/temp"; expect 5 204 "sessiz: battery 40.5 C still -> level 5 (floor)"
echo 300 > "$B/temp"; expect 0 0 "sessiz: battery cool"
echo performans > "$T/profil"
echo 30000 > "$Q";  expect 2 113 "performans: skin 30 C -> level 2"
echo bozuk > "$T/profil"
echo 33000 > "$Q";  expect 2 113 "unknown profile -> dengeli (skin 33 C -> level 2)"
rm "$T/profil"
echo 29000 > "$Q";  expect 0 0   "no profile file -> dengeli, skin 29 C -> off"
kill "$PID"; wait "$PID" 2>/dev/null
[ "$(cat "$S/class/hwmon/hwmon0/pwm1")" = 255 ] && echo "ok   stop -> full speed" || { echo "FAIL stop leaves pwm1=$(cat "$S/class/hwmon/hwmon0/pwm1")"; fail=1; }

[ $fail = 0 ] && echo "GEÇTİ" || { echo "KALDI"; cat "$T/log"; }
exit $fail
