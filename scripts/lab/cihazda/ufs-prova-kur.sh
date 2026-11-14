#!/bin/bash
# Rehearsal: copy the running SD system into one internal partition (default rawdump).
# Runs on the phone as root, from SD Linux, on a kernel whose
# ufshcd_core.write_ranges covers exactly that partition (docs/guvenlik-kurallari.md §8, 4 Nov).
#
# Layout is what the pmOS initramfs looks for: a GPT inside the partition (loop device
# with 4096-byte sectors) holding pmOS_boot and pmOS_root, with their own UUIDs. The SD
# card stays untouched and bootable. Prints the UUIDs for the boot image at the end.
#
# Usage: ufs-prova-kur.sh [BOLUM]     Refuses anything but rawdump unless the kernel
# range covers it AND UFS_KUR_ONAY=<BOLUM> is set. Never touches any other partition.
set -euo pipefail
BOLUM=${1:-rawdump}
hata() { echo "HATA: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || hata "root gerekli"
# A private mount namespace. Without it, services with their own namespace get a copy of these
# mounts and keep the new filesystem mounted and dirty after this script exits (4 Nov).
[ -n "${UFS_KUR_NS:-}" ] || UFS_KUR_NS=1 exec unshare -m --propagation private "$0" "$@"
[ "$BOLUM" = rawdump ] || [ "${UFS_KUR_ONAY:-}" = "$BOLUM" ] || hata "$BOLUM için UFS_KUR_ONAY gerekli"

P=$(readlink -f "/dev/disk/by-partlabel/$BOLUM")
[ -b "$P" ] || hata "$BOLUM bulunamadı"
n=${P##*/}; lu=${n%%[0-9]*}
[ "$(findmnt -n -o SOURCE / | sed 's#/dev/##; s#p[0-9]*$##')" = mmcblk1 ] || hata "kök SD'de değil"
grep -q "^$P " /proc/mounts && hata "$P bağlı"

# the kernel's range must be exactly this partition: no wider, no other
bas=$(( $(cat /sys/class/block/"$n"/start) / 8 )); boy=$(( $(cat /sys/class/block/"$n"/size) / 8 ))
lun=$(basename "$(readlink -f /sys/block/"$lu"/device)" | cut -d: -f4)
aralik=$(cat /sys/module/ufshcd_core/parameters/write_ranges)
[ "$aralik" = "$lun:$bas:$boy" ] || hata "çekirdek aralığı '$aralik', beklenen $lun:$bas:$boy"
echo "hedef: $BOLUM = $P, LU $lun, blok $bas + $boy (çekirdek aralığı aynı)"

# other disks stay read-only at the block layer as well; only this LU opens
for b in /sys/block/sd*; do
	d=${b##*/}
	[ "$d" = "$lu" ] || blockdev --setro "/dev/$d"
done
blockdev --setrw "/dev/$lu"
trap 'umount -R /mnt/ufs-prova 2>/dev/null || true; [ -n "${L:-}" ] && losetup -d "$L" 2>/dev/null || true; blockdev --setro "/dev/$lu"' EXIT

command -v rsync >/dev/null || apk add rsync
L=$(losetup --show -P -f --sector-size 4096 --direct-io=on "$P")
# 512 MiB boot (as on SD), the rest root
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

M=/mnt/ufs-prova
mkdir -p "$M"
mount "${L}p2" "$M"; mkdir -p "$M/boot"; mount "${L}p1" "$M/boot"
rsync -aHAXx --numeric-ids --exclude=/mnt/ufs-prova --exclude='/tmp/*' --exclude='/run/*' --exclude='/var/tmp/*' \
	--exclude=/lost+found / "$M/"
rsync -aHAXx --numeric-ids --exclude=/lost+found --exclude=/nicole-log /boot/ "$M/boot/"
mkdir -p "$M/boot/nicole-log"

cat > "$M/etc/fstab" <<EOF
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$ROOT_UUID / ext4 defaults 0 0
UUID=$BOOT_UUID /boot ext2 nodev,nosuid,noexec 0 0
EOF
# the initramfs must mount the partition with the sector size the table was written in.
# /etc/deviceinfo: the initramfs reads it after the package's file, and apk leaves it alone.
cat > "$M/etc/deviceinfo" <<'EOF'
# This install's root is on UFS: 4096-byte logical blocks. Overrides the package's SD value.
deviceinfo_rootfs_image_sector_size="4096"
EOF

# boot-deploy and nicole-imaj take the cmdline from here: without the range the root cannot write
mkdir -p "$M/etc/kernel-cmdline.d"
echo "ufshcd_core.write_ranges=$aralik" > "$M/etc/kernel-cmdline.d/60-ufs-yazma.conf"

# rslave: unmounting these below must not reach the running system's own mounts
for d in proc sys dev; do mount --rbind "/$d" "$M/$d"; mount --make-rslave "$M/$d"; done
chroot "$M" /bin/sh -c 'mkinitfs' 2>&1 | tail -3
sync
echo "boot=$BOOT_UUID root=$ROOT_UUID loop=$L"
df -h "$M" "$M/boot" | tail -2
umount -R "$M/dev" "$M/sys" "$M/proc" 2>/dev/null || true
cp "$M/boot/boot.img" "$M/boot/vmlinuz" "$M/boot/initramfs" "$M/boot/sm8350-razer-nicole.dtb" /var/tmp/ 2>/dev/null || hata "boot dosyaları alınamadı"
echo "UUID_BOOT=$BOOT_UUID"
echo "UUID_ROOT=$ROOT_UUID"
