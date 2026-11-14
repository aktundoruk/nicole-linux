#!/bin/sh
# Unplugged sleep drain with root on UFS (5 Kasım 2026, kernel r18, device r19).
# The last measurement (3 Kasım, pcie-d3-olcum.sh, root on SD, UFS untouched) settled at ~195 mA.
# Back then the internal UFS had no Linux driver: it stayed as the bootloader left it, its rails
# (L7 VCC, L9 VCCQ) never switched off. Now ufshcd drives it (runtime suspended, spm_lvl 3:
# device SLEEP, link HIBERN8). Question: does that move the drain, and does aosd/cxsd count now?
# Nothing is switched off or loaded: the phone as it is used, screen off.
# Start as root, unplugged, with
#   doas systemd-run --unit=ufs-gece --collect sh /var/lib/uyku-test/ufs-gece-olcum.sh
# 5 min sleep, then 45 min windows (as on 3 Kasım), at most 8 (~6 h 10). Plugging the cable ends
# it. No reboot, no sound, the screen stays off. Log: /var/lib/uyku-test/ufs-gece-<date>.csv
B=/sys/class/power_supply/qcom-battmgr-bat; U=/sys/class/power_supply/qcom-battmgr-usb
Q=/sys/kernel/debug/qcom_stats
H=/sys/bus/platform/drivers/ufshcd-qcom/1d84000.ufshc
L=/var/lib/uyku-test/ufs-gece-$(date +%m%d-%H%M).csv
modprobe qcom_stats 2>/dev/null
st() { awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" int(a/19200000)}' $Q/$1; }
ufs() { echo "$(cat $H/power_info/dev_pm 2>/dev/null)/$(cat $H/power_info/link_state 2>/dev/null)/$(cat $H/power/runtime_status)"; }
# seconds really spent asleep: boottime counts suspend, monotonic does not
uyuyan() { python3 -c 'import time; print(int(time.clock_gettime(time.CLOCK_BOOTTIME) - time.monotonic()))'; }
satir() {
	echo "$(date +%T),$1,$(cat $B/capacity),$(cat $B/charge_counter),$(cat $B/voltage_now),$(cat $B/current_now),$(cat $B/temp),$(st slpi),$(st adsp),$(st cdsp),$(st aosd),$(st cxsd),$(st ddr),$(uyuyan),$(ufs)" >> $L
}
takili() { [ "$(cat $U/voltage_now)" -gt 1000000 ] || [ -e /sys/class/typec/port0-partner ]; }
uyu() {
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$1 > /sys/class/rtc/rtc0/wakealarm
	satir "uyku-once $2"
	systemctl suspend -i || systemctl suspend; sleep 5
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 5; satir "uyku-sonra $2 uyandiran=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	takili && { satir "kablo-takildi"; exit 0; }
}
echo "zaman,olay,yuzde,yuk_uAh,gerilim_uV,akim_uA,sicaklik_dC,slpi_n/sn,adsp_n/sn,cdsp_n/sn,aosd_n/sn,cxsd_n/sn,ddr_n/sn,uyunan_sn,ufs_dev/link/rpm" > $L
echo "# $(uname -r) $(uname -v); kok $(findmnt -n -o SOURCE /); mem_sleep $(cat /sys/power/mem_sleep); spm_lvl $(cat $H/spm_lvl) rpm_lvl $(cat $H/rpm_lvl)" >> $L
takili && { satir "kablo-takili-basta"; exit 0; }
su user -c 'XDG_RUNTIME_DIR=/run/user/10000 SWAYSOCK=$(ls /run/user/10000/sway-ipc.*.sock) swaymsg output "*" power off' 2>/dev/null
satir basla
uyu 300 kisa
i=1
while [ $i -le 8 ]; do
	uyu 2700 pencere$i
	i=$((i+1))
done
satir bitti
