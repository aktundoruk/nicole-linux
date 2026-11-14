#!/usr/bin/env bash
# USB timeline: prints the time (s, from start) whenever the phone's USB device set changes
t0=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
son="__"
while :; do
	n=$(ioreg -p IOUSB -w0 | grep -v -e SanDisk -e XHCI -e Root | sed -E 's/.*-o ([^<]*)<.*id (0x[0-9a-f]+).*/\1 \2/' | tr '\n' ';')
	if [ "$n" != "$son" ]; then
		t=$(perl -MTime::HiRes=time -e "printf '%.2f', time - $t0")
		echo "$t ${n:-YOK}"; son=$n
	fi
	sleep 0.1
done
