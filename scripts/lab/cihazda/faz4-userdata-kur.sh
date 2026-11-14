#!/bin/bash
# Faz 4 (docs/guvenlik-kurallari.md §8, 8 Kasım 2026): set up slot A's root in userdata, copying the running
# rescue system (slot B, root in rawdump). Runs on the phone as root, booted from slot B,
# on a kernel whose ufshcd_core.write_ranges opens userdata.
#
# Layout as in ufs-prova-kur.sh (what the pmOS initramfs looks for): a GPT inside userdata
# (4096-byte sectors) with pmOS_boot (512 MiB) and pmOS_root (the rest), new UUIDs, so the
# initramfs tells the two installs apart by pmos_root_uuid. The target only opens its own
# partition for writing (60-ufs-yazma.conf = userdata), so slot A cannot touch the rescue.
# Builds slot A's boot images with nicole-imaj --kurulum into /var/tmp/imaj-userdata.
# Android's data in userdata is wiped (approved: docs/guvenlik-kurallari.md §8 Faz 4).
#
# Usage: FAZ4_ONAY=userdata faz4-userdata-kur.sh [nicole-imaj path]
set -euo pipefail
IMAJ=${1:-nicole-imaj}
BOLUM=userdata
hata() { echo "HATA: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || hata "root gerekli"
[ -n "${FAZ4_KUR_NS:-}" ] || FAZ4_KUR_NS=1 exec unshare -m --propagation private "$0" "$@"
[ "${FAZ4_ONAY:-}" = "$BOLUM" ] || hata "FAZ4_ONAY=$BOLUM gerekli"
grep -qw "androidboot.slot_suffix=_b" /proc/cmdline || hata "slot B'den (kurtarma) açılmış değil"

P=$(readlink -f "/dev/disk/by-partlabel/$BOLUM")
[ -b "$P" ] || hata "$BOLUM bulunamadı"
n=${P##*/}; lu=${n%%[0-9]*}
kaynak=$(findmnt -n -o SOURCE /)
[[ "$kaynak" =~ ^/dev/loop[0-9]+p2$ ]] || hata "kök bir UFS alt bölümü değil: $kaynak"
arka=$(readlink -f "$(cat /sys/block/"$(basename "${kaynak%p2}")"/loop/backing_file)")
[ "$arka" = "$(readlink -f /dev/disk/by-partlabel/rawdump)" ] || hata "kök rawdump'ta değil: $arka"
grep -q "^$P " /proc/mounts && hata "$P bağlı"
[ -z "$(losetup -j "$P")" ] || hata "$P bir loop aygıtına bağlı: $(losetup -j "$P")"

bs=$(cat /sys/block/"$lu"/queue/logical_block_size)
bas=$(( $(cat /sys/class/block/"$n"/start) * 512 / bs )); boy=$(( $(cat /sys/class/block/"$n"/size) * 512 / bs ))
lun=$(basename "$(readlink -f /sys/block/"$lu"/device)" | cut -d: -f4)
hedef_aralik="$lun:$bas:$boy"
aralik=$(cat /sys/module/ufshcd_core/parameters/write_ranges)
[[ ",$aralik," == *",$hedef_aralik,"* ]] || hata "çekirdek aralığı '$aralik', $hedef_aralik içermiyor"
echo "hedef: $BOLUM = $P, LU $lun, blok $bas + $boy ($(( boy * bs >> 30 )) GiB); kaynak $kaynak ($arka)"

# only LU $lu is writable at the block layer for this run
for b in /sys/block/sd*; do
	d=${b##*/}
	[ "$d" = "$lu" ] || blockdev --setro "/dev/$d"
done
M=/mnt/faz4-kur
trap 'umount -R "$M" 2>/dev/null || true; [ -n "${L:-}" ] && losetup -d "$L" 2>/dev/null || true' EXIT

command -v rsync >/dev/null || hata "rsync yok"
wipefs -q -a "$P"   # Android's f2fs signature, so nothing probes it as f2fs any more
L=$(losetup --show -P -f --sector-size 4096 --direct-io=on "$P")
sfdisk -q "$L" <<'EOF'
label: gpt
name=pmOS_boot, size=512MiB, type=linux
name=pmOS_root, type=linux
EOF
partprobe "$L" || true
sleep 1
[ -b "${L}p1" ] && [ -b "${L}p2" ] || hata "alt bölümler görünmedi"
BOOT_UUID=$(cat /proc/sys/kernel/random/uuid); ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
mkfs.ext2 -q -F -b 4096 -L pmOS_boot -U "$BOOT_UUID" "${L}p1"
mkfs.ext4 -q -F -b 4096 -L pmOS_root -U "$ROOT_UUID" "${L}p2"

mkdir -p "$M"
mount "${L}p2" "$M"; mkdir -p "$M/boot"; mount "${L}p1" "$M/boot"
t0=$(date +%s)
rsync -aHAXx --numeric-ids --exclude="$M" --exclude='/tmp/*' --exclude='/run/*' --exclude='/var/tmp/*' \
	--exclude=/lost+found / "$M/"
rsync -aHAXx --numeric-ids --exclude=/lost+found --exclude=/nicole-log /boot/ "$M/boot/"
mkdir -p "$M/boot/nicole-log"
echo "kopya $(( $(date +%s) - t0 )) sn"

cat > "$M/etc/fstab" <<EOF
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$ROOT_UUID / ext4 defaults 0 0
UUID=$BOOT_UUID /boot ext2 nodev,nosuid,noexec 0 0
EOF
cat > "$M/etc/deviceinfo" <<'EOF'
# This install's root is on UFS: 4096-byte logical blocks. Overrides the package's SD value.
deviceinfo_rootfs_image_sector_size="4096"
EOF
# slot A writes its own partition only (not the rescue's rawdump)
echo "ufshcd_core.write_ranges=$hedef_aralik" > "$M/etc/kernel-cmdline.d/60-ufs-yazma.conf"
echo "Faz 4 kurulumu $(date -Iseconds): slot A, kök userdata, kaynak $arka" > "$M/etc/nicole-kurulum"

for d in proc sys dev; do mount --rbind "/$d" "$M/$d"; mount --make-rslave "$M/$d"; done
chroot "$M" /bin/sh -c 'mkinitfs' 2>&1 | tail -2
umount -R "$M/dev" "$M/sys" "$M/proc" 2>/dev/null || true
rm -rf /var/tmp/imaj-userdata
"$IMAJ" --kurulum "$M" --cikti /var/tmp/imaj-userdata
sync
df -h "$M" "$M/boot" | tail -2
echo "UUID_BOOT=$BOOT_UUID"
echo "UUID_ROOT=$ROOT_UUID"
