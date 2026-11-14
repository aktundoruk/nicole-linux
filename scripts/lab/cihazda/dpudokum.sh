#!/bin/sh
# DPU resource assignment snapshot: CRTC mixers/ctl, encoder intf/mode, atomic state summary
D=/sys/kernel/debug/dri/1
for c in 0 1 2; do echo "== crtc-$c"; grep -E "mixer|crtc:|intf_mode" $D/crtc-$c/status; done
for e in 0 1 2; do echo "== enc-$e: $(cat $D/encoder-$e/status)"; done
awk '/^crtc\[/{c=$0} /enable=|encoder_mask|mode: /{print c": "$0}' $D/state
grep -c "frame done timeout" /dev/null; dmesg | grep -c "frame done timeout"
