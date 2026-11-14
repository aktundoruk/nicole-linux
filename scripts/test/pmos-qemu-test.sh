#!/usr/bin/env bash
# End-to-end test of the postmarketOS image WITHOUT the device (run on the Mac).
#
# Boots the exported pmOS kernel + initramfs with the rootfs image as a virtio disk in
# QEMU (inside the Lima VM; QEMU's own DT, not nicole's) and checks over SSH from the Mac
# (Lima forwards the VM's 127.0.0.1:2222):
#   - pmOS initramfs finds pmOS_root by UUID, systemd boots, sshd runs
#   - login as "user" with ~/.ssh/razer_nicole (BatchMode: no password prompt)
#   - "doas -n" works (razer-nicole-lab), reboot-mode installed, no plymouth (nosplash)
#   - kernel cmdline from the device package (loglevel=8 ignore_loglevel, no "splash")
#   - "doas reboot-mode bootloader" (izle.sh's safety stop) restarts with 'bootloader'
# Then also runs scripts/build/qemu-smoke.sh (mini initramfs USB path).
#
# Usage: scripts/test/pmos-qemu-test.sh
set -euo pipefail
export LIMA_HOME="${LIMA_HOME:-$HOME/.lima}"
PORT=2222
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error
	-o ConnectTimeout=5 -i "$HOME/.ssh/razer_nicole" -p "$PORT" user@127.0.0.1)
hata=0
ok()   { echo "  OK   $*"; }
fail() { echo "  HATA $*"; hata=1; }
vm()   { limactl shell razer bash -lc "$1"; }

nc -z -G 1 127.0.0.1 "$PORT" 2>/dev/null && { echo "port $PORT busy (old QEMU?)"; exit 1; }

echo "QEMU başlatılıyor"
vm '
set -e
E=$WORK/pmos-export
CMD=$(unpack_bootimg --boot_img "$RAZER_PROJECT/out/pmos/pmos-boot.img" --out /tmp/pq-unpack | sed -n "s/^command line args: //p" | sed "s/console=tty0//")
echo "$CMD" > /tmp/pq-cmdline
gzip -dc $E/vmlinuz > /tmp/pq-Image 2>/dev/null || cp -L $E/vmlinuz /tmp/pq-Image
cp -L $E/razer-nicole.img /tmp/pq-disk.img
nohup timeout 900 qemu-system-aarch64 -M virt -cpu max -accel tcg -smp 4 -m 3072 -nographic -no-reboot \
  -kernel /tmp/pq-Image -initrd $E/initramfs -append "console=ttyAMA0 $CMD" \
  -drive file=/tmp/pq-disk.img,if=virtio,format=raw \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:'"$PORT"'-:22 -device virtio-net-pci,netdev=n0 \
  > /tmp/pq-qemu.log 2>&1 < /dev/null &
'
girdi=0
for _ in $(seq 1 90); do
	if "${SSH[@]}" true 2>/dev/null; then girdi=1; break; fi
	sleep 5
done
if [ "$girdi" = 1 ]; then ok "SSH anahtarla giriş (user)"; else fail "SSH girişi yok (7,5 dk)"; vm 'tail -20 /tmp/pq-qemu.log'; fi

if [ "$girdi" = 1 ]; then
	sonuc=$("${SSH[@]}" '
		echo "kernel=$(uname -r)"
		doas -n true && echo doas=ok
		command -v reboot-mode >/dev/null && echo rebootmode=ok
		apk info -e plymouth >/dev/null 2>&1 && echo plymouth=var || echo plymouth=yok
		systemctl is-active sshd >/dev/null 2>&1 && echo sshd=ok
		echo "cmdline=$(cat /proc/cmdline)"
	')
	echo "$sonuc" | grep "^kernel=" | sed 's/^/       /'
	grep -q "^doas=ok" <<<"$sonuc" && ok "doas -n (parolasız root)" || fail "doas -n çalışmıyor"
	grep -q "^rebootmode=ok" <<<"$sonuc" && ok "reboot-mode kurulu" || fail "reboot-mode yok"
	grep -q "^plymouth=yok" <<<"$sonuc" && ok "plymouth yok (açılış mesajları ekranda)" || fail "plymouth kurulu"
	grep -q "^sshd=ok" <<<"$sonuc" && ok "sshd aktif" || fail "sshd aktif değil"
	c=$(grep "^cmdline=" <<<"$sonuc")
	{ grep -q "loglevel=8" <<<"$c" && grep -q "ignore_loglevel" <<<"$c" && ! grep -qw "splash" <<<"$c"; } \
		&& ok "cmdline: loglevel=8 ignore_loglevel, splash yok" || fail "cmdline beklenen gibi değil: $c"

	"${SSH[@]}" 'sync; doas -n reboot-mode bootloader' >/dev/null 2>&1 || true
	sleep 5
	if vm 'grep -q "Restarting system with command .bootloader." /tmp/pq-qemu.log'; then
		ok "güvenlik freni: 'reboot-mode bootloader' parolasız çalıştı"
	else
		fail "reboot-mode bootloader çalışmadı"
	fi
fi
vm 'pkill -f "[q]emu-system-aarch64.*pq-disk" || true; rm -f /tmp/pq-disk.img'

echo "mini initramfs USB testi"
if vm 'cd "$RAZER_PROJECT" && bash scripts/build/qemu-smoke.sh' 2>&1 | grep -E "SMOKE (dhcp|telnetd|acm)|PASS|FAIL" | sed 's/^/    /' | tee /dev/stderr | grep -q PASS; then
	ok "qemu-smoke.sh"
else
	fail "qemu-smoke.sh"
fi
[ "$hata" = 0 ] && echo "SONUÇ: GEÇTİ" || { echo "SONUÇ: BAŞARISIZ"; exit 1; }
