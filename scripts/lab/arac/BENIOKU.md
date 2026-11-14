# Lab yardımcıları (25 Ekim 2026 gecesi)

- `telnet.py [bekleme_sn]`: stdin'deki komutları mini initramfs'in telnet'inde (172.16.42.1:23) çalıştırır, çıktıyı yazar. Örnek: `printf 'dmesg\n' | scripts/lab/arac/telnet.py 5`
- `usb-izle.sh`: telefonun USB aygıt kümesindeki her değişikliği zamanıyla yazar (ioreg, macOS).

- `gonder.py HOST PORT`: stdin'i gönderir, sonra yazma yönünü kapatıp karşının kapatmasını bekler; gönderilenin bayt sayısını ve SHA-256'sını yazar (`scripts/lab/sd-ag-yaz.sh` kullanır).
- `dtbo-dok.py DTBO...`: dt_table başlığını, girdileri ve her overlay'in düğüm/özelliklerini döker (VM'de, python3-libfdt).
