#!/bin/sh
# Speed of the running root (expects root on UFS), the card and the raw partition, read only on both.
hiz() { awk '/copied/{print $(NF-1),$NF}'; }
sync; echo 3 > /proc/sys/vm/drop_caches
T=/var/tmp/hiz.bin
echo "kök yaz 1 GiB:   $(dd if=/dev/zero of=$T bs=1M count=1024 oflag=direct 2>&1 | hiz)"
echo "kök oku 1 GiB:   $(dd if=$T of=/dev/null bs=1M iflag=direct 2>&1 | hiz)"
rm -f $T; sync
echo "sda10 ham oku:   $(dd if=/dev/sda10 of=/dev/null bs=1M count=1024 skip=64 iflag=direct 2>&1 | hiz)"
echo "SD ham oku:      $(dd if=/dev/mmcblk1p2 of=/dev/null bs=1M count=1024 skip=64 iflag=direct 2>&1 | hiz)"
command -v fio >/dev/null || apk add -q fio
for k in "randread 4k 1" "randwrite 4k 1" "randread 4k 32" "randwrite 4k 32"; do
	set -- $k
	echo "fio $1 $2 qd$3: $(fio --name=t --filename=/var/tmp/fio.bin --size=512M --direct=1 --ioengine=libaio --rw=$1 --bs=$2 --iodepth=$3 --runtime=8 --time_based --minimal 2>/dev/null | awk -F';' '{print ($8>0?$8:$49) " IOPS"}')"
done
rm -f /var/tmp/fio.bin; sync
