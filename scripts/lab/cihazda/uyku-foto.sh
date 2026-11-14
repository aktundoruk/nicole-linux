#!/bin/sh
# One short s2idle with the uyku_iz snapshot: exact counters and what is on inside suspend, no
# battery gauge involved. Optional argument: commands to run first, to see what they free.
#   doas systemd-run --unit=foto sh /var/lib/uyku-test/uyku-foto.sh "systemctl stop bluetooth"
# Module parameters can be added through UYKU_IZ=, e.g. systemd-run -E UYKU_IZ=wcn=1 ...
# Output: /var/lib/uyku-test/foto/
Q=/sys/kernel/debug/qcom_stats; O=/var/lib/uyku-test/foto; mkdir -p $O; rm -f $O/*
s() { awk -v a="$1" '$3==a{print "0x"$1}' /proc/kallsyms; }
st() { for k in slpi adsp aosd cxsd ddr; do printf '%s=%s ' $k "$(awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" int(a/19200000)}' $Q/$k)"; done; echo; }
modprobe qcom_stats 2>/dev/null
rmmod uyku_iz 2>/dev/null
insmod /var/lib/uyku-test/uyku_iz.ko d3=1 kok=$(s clk_root_list) gpd=$(s gpd_list) rs=$(s regulator_class) icc=$(s icc_providers) $UYKU_IZ || exit 1
OTO=$(for p in $(pidof python3); do grep -qa otodondur /proc/$p/cmdline && echo $p; done)
geri() { systemctl start iio-sensor-proxy; [ -n "$OTO" ] && kill -CONT $OTO; rmmod uyku_iz; echo bitti >> $O/stats; }
trap geri EXIT
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
[ -n "$OTO" ] && kill -STOP $OTO
kill $(pidof monitor-sensor) 2>/dev/null
systemctl stop iio-sensor-proxy
[ -n "$1" ] && sh -c "$1" >> $O/stats 2>&1
sleep 10
st >> $O/stats
echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +60 > /sys/class/rtc/rtc0/wakealarm
systemctl suspend -i || systemctl suspend; sleep 5
while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
sleep 3
st >> $O/stats
for f in clk genpd icc regulator; do cp /sys/kernel/debug/uyku_iz/$f $O/$f; done
