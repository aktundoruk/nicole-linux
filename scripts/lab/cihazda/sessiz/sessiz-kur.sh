#!/bin/sh
# Arm the silent-boot experiment and reboot into it. Run as root on the phone:
#   doas sh /var/lib/uyku-test/sessiz-kur.sh [uyku-sessiz-a.conf]
# Without an argument the whole LPASS audio stack stays out (uyku-sessiz.conf); a
# variant conf keeps only part of it out. Files are expected next to this script in
# /var/lib/uyku-test/.
set -e
U=/var/lib/uyku-test
cp $U/${1:-uyku-sessiz.conf} $U/uyku-sessiz-etkin.conf
cp $U/sessiz-erken.service $U/sessiz-deney.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable sessiz-erken.service sessiz-deney.service
touch $U/sessiz-bir-kez
echo "sessiz açılış kuruldu; yeniden başlatılıyor"
sync; systemctl reboot
