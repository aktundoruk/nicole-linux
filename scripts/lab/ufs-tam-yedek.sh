#!/usr/bin/env bash
# Full backup of the internal UFS to the Mac (M0, approved by the user on 4 Nov 2026).
# The phone runs its normal SD Linux with the UFS nodes enabled (scripts/build/ufs-acik-dtb.sh)
# and the write guard in its kernel (drivers/ufs/0001-*: ufshcd_core.write_ranges empty).
#
# Usage: ufs-tam-yedek.sh [HEDEF_DIZIN]    (default: $YEDEK_KOK/tam-<stamp>; rerun with the
#        same directory to continue: pieces already in SHA256SUMS are skipped)
#
# Streams over ssh, so TELEFON=<ip> works over Wi-Fi too (encrypted either way).
# Pieces, each zstd-compressed, hashed raw on the phone while read and again on the Mac:
#   sdb sdc sdd sdf sde   whole LUs (boot chain, calibration: the small and irreplaceable)
#   sda-on / sda-userdata-NNN / sda-son   LU 0 cut around userdata; together they are the whole LU
# Then disk.txt, gpt/ and every partition's own hash, for dogrula.py to check the cut.
#
# Refuses unless: guard on, all disks ro=1 (before and after), none mounted. Stops when
# the Mac has under 10 GB free or the phone crosses a docs/guvenlik-kurallari.md §3 limit.
# Stays on this Mac (docs/guvenlik-kurallari.md §2): never upload or commit it.
set -euo pipefail
# shellcheck source=../lib/ortak.sh
source "$(dirname "$0")/../lib/ortak.sh"
gerekli python3 zstd openssl ssh
ARAC="$(cd "$(dirname "$0")" && pwd)/arac"
TEL=${TELEFON:-172.16.42.1}
D=${1:-$YEDEK_KOK/tam-$(damga)}
mkdir -p "$D"; chmod 700 "$D"; touch "$D/SHA256SUMS"; chmod 600 "$D/SHA256SUMS"

t() { ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o ConnectTimeout=8 -o ServerAliveInterval=20 -o ServerAliveCountMax=6 -o LogLevel=ERROR \
	-i "$HOME/.ssh/razer_nicole" "user@$TEL" "$@"; }

koruma() {
	local a
	dur_kontrol
	a=$(t 'p=/sys/module/ufshcd_core/parameters/write_ranges; [ -e $p ] && echo "bos:$(cat $p)" || echo yok')
	[ "$a" = "bos:" ] || hata "yazma koruması kapalı değil ya da çekirdekte yok ($a)"
	# shellcheck disable=SC2016  # runs on the phone
	t 'for b in /sys/block/sd*; do doas blockdev --setro /dev/${b##*/}; done'
	# shellcheck disable=SC2016
	a=$(t 'for b in /sys/block/sd*; do echo "${b##*/} $(cat $b/ro)"; done')
	[ "$(wc -l <<<"$a")" -eq 6 ] || hata "6 LU bekleniyordu: $(tr '\n' ' ' <<<"$a")"
	! grep -qv ' 1$' <<<"$a" || hata "salt okunur olmayan disk var: $(tr '\n' ' ' <<<"$a")"
	! t 'grep -E "^/dev/sd" /proc/mounts /proc/swaps' || hata "UFS'ten bağlı bir şey var"
}

# oku <piece> <device> <dd args>: one compressed stream to the Mac, verified at both ends
oku() {
	local ad=$1 dev=$2 dd_arg=$3 n sik sha tel_sat tel_sha bos
	if grep -q "  $ad.img$" "$D/SHA256SUMS"; then bilgi "$ad zaten var, atlanıyor"; return; fi
	bilgi "$ad: /dev/$dev $dd_arg"
	# shellcheck disable=SC2016  # runs on the phone
	t "doas bash -c '
		set -o pipefail
		f=/run/yedek-$ad; rm -f \$f \$f.son; mkfifo \$f
		sha256sum < \$f > \$f.sha &
		s=\$!
		dd if=/dev/$dev $dd_arg 2>/dev/null | tee \$f | zstd -1 -T2 -q
		r=\$?
		wait \$s
		echo \"\$r \$(cut -d\" \" -f1 \$f.sha)\" > \$f.son
		rm -f \$f \$f.sha
	'" > "$D/$ad.img.zst" || hata "$ad: aktarım koptu"
	tel_sat=$(t "cat /run/yedek-$ad.son; doas rm -f /run/yedek-$ad.son")
	[ "${tel_sat%% *}" = 0 ] || hata "$ad: boru hattı çıkışı ${tel_sat%% *}"
	tel_sha=${tel_sat##* }
	# the phone hashed what it read; this hashes what landed here
	sha=$(zstd -dc "$D/$ad.img.zst" | tee >(wc -c | tr -d ' ' > "$D/.n") | openssl sha256 -r | cut -d' ' -f1)
	sleep 1
	n=$(cat "$D/.n"); rm -f "$D/.n"
	[ "$sha" = "$tel_sha" ] || hata "$ad: SHA-256 uyuşmuyor (telefon $tel_sha, Mac $sha)"
	echo "$sha  $ad.img" >> "$D/SHA256SUMS"
	chmod 600 "$D/$ad.img.zst"
	sik=$(stat -f %z "$D/$ad.img.zst")
	bilgi "$ad tamam: $n bayt ham, $sik bayt sıkışık, sha256 ${sha:0:16}…"
	echo "$ad $n" >> "$D/boyutlar.txt"
	bos=$(df -g "$D" | awk 'NR==2{print $4}')
	[ "$bos" -ge 10 ] || hata "Mac'te ${bos} GB kaldı (docs/guvenlik-kurallari.md §4)"
}

# Mac disk and phone limits, every 30 s, while a piece streams
gozcu() {
	while sleep 30; do
		local g b s
		g=$(df -g "$D" | awk 'NR==2{print $4}')
		b=$(t 'cat /sys/class/power_supply/qcom-battmgr-bat/temp /sys/class/power_supply/qcom-battmgr-bat/capacity; cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -1' 2>/dev/null | tr '\n' ' ') || continue
		# shellcheck disable=SC2086
		set -- $b
		s=$(date +%H:%M:%S)
		echo "$s disk=${g}G pil_sicaklik=${1:-?} yuzde=${2:-?} en_sicak=${3:-?}" >> "$D/gozcu.txt"
		if [ "$g" -lt 10 ] || [ "${1:-0}" -ge 450 ] || [ "${2:-100}" -le 15 ] || [ "${3:-0}" -ge 90000 ]; then
			echo "$s EŞİK AŞILDI, durduruluyor" >> "$D/gozcu.txt"
			t 'doas pkill -x dd; true' 2>/dev/null
			return
		fi
	done
}

koruma
eylem_kaydet "ufs-tam-yedek: başladı -> $D"
caffeinate -dimsw $$ &

# inventory: names, offsets and sizes from sysfs, GPT copies as files
# shellcheck disable=SC2016  # runs on the phone
t 'for d in /sys/block/sd*; do n=${d##*/}; echo "LU $n boyut=$(cat $d/size) mantiksal=$(cat $d/queue/logical_block_size) model=$(cat $d/device/model) rev=$(cat $d/device/rev) lun=$(basename $(readlink -f $d/device))"; for p in $d/$n*; do [ -e $p/partition ] || continue; echo "$n ${p##*/} $(grep PARTNAME= $p/uevent | cut -d= -f2) baslangic=$(cat $p/start) boyut=$(cat $p/size) $(grep -E "^PARTUUID|^PARTN=" $p/uevent 2>/dev/null | tr "\n" " ")"; done; done; cat /proc/cmdline' > "$D/disk.txt"
bilgi "$(grep -c '^sd' "$D/disk.txt") bölüm, $(grep -c '^LU' "$D/disk.txt") LU → $D/disk.txt"

gozcu &
GOZCU=$!
trap 'kill $GOZCU 2>/dev/null; true' EXIT

for lu in sdb sdc sdd sdf sde; do oku "$lu" "$lu" "bs=1M"; done

# LU 0 around userdata (sizes in 512-byte units in sysfs, disk blocks are 4096)
read -r u_bas u_boy < <(awk '$3=="userdata"{sub("baslangic=","",$4); sub("boyut=","",$5); print $4,$5}' "$D/disk.txt")
lu_boy=$(awk '$1=="LU" && $2=="sda"{sub("boyut=","",$3); print $3}' "$D/disk.txt")
[ -n "$u_bas" ] && [ -n "$u_boy" ] && [ -n "$lu_boy" ] || hata "userdata bulunamadı"
[ $((u_bas % 8)) = 0 ] && [ $((u_boy % 8)) = 0 ] && [ $((lu_boy % 8)) = 0 ] || hata "4K hizalı değil"
oku sda-on sda "bs=4096 count=$((u_bas / 8))"
kalan=$(( (lu_boy - u_bas - u_boy) / 8 ))
oku sda-son sda "bs=4096 skip=$(( (u_bas + u_boy) / 8 )) count=$kalan"
# userdata in 8 GiB pieces: a dropped link costs one piece, not 100 GB
ud=$(awk '$3=="userdata"{print $2}' "$D/disk.txt")
parca=8192
mib=$(( (u_boy + 2047) / 2048 ))   # the last dd stops at the end of the partition
i=0
while [ $((i * parca)) -lt "$mib" ]; do
	oku "$(printf 'sda-userdata-%03d' "$i")" "$ud" "bs=1M skip=$((i * parca)) count=$parca"
	i=$((i + 1))
done

kill $GOZCU 2>/dev/null || true
koruma

# Each partition read a second time on its own, for dogrula.py
bilgi "bölümler ikinci kez okunuyor (sağlama)"
# shellcheck disable=SC2016  # runs on the phone
t 'doas sh -c "for p in \$(ls /sys/class/block | grep -E \"^sd[a-z][0-9]+\$\"); do sha256sum /dev/\$p; done"' > "$D/bolum-sha256.txt"
koruma
python3 "$ARAC/tam-yedek-dogrula.py" "$D"
eylem_kaydet "ufs-tam-yedek: tamam ($D)"
bilgi "Bitti: $D ($(du -sh "$D" | cut -f1)); diskler hâlâ salt okunur"
