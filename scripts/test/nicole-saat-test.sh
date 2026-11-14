#!/bin/sh
# nicole-saat decisions with fake files (NICOLE_SAAT_DENEME: nothing is set or written).
# Runs on the phone or any busybox/coreutils shell: sh nicole-saat-test.sh /path/to/nicole-saat
N=${1:-/usr/libexec/nicole-saat}
D=$(mktemp -d); trap 'rm -rf $D' EXIT
export NICOLE_SAAT_RTC=$D/rtc NICOLE_SAAT_OFS=$D/ofs NICOLE_SAAT_TSC=$D/tsc NICOLE_SAAT_SON=$D/son \
	NICOLE_SAAT_SENK=$D/senk NICOLE_SAAT_DENEME=1
hata=0
T0=1793900000   # "now" of the fake world
dosyalar() {  # rtc offset tsc_mtime son_r son_s
	rm -f $D/*; echo $1 > $D/rtc
	[ -n "$2" ] && echo $2 > $D/ofs && touch -d @$3 $D/ofs
	[ -n "$3" ] && touch -d @$3 $D/tsc
	[ -n "$4" ] && echo "$4 $5" > $D/son
	:
}
bekle() {  # name expected-pattern
	c=$(sh $N kur)
	case "$c" in $2) echo "GEÇTİ $1: $c" ;; *) echo "KALDI $1: $c (beklenen $2)"; hata=1 ;; esac
}
# 1 normal: RTC 50000, offset T0-50000+100 → T0+100, saved stamps T0
dosyalar 50000 $((T0 - 50000 + 100)) $T0 49000 $((T0 - 1000)); bekle normal "kur: saat $((T0 + 100))"
# 2 RTC reset: RTC 30 (was 49000), offset stale → saved time T0
dosyalar 30 $((T0 - 50000)) $T0 49000 $((T0 - 1000)); bekle sifirlanmis "kur: saat $T0, RTC sıfırlanmış*"
# 3 stale offset, no own record (first boot with this package after an RTC reset)
dosyalar 30 $((T0 - 50000)) $T0; bekle eski-fark "kur: saat $T0, RTC + fark*geride"
# 4 own record newer than timesyncd's stamp
dosyalar 30 $((T0 - 50000)) $T0 49000 $((T0 + 500)); bekle kendi-kayit "kur: saat $((T0 + 500)), RTC sıfırlanmış*"
# 5 no offset file, nothing saved: leave the clock where it is (date now ≥ 0)
dosyalar 30; c=$(sh $N kur); case "$c" in "kur: saat "[0-9]*) echo "GEÇTİ dosyasiz: $c" ;; *) echo "KALDI dosyasiz: $c"; hata=1 ;; esac
# 6 garbage in files: the clock stays, unless it is behind the saved time (here in the future)
G=$(($(date +%s) + 100000))
dosyalar 50000 abc $G xx yy; bekle bozuk "kur: saat $G, RTC + fark*geride"
# 7 already synchronised over the network: no change
dosyalar 30 $((T0 - 50000)) $T0 49000 $T0; touch $D/senk; bekle senkron "saat ağdan eşitlenmiş*"
# 8 rtc0 missing (early run before the module)
dosyalar 1; rm $D/rtc; bekle rtc-yok "rtc0 yok*"
# 9 kaydet
dosyalar 50000; c=$(sh $N kaydet); case "$c" in "kaydet: fark "*", rtc 50000, saat "*) echo "GEÇTİ kaydet: $c" ;; *) echo "KALDI kaydet: $c"; hata=1 ;; esac
exit $hata
