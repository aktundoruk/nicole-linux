#!/bin/bash
# Checks the write guard's edges on a kernel booted with ufshcd_core.write_ranges = rawdump.
# Runs on the phone as root. Every command here is harmless even if the guard failed:
# outside the range they carry no data (zero length, or a length with no data phase) or
# aim past the end of the LU. The two real writes put each block's own contents back, because
# after an install the first and last block of rawdump hold the inner GPT: a first version
# wrote zeros there and the next boot could not find its root (5 Nov). Refuses while rawdump
# is in use. Never add a data-carrying write that could land outside rawdump.
set -u
R=$(cat /sys/module/ufshcd_core/parameters/write_ranges)
[ "$R" = 0:2109992:3196928 ] || { echo "beklenmeyen aralık: $R"; exit 1; }
BAS=2109992; SON=$((2109992 + 3196928))   # first block after rawdump = first block of userdata
LU=$(($(cat /sys/block/sda/size) / 8))
h32() { printf '%02x %02x %02x %02x' $(($1>>24&255)) $(($1>>16&255)) $(($1>>8&255)) $(($1&255)); }
[ -z "$(ls /sys/class/block/sda10/holders 2>/dev/null)" ] || { echo "rawdump kullanımda"; exit 1; }
blockdev --flushbufs /dev/sda
dd if=/dev/sda of=/tmp/ilk.bin bs=4096 skip=$BAS count=1 iflag=direct 2>/dev/null
dd if=/dev/sda of=/tmp/son.bin bs=4096 skip=$((SON-1)) count=1 iflag=direct 2>/dev/null
hata=0
dene() { # dene <beklenen: ret|gec> <ad> <aygıt> <sg_raw args...>
	local b=$1 ad=$2; shift 2
	local c; c=$(sg_raw "$@" 2>&1)
	local s=diger
	case "$c" in *"Data protect"*|*"Data Protect"*) s=ret ;; *"SCSI Status: Good"*) s=gec ;; esac
	[ "$s" = "$b" ] && echo "ok   $ad: $s" || { echo "HATA $ad: beklenen $b, çıkan $s"; echo "$c" | tail -4; hata=$((hata+1)); }
}
w10() { echo "2a 00 $(h32 "$1") 00 $(printf '%02x %02x' $(($2>>8)) $(($2&255))) 00"; }
# shellcheck disable=SC2046
{
dene ret "aralığın bir blok altı, boy 0"    /dev/sda $(w10 $((BAS-1)) 0)
dene ret "aralığın hemen üstü, boy 0"       /dev/sda $(w10 $SON 0)
dene ret "üst sınırı taşan, veri yok"       /dev/sda $(w10 $((SON-1)) 2)
dene ret "alt sınırı taşan, veri yok"       /dev/sda $(w10 $((BAS-1)) 2)
dene ret "aynı blok numarası başka LU (sdb), boy 0" /dev/sdb $(w10 $BAS 0)
dene ret "LU sonrası, veri ile"             -s 4096 -i /dev/zero /dev/sda 8a 00 00 00 00 00 $(h32 $((LU+1000))) 00 00 00 01 00 00
dene ret "içeride, boy 0 (koruma sıfır boyu da reddeder)"                 /dev/sda $(w10 $BAS 0)
dene gec "içeride, ilk blok kendi içeriğiyle" -s 4096 -i /tmp/ilk.bin /dev/sda $(w10 $BAS 1)
dene gec "içeride, son blok kendi içeriğiyle" -s 4096 -i /tmp/son.bin /dev/sda $(w10 $((SON-1)) 1)
}
# UNMAP outside: one descriptor, 8-byte LBA past the end of the LU, count 1. An earlier layout had
# the bytes one field off, which read as LBA 0 for 192 GiB (5 Nov): harmless only because the
# guard refused it, so check the decoded fields here before sending.
hex() { printf '\\x%s' "$@"; }
# shellcheck disable=SC2046
printf "$(hex 00 16 00 10 00 00 00 00 00 00 00 00 $(h32 $((LU+1000))) 00 00 00 01 00 00 00 00)" > /tmp/unmap.bin
c=$(od -An -tu1 -v /tmp/unmap.bin | tr -s ' \n' ' ')
# shellcheck disable=SC2086
set -- $c
[ $# = 24 ] && [ $((($9<<56|${10}<<48|${11}<<40|${12}<<32|${13}<<24|${14}<<16|${15}<<8|${16}))) = $((LU+1000)) ] \
	&& [ $((${17}<<24|${18}<<16|${19}<<8|${20})) = 1 ] || { echo "UNMAP yükü yanlış: $c"; exit 1; }
dene ret "UNMAP aralık dışı"                -s 24 -i /tmp/unmap.bin /dev/sda 42 00 00 00 00 00 00 00 18 00
rm -f /tmp/unmap.bin
blockdev --flushbufs /dev/sda
dd if=/dev/sda bs=4096 skip=$BAS count=1 iflag=direct 2>/dev/null | cmp - /tmp/ilk.bin || { echo "HATA ilk blok değişti"; hata=$((hata+1)); }
dd if=/dev/sda bs=4096 skip=$((SON-1)) count=1 iflag=direct 2>/dev/null | cmp - /tmp/son.bin || { echo "HATA son blok değişti"; hata=$((hata+1)); }
rm -f /tmp/ilk.bin /tmp/son.bin
dmesg | grep -c 'refused SCSI opcode' | sed 's/^/reddedilen satır: /'
dmesg | grep 'refused SCSI opcode' | tail -8
echo "hata=$hata"
exit $hata
