#!/bin/sh
# s2idle cycles with root on UFS: data written before sleep must read back the same after it,
# from the disk rather than the cache, and the driver must not log errors. Runs detached (systemd-run).
N=${1:-6}; SURE=${2:-25}
O=/var/lib/uyku-test/ufs-dongu-$(date +%H%M); mkdir -p $O; echo $O > /var/lib/uyku-test/son-dongu
Q=/sys/kernel/debug/qcom_stats
# the UART carrying Bluetooth: a normal cycle takes about a dozen interrupts, a storm far more
bt_irq() { awk '/qcom_geni_serial_uart1/{s=0; for(i=2;i<=9;i++) s+=$i; print s}' /proc/interrupts; }
st() { for f in adsp slpi aosd cxsd ddr; do printf '%s=%s ' $f "$(awk '/Count/{c=$2} /Accum/{a=$3} END{print c "/" int(a/19200000)}' $Q/$f)"; done; echo; }
st > $O/stats
i=1; hata=0
while [ $i -le $N ]; do
	dd if=/dev/urandom of=$O/veri bs=1M count=64 2>/dev/null
	i0=$(bt_irq)
	a=$(sha256sum < $O/veri); sync
	echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$SURE > /sys/class/rtc/rtc0/wakealarm
	systemctl suspend -i || systemctl suspend; sleep 3
	while [ "$(systemctl is-active systemd-suspend.service)" = activating ]; do sleep 1; done
	sleep 6
	sync; echo 3 > /proc/sys/vm/drop_caches
	b=$(sha256sum < $O/veri)
	[ "$a" = "$b" ] && s=ok || { s=FARKLI; hata=$((hata+1)); }
	echo "$i $(date +%T) $s bt_irq=$(($(bt_irq)-i0)) $(st)" >> $O/dongu
	i=$((i+1))
done
rm -f $O/veri; sync
{ head -8 /sys/kernel/debug/suspend_stats; dmesg | grep -E 'ufshc|refused|I/O error|EXT4-fs (error|warning)|blk_update|Abort|timeout|task abort' | tail -20; ip -br a; } > $O/sonuc 2>&1
echo "hata=$hata bitti" >> $O/sonuc
