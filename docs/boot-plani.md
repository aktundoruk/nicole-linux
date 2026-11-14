# Boot planı — mainline çekirdeği `fastboot boot` ile açmak (nicole)

> Durum: cihaz bağlanmadan önce hazırlandı (5 Ekim 2026). Proje kuralı: ilk açılışlar **yalnız RAM'den** (`fastboot boot`), hiçbir bölüme yazılmaz. Bölüme yazan her adım docs/guvenlik-kurallari.md'deki seviyesiyle işaretlidir.
> İmajları `scripts/build/make-bootimg.sh` üretir (asla flash/erase yapmaz); denemeyi `scripts/lab/deneme.sh <imaj> <etiket>` yürütür ve kaydeder.

## 0. Kısa cevap

**İlk deneme (Deneme 1):** Xperia 1 III (aynı SoC ailesi, aynı Qualcomm ABL kuşağı) için çalıştığı bilinen tarif:

- **boot header v1**, `Image.gz` + **DTB sona eklenmiş** (`cat Image.gz sm8350-razer-nicole.dtb`), ayrı DTB bölümü yok,
- DTB'de **`qcom,msm-id` / `qcom,board-id` YOK** (mevcut `dts/sm8350-razer-nicole.dts` zaten böyle),
- DTB `-@` ile derlenmiş (sembol tablosu var), pagesize 4096, base 0,
- küçük bir initramfs (USB NCM + ACM + telnet) — `make-bootimg.sh` bunu `d1-v1-appended.img` olarak üretir.

Bunun başarısız olmasının en olası nedeni **`dtbo` bölümü**dür: ABL, aktif slotun `dtbo` bölümündeki Razer overlay'ini bizim DTB'mize uygulamaya çalışır. `fastboot boot` bunu atlatamaz. Kesin çözüm (Sony'nin yöntemi) `dtbo` bölümünün başına 2 sıfır bayt yazmaktır → bizde bu yalnız **B slotunda** ve **Seviye 2** onayıyla yapılabilir (Deneme 3).

Bulunan kimlikler (yedek plan için): **`qcom,msm-id = <439 0x20001>`** (SG8175P v2.1), **`qcom,board-id = <0x1001f 0x02>`** (HDK platform tipi 0x1f, platform sürümü 1, alt tip 2).

## 1. Arka plan

### 1.1 Önyükleme zinciri

PBL → XBL → (hyp/TZ) → **ABL** (Qualcomm UEFI "LinuxLoader", `abl` bölümü) → çekirdek. `fastboot` ABL'nin kendisidir; `fastboot boot X.img` görüntüyü RAM'e alır ve normal açılış yolunu o görüntüyle çalıştırır. Cihazın kilidi açık olmalı (`fastboot getvar unlocked` → `yes`); açık kilitte ABL turuncu "doğrulanmamış" uyarısını ~5 sn gösterir.

### 1.2 Cihazın kendi düzeni (LineageOS `BoardConfig.mk`)

- `BOARD_BOOT_HEADER_VERSION := 3`, `BOARD_KERNEL_PAGESIZE := 4096`, `BOARD_KERNEL_BASE := 0x00000000`.
- `BOARD_INCLUDE_DTB_IN_BOOTIMG := true` + `vendor_boot` bölümü: v3'te DTB **vendor_boot**'ta durur (boot.img v3'te DTB alanı yoktur).
- `BOARD_KERNEL_SEPARATED_DTBO := true`: overlay'ler ayrı `dtbo` bölümünde. Razer DTB'leri: taban `lahainap.dtb`, `lahainap-v2.dtb`, `lahainap-v2.1.dtb` (`qcom,board-id = <0 0>`), overlay `lahainap-nicole-overlay.dtbo` (`qcom,board-id = <0x1001f 0x02>`) — `sources/razer-kernel/.../vendor/qcom/Makefile:1–9`.
- Bölüm boyutları: boot 96 MiB, vendor_boot 96 MiB, dtbo 24 MiB (yalnız flash için önemli).

### 1.3 `fastboot boot` ile v3 sorunu

v3/v4 bir boot.img gönderirsek ABL DTB'yi ve vendor ramdisk'i **aktif slotun `vendor_boot` bölümünden** alır → Razer'ın downstream DTB'si + mainline çekirdek = çalışmaz. Bu yüzden ilk denemeler **v1/v2** ile yapılır: v0–v2'de DTB ya çekirdeğin sonuna eklenir (appended) ya da v2'nin DTB alanına konur ve `vendor_boot` hiç okunmaz.

Kanıtlar (ABL'nin v3/v4 ile gelen cihazlarda v1/v2 kabul ettiği):
- Sony Xperia 1 III (SM8350, Android 11 ile v3 çıktı): pmOS `deviceinfo_header_version="1"`, `deviceinfo_append_dtb="true"` (`sources/pmaports/device/testing/device-sony-pdx215/deviceinfo`). Upstream DT commit'i de `mkbootimg --header_version 1` ile appended DTB kullanıyor.
- Fairphone 5 (QCM6490, aynı ABL kuşağı, vendor_boot'lu) ve Nothing Phone (1) (SM7325): pmOS `deviceinfo_header_version="2"` + `append_dtb="true"`.

## 2. ABL'nin DTB ile yaptıkları

### 2.1 DTB seçimi ve `qcom,msm-id` / `qcom,board-id`

- Klasik Qualcomm ABL, ekli (veya v2 alanındaki) DTB'ler arasından SoC kimliği (`qcom,msm-id`), kart kimliği (`qcom,board-id`) ve PMIC kimliğine en iyi uyanı seçer.
- **SM8350'ye özgü uyarı** — mainline `sm8350-sony-xperia-sagami.dtsi` (Konrad Dybcio): *"there is NO MORE {msm,board,pmic}-id on SM8350! Adding it will cause the bootloader to go crazy and randomly crash shortly after closing UEFI boot services."* Mainline'daki hiçbir SM8350 DTS'i (hdk, mtp, sagami) bu özellikleri taşımıyor. Tek DTB varsa ABL kimliksiz DTB'yi kullanıyor.
- Bu yüzden: **varsayılan = kimliksiz**. Kimlikli varyant (`d4-v2-ids.img`) yalnız ABL "DTB bulunamadı" türü bir hata verirse denenir.
- nicole değerleri (Razer kaynaklarından):
  - `qcom,msm-id = <439 0x20001>` — `lahainap-v2.1.dtsi:6` (`<439 0x20001>, <502 0x20001>`; 502 = SM8325P, bu SKU'yla ilgisiz). Downstream `socinfo.c:774`: 439 = "SG8175P". v1/v2.0 silikonda `0x10000`/`0x20000`; gerçek değer `TODO(cihaz)`: `cat /sys/devices/soc0/revision`.
  - `qcom,board-id = <0x1001f 0x02>` — `lahainap-nicole.dts:8`, `lahainap-nicole-overlay.dts:9`. Çözümleme: `0x1f` = 31 = HDK platform tipi, `(0x1001f >> 16) & 0xff = 1` platform ana sürümü, ikinci hücre `0x02` alt tip. Mainline `qcom,ids.h`'te HDK için makro yok (`QCOM_BOARD_ID()` yalnız MTP/DRAGONBOARD/QRD/SBC) → ham sayı yazılmalı.
  - Android'de doğrulama: `xxd /proc/device-tree/qcom,msm-id`, `xxd /proc/device-tree/qcom,board-id` (ABL'nin seçtiği/birleştirdiği DTB'yi gösterir).

### 2.2 DTBO (overlay) — ana risk

- ABL, DTB'yi seçtikten sonra **aktif slotun `dtbo` bölümünden** uygun overlay'i bulup uygular. Bu, boot.img'in nereden geldiğinden bağımsızdır; `fastboot boot` da etkilenir.
- Mainline DTB'ye Razer overlay'i uygulanamaz (hedef etiketler — `qupv3_se12_spi`, `sde_dsi`, `pmk8350_adc_tm` … — mainline'da yok). Sonuç ABL'ye göre değişiyor: bootloader menüsüne dönme ya da çekirdeğe garip bir DTB verme.
- Sony'nin (SM8350) upstream DT commit'indeki talimat: `fastboot flash dtbo emptydtbo.img` — *"emptydtbo.img is a tiny file that consists of 2 bytes (all zeroes), doing a 'fastboot erase' won't cut it, the bootloader will go crazy … when it tries to overlay random bytes from an empty partition onto a perfectly good appended DTB."* (<https://lkml.iu.edu/hypermail/linux/kernel/2111.1/06489.html>). Yani **erase değil, başlığı bozan 2 sıfır bayt**. (Bizde `fastboot erase` zaten Seviye 4 yasak.)
- SM8550 tartışması (2026): ABL'nin bir dtbo uygulayabilmesi için taban DTB'de `qcom_tzlog` ve `arch_timer` **etiketleri** bulunmalı; yoksa bootloader menüsüne düşüyor. pmOS'ta genel uygulama `fastboot erase dtbo` (<https://lkml.iu.edu/2602.3/10118.html>, <https://lkml.iu.edu/hypermail/linux/kernel/2602.1/00445.html>).
- Mevcut taslak DTB'de (`dts/sm8350-razer-nicole.dts`, `-@` ile derlendi) bu iki etiket **yok** (463 sembol var, `qcom_tzlog`/`arch_timer` değil). DTS ekibine öneri: `/ { timer { … } }` düğümüne `arch_timer` etiketi ve boş bir `qcom_tzlog: tz-log { status = "disabled"; }` benzeri düğüm eklemek ucuz bir ek önlem; asıl çözüm yine boş dtbo.
- Yan etki ihtimali: overlay başarıyla uygulanırsa, mainline'da da bulunan aynı adlı etiketlere (`tlmm`, `sdhc_2`, `pcie1`, `thermal_zones`…) downstream özellikleri eklenir. Bunu görmek için cihazdan alınan `dtbo` imajı `scripts/build/dtbo-araci.py etiketler dtbo.img sm8350-razer-nicole.dtb` ile incelenir (hangi overlay girdisi, hangi `__fixups__` etiketleri, hangileri bizim DTB'de de var).

### 2.3 ABL'nin DTB'ye yazdıkları

- `/memory` düğümünün `reg`'ini DDR haritasıyla doldurur (mainline `sm8350.dtsi:303` `memory@80000000 { reg = <0 0x80000000 0 0>; }` — "bootloader doldurur" diye bırakılmış; libfdt `"/memory"` yolunu `memory@80000000` ile eşleştirir).
- `/chosen`: `bootargs` (boot.img cmdline + ABL'nin eklediği `androidboot.*`, `msm_drm.dsi_display0=…` vb.), `linux,initrd-start/end`, `kaslr-seed`.
- Sürekli splash: ABL ekranı açık bırakır, çerçeve tamponu `0xe1000000` (`lahaina.dtsi:516` `splash_region`, 0x2300000 bayt). DTS'te `cont_splash_mem` (no-map) + `simple-framebuffer` var. U-Boot belgesi yeni cihazlarda ABL'nin DTB'nin **etiketlerle (`-@`) derlenmesini ve splash bölgesinin `cont_splash` etiketiyle adlandırılmasını** beklediğini söylüyor (<https://github.com/u-boot/u-boot/blob/master/doc/board/qualcomm/phones.rst>) — mevcut DTS'teki `cont_splash_mem` etiketi buna uyuyor.
- Çekirdek yükleme adresleri: arm64 `Image` için ABL mkbootimg ofsetlerini büyük ölçüde yok sayar; pmOS'un standart ofsetleri kullanılır (`kernel 0x8000`, `ramdisk 0x1000000`, `tags 0x100`, `dtb 0x1f00000`, base 0).
- `--os_version`/`--os_patch_level`: Sony tarifinde var. `make-bootimg.sh` varsayılanı `12.0.0` / `2023-02` (LineageOS `BOOT_SECURITY_PATCH`); en doğrusu Faz 0'da yedeklenen `boot_a.img`'ten okumak: `unpack_bootimg --boot_img yedek/boot_a.img`.

## 3. Karar ağacı

Her deneme: `scripts/lab/deneme.sh <imaj> <etiket>` (fastboot'a döndürür, `fastboot boot` çalıştırır, 5/20/60/120 sn'de webcam karesi alır, 172.16.42.1'de 22/23 portunu yoklar, sonucu `log/denemeler/ozet.tsv`'ye yazar). Aynı hedef için 25 deneme / 8 saat sınırı geçerli (docs/guvenlik-kurallari.md §4.5).

```
Deneme 0  stok boot_a.img'i fastboot boot ─┬─ Android açılıyor → mekanizma çalışıyor → Deneme 1
                                           └─ "boot" komutu reddediliyor → DUR (ABL fastboot boot'u kapatmış olabilir; karar gerekir)
Deneme 1  d1-v1-appended (kimliksiz)      ─┬─ USB'de NCM/ACM + telnet → M1 yolunda (§6)
                                           ├─ fastboot hata döndü → Deneme 2
                                           ├─ ABL menüsüne geri döndü / ekranda DTB/DTBO hatası → Deneme 2, sonra 3
                                           └─ splash'ta donma / yeniden başlama döngüsü → §3.7 teşhis, sonra Deneme 3
Deneme 2  d2-v2-dtb (kimliksiz)           ─┬─ çalıştı → v2 ile devam
                                           └─ aynı hata → Deneme 3 (Seviye 2 onayı gerekli)
Deneme 3  dtbo_a ← emptydtbo + slot A     ─┬─ çalıştı → kalıcı çözüm bu; ileride vendor_boot_a'ya gerek yok
           (Seviye 2)                      └─ hâlâ hata → Deneme 4
Deneme 4  d4-v2-ids (msm/board-id'li)     ─┬─ çalıştı → kimlikli DTB ile devam (sagami uyarısına rağmen)
                                           └─ hata → Deneme 5
Deneme 5  v3 boot + vendor_boot_a (Seviye 2) → ABL v<3'ü hiç kabul etmiyorsa
Deneme 6  U-Boot zincirleme (SM8350 U-Boot portu gerekir) → uzun vadeli
```

### 3.0 Hazırlık (Seviye 1)

1. `scripts/faz0/04-fastboot-bilgi.sh` → `fastboot getvar all`: `unlocked`, `current-slot`, `slot-count`, `max-download-size`, `partition-size:dtbo_a`, `version-bootloader`, `product`.
2. Faz 0 yedeği: `boot_a/b`, `vendor_boot_a/b`, `dtbo_a/b`, `vbmeta*` (sha256'lı) — Deneme 3/5 bunlar olmadan yapılamaz.
3. `unpack_bootimg --boot_img yedek/boot_a.img` ve `--boot_img yedek/vendor_boot_a.img`: header sürümü, `os_version`, `os_patch_level`, cmdline doğrulanır.
4. `python3 scripts/build/dtbo-araci.py bilgi yedek/dtbo_a.img` → overlay girdileri ve kimlikleri; `etiketler …` → bizim DTB ile çakışan/eksik etiketler.
5. Android'de (root): `cat /proc/cmdline` (ABL'nin eklediği argümanlar), `cat /sys/devices/soc0/{soc_id,revision}`, `xxd /proc/device-tree/qcom,{msm,board}-id`, `cat /proc/iomem` (ramoops için boş bölge, splash adresi).

### 3.1 Deneme 0 — Mekanizma testi (Seviye 1)

```bash
scripts/lab/deneme.sh yedek/boot_a.img d0-stok-boot
```
Başarı: Android açılır (ADB görünür). Bu, `fastboot boot`'un bu ABL'de açık olduğunu ve RAM'den açılışın slotu değiştirmediğini kanıtlar.

### 3.2 Deneme 1 — v1 + appended DTB, kimliksiz (Seviye 1) — ÖNERİLEN

```bash
cat Image.gz sm8350-razer-nicole.dtb > Image.gz-dtb
mkbootimg --header_version 1 \
  --kernel Image.gz-dtb --ramdisk initramfs-mini.cpio.gz \
  --cmdline "$CMDLINE" \
  --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00000000 --tags_offset 0x00000100 --pagesize 4096 \
  --os_version 12.0.0 --os_patch_level 2023-02 \
  -o d1-v1-appended.img
scripts/lab/deneme.sh out/boot/d1-v1-appended.img d1-v1-appended
```

### 3.3 Deneme 2 — v2, DTB alanı + appended (Seviye 1)

```bash
mkbootimg --header_version 2 \
  --kernel Image.gz-dtb --ramdisk initramfs-mini.cpio.gz \
  --dtb sm8350-razer-nicole.dtb --dtb_offset 0x01f00000 \
  --cmdline "$CMDLINE" \
  --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 --pagesize 4096 \
  --os_version 12.0.0 --os_patch_level 2023-02 \
  -o d2-v2-dtb.img
```
(pmOS'un `header_version=2` + `append_dtb=true` ile ürettiği biçimin aynısı.)

### 3.4 Deneme 3 — Boş dtbo, yalnız A slotu (Seviye 2: `dtbo_a` yazma + slot değiştirme onayı gerekli)

> Slot düzeni (24 Ekim 2026): **B = Android güvenlik ağı, A = bizim slotumuz.** Cihaz ilk bağlandığında Android B'den açılıyordu.

Önkoşul: `yedek/` altında `dtbo_a.img` ve sha256'sı; B slotundaki Android açılabiliyor.

```bash
head -c 2 /dev/zero > emptydtbo.img          # make-bootimg.sh üretir: out/boot/emptydtbo.img
fastboot flash dtbo_a emptydtbo.img          # Seviye 2 — betiklerimiz bunu ÇALIŞTIRMAZ, elle/onaylı akışla
fastboot --set-active=a
fastboot boot d1-v1-appended.img             # (veya d2-v2-dtb.img)
# ... deneme sonrası:
fastboot --set-active=b
```
- `fastboot boot` RAM'deki imajı açar ama DTBO'yu **aktif slottan** okur; bu yüzden A'yı aktif yapmak gerekir. B slotu (Android) hiç değişmez.
- A aktifken açılış zincirinin A kopyaları çalışır (`xbl_a`, `abl_a`); bunlar B'dekilerden eski olabilir. ABL davranışı Deneme 1–2'dekinden (B'nin ABL'si) farklıysa bunu hesaba kat.
- A aktifken cihaz kendiliğinden yeniden başlarsa A'daki eski Android'i açmaya çalışır (dtbo_a boş olduğu için muhtemelen başarısız olur ve A/B mantığı birkaç denemeden sonra B'ye döner; `slot-retry-count` 6 olduğundan bu uzun sürebilir). Deneme bitince **mutlaka `--set-active=b`**.
- Geri alma: `fastboot flash dtbo_a yedek/dtbo_a.img`.
- Alternatif (daha zarif, denenmemiş): Razer overlay'inin kimlikleriyle eşleşen ama içi boş tek girdili bir dtbo (`make-bootimg.sh` → `dtbo-bos-overlay.img`). Bazı eski SoC'lerde pmOS bunu kullanıyor ("blank dtbo that just has qcom,board-id"). İlk tercih yine 2 baytlık dosya.

### 3.5 Deneme 4 — Kimlikli DTB (Seviye 1)

`make-bootimg.sh`, DTB'nin bir kopyasına `fdtput` ile ekler:
```bash
fdtput -t u nicole-ids.dtb / qcom,msm-id 439 131073      # <439 0x20001>
fdtput -t u nicole-ids.dtb / qcom,board-id 65567 2       # <0x1001f 0x02>
```
ve Deneme 2 komutunu bu DTB ile çalıştırır (`d4-v2-ids.img`). Sagami uyarısı nedeniyle "ExitBootServices sonrası rastgele çökme" belirtisine dikkat.

### 3.6 Deneme 5 — v3 + kendi vendor_boot'umuz (Seviye 2: `vendor_boot_a`)

Yalnız ABL v1/v2'yi açıkça reddederse (ör. header sürümü hatası):
```bash
mkbootimg --header_version 3 --kernel Image.gz --ramdisk initramfs-mini.cpio.gz \
  --cmdline "$CMDLINE" --os_version 12.0.0 --os_patch_level 2023-02 -o d5-boot-v3.img
: | cpio -o -H newc | gzip -9 > vendor-ramdisk-empty.cpio.gz   # v3 vendor_boot ramdisk ister
mkbootimg --header_version 3 --vendor_boot d5-vendor_boot-v3.img \
  --vendor_ramdisk vendor-ramdisk-empty.cpio.gz \
  --dtb sm8350-razer-nicole.dtb --vendor_cmdline "" \
  --base 0x00000000 --pagesize 4096 --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 --tags_offset 0x00000100 --dtb_offset 0x01f00000
# Seviye 2: fastboot flash vendor_boot_a d5-vendor_boot-v3.img ; dtbo_a ← emptydtbo ; --set-active=a
fastboot boot d5-boot-v3.img
```

### 3.7 Belirtiler ve anlamları

| Gözlem (ekran / fastboot / USB) | Muhtemel anlam | Sonraki adım |
|---|---|---|
| `fastboot boot` hemen `FAILED (remote: …)` döndürür, cihaz fastboot'ta kalır | ABL imajı reddetti (header/boyut/sayfa boyutu) | `unpack_bootimg` ile imajı kontrol et; boyut < `max-download-size`; diğer header sürümü |
| `Booting OKAY`, birkaç saniye sonra ABL menüsüne/fastboot'a döner, ekranda kırmızı/sarı hata satırı | DTB seçilemedi veya DTBO uygulanamadı | Webcam karesindeki metni oku; Deneme 2 → 3 (DTBO) veya 4 (DTB bulunamadı) |
| Turuncu uyarı → Razer logosu/siyah ekranda donma, USB kopuk, 2 dk'dan uzun | Çekirdek erken aşamada asılı (simpledrm'den önce) veya ekran çerçevesi yanlış | Zorla yeniden başlat; `panic=30`'u koru; DTB'deki `memory`, `reserved-memory`, `simple-framebuffer` gözden geçir; mini initramfs'te `nicole.sinyal=reboot` ile "userspace'e ulaştı mı" testini yap (§5.2) |
| Ekranda çekirdek logu akıyor ama USB'de yeni cihaz yok | Çekirdek çalışıyor; DWC3/PHY/gadget sorunu | Logdaki son satırlar (webcam); `dr_mode = "peripheral"`, `CONFIG_USB_CONFIGFS=y`, PHY sürücüleri yerleşik mi |
| Döngüsel yeniden başlama | Panic (`panic=30`) veya hipervizör/watchdog sıfırlaması (sagami'nin "msm-id" belirtisi) | Kimlikli DTB kullanılıyorsa kaldır; `clk_ignore_unused pd_ignore_unused` var mı |
| Cihaz Android'e açıldı | (a) Bizim init `sysrq b` yaptı (bilerek), (b) çekirdek erken reset → ABL normal açılış | Sinyal testiyse başarı; değilse (b) gibi değerlendir |
| Siyah ekran, Mac'te `05c6:900e` (Qualcomm ramdump/"crashdump") | XBL crashdump moduna girdi | Uzun basarak zorla yeniden başlat. **EDL/Sahara araçları kullanılmaz** (Seviye 4) |
| Mac'te yeni USB ağ arayüzü + `/dev/cu.usbmodem*` | Başarı: initramfs çalışıyor | `nc 172.16.42.1 23`, `cat /proc/cmdline; dmesg` (deneme.sh otomatik toplar) |

## 4. Kurtarma

1. Cihaz fastboot'taysa: hiçbir şey kaybolmadı; `fastboot reboot` → B slotundaki Android.
2. Yanıt yoksa: **Güç (+ Ses Kısma) ~10–20 sn** basılı tut → PMIC sıfırlaması; yeniden başlarken **Ses Kısma basılı** kalırsa fastboot'a girer. (Razer Edge'in tam tuş kombinasyonu ve süreleri `TODO(cihaz)`; otomatik tuş düzeneği kullanılmıyor, reset elle yapılır.)
3. Slot A aktif kaldıysa: fastboot'ta `fastboot --set-active=b` → `fastboot reboot`.
4. Seviye 2 yazımlarının geri alınması: `fastboot flash dtbo_a yedek/dtbo_a.img`, `fastboot flash vendor_boot_a yedek/vendor_boot_a.img`.
5. B slotuna hiçbir aşamada yazılmadığı için Android her zaman geri dönüş yoludur (`docs/geri-donus.md`).

## 5. Çekirdek komut satırı

### 5.1 Önerilen (ilk açılışlar)

```
console=tty0 fbcon=rotate:1 fbcon=font:TER16x32 loglevel=8 ignore_loglevel printk.devkmsg=on clk_ignore_unused pd_ignore_unused panic=30 softlockup_panic=1 hung_task_panic=1 hardlockup_panic=1 rcupdate.rcu_cpu_stall_panic=1
```

| Argüman | Neden |
|---|---|
| `console=tty0` | Kernel mesajları simpledrm üzerindeki fbcon'a; UART pedleri bilinmiyor. (DTS'teki `stdout-path = serial0` UART'a da yazar.) |
| `fbcon=rotate:1` | Panel 1080×2400 dikey, cihaz yatay kullanılıyor; doğru değer 1 veya 3 — webcam'den kontrol (`TODO(cihaz)`). |
| `fbcon=font:TER16x32` | Webcam'den okunabilir büyük font (`CONFIG_FONT_TER16x32=y`). |
| `loglevel=8 ignore_loglevel printk.devkmsg=on` | Her şey ekrana. |
| `clk_ignore_unused pd_ignore_unused` | `simple-framebuffer` ve henüz sürücüsü olmayan bloklar için kullanılmayan saat/güç alanlarının kapatılmasını engeller (DRM_MSM gelene kadar). |
| `panic=30` | Panik ekranını 30 sn gösterip yeniden başlar (webcam yakalar, cihaz kendiliğinden kurtulur). Süresiz beklemek için `panic=0`. |

Eklenebilecekler: `regulator_ignore_unused` (çekirdek destekliyorsa; simplefb düğümü beslemeleri zaten tutuyor), `initcall_debug` (asılmanın yerini bulmak için), `pmos.debug-shell` (pmOS initramfs ile).

- ABL kendi argümanlarını ekler (`androidboot.*`, `msm_drm.dsi_display0=…`); mainline için zararsız. Dinamik bölümlü (super) cihazlarda ABL `root=`/`skip_initramfs` eklemiyor olmalı — ilk açılışta `/proc/cmdline` ile doğrula.
- **Kök dosya sistemi microSD'de:** UFS DTS'te kapalı (docs/guvenlik-kurallari.md §2 Seviye 4), MMC olarak yalnız `sdhc_2` var. DTS'te `aliases { mmc1 = &sdhc_2; }` olduğu için mainline kartı **`/dev/mmcblk1`** olarak adlandırır (mmcblk numarası alias'ı izler) → `mmcblk0p2` değil. Ad yerine `root=PARTUUID=<…> rootwait rw` (veya pmOS'un etiket araması) kullanılmalı.

### 5.2 Mini initramfs (Deneme 1–5 için)

`scripts/build/mkinitramfs-mini.sh`, Ubuntu'nun statik busybox'ı ile ~1 MB'lık bir initramfs kurar:
- `/proc`, `/sys`, `devtmpfs`, `configfs`, `debugfs` bağlar; UDC'yi 60 sn bekler.
- configfs gadget: **NCM** (`ncm.usb0`) + **ACM** (`acm.GS0`) [+ isteğe bağlı ECM]; `usb0` = `172.16.42.1/24`, `udhcpd` istemciye `172.16.42.2` verir.
- `telnetd -b 172.16.42.1:23 -l /bin/sh` (busybox'ta varsa; yoksa `nc -ll -p 23 -e /bin/sh`) ve `ttyGS0` üzerinde kabuk.
- fbcon'a 10 sn'de bir "canlıyım + uptime + IP" satırı yazar (webcam'den takip).
- `nicole.sinyal=reboot` cmdline'da varsa init hemen `sysrq b` ile yeniden başlatır → ekransız/USB'siz durumda "çekirdek userspace'e ulaştı mı?" sorusunun ikili cevabı.
- `root=` verilmişse ve `nicole.kabuk` yoksa SD'deki kök dosya sistemine `switch_root` dener.

**macOS notları:** macOS CDC‑NCM/ECM ve CDC‑ACM'i sürücüsüz tanır; **RNDIS'i tanımaz** (HoRNDIS Apple Silicon'da kullanılamıyor) → NCM birincil, ECM yedek. macOS'ta `telnet` yok: `nc 172.16.42.1 23` veya `screen /dev/cu.usbmodem* 115200`. USB cihazları Lima VM'ine geçmez; `fastboot`, `nc`, `ssh` **Mac'te** çalışır (`brew install --cask android-platform-tools`).

### 5.3 postmarketOS initramfs ile (M1'in SSH kısmı)

`postmarketos-initramfs` (`init_functions.sh`, <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/main/postmarketos-initramfs/init_functions.sh>):
- USB ağını configfs ile kurar: `deviceinfo_usb_network_function` (varsayılan `ncm.usb0`, yedek `rndis.usb0`), VID:PID `0x18D1:0xD001`, seri "postmarketOS".
- `unudhcpd` cihazı `172.16.42.1`, Mac'i `172.16.42.2` yapar.
- `pmos.debug-shell` cmdline'da varsa (veya açılışta **Ses Kısma** basılıysa, `check_keys`) hata ayıklama kabuğu: `telnetd -b 172.16.42.1:23`, ACM üzerinde getty (`/dev/ttyGS0`), `pmos_continue_boot` ile açılışa devam, `pmos_logdump` ile log.
- Kök: `pmOS_boot` / `pmOS_root` etiketli bölümleri tüm blok aygıtlarında arar (microSD dahil); `pmos.root=`/`pmos.boot=` ile zorlanabilir.
- Rootfs açıldıktan sonra SSH: `ssh <kullanıcı>@172.16.42.1` (kullanıcı/parola `pmbootstrap init/install` sırasında belirlenir). Laboratuvar betiği root SSH bekliyor; pmOS'ta `doas` ile yetki yükseltilir.
- Cihaz paketi taslağı: `pmaports/device-razer-nicole/` (deviceinfo: header v1 + append_dtb, §7).

## 6. microSD üzerinde rootfs

**Hazır (2026-10-07):** `scripts/build/pmos-hazirla.sh` VM'de postmarketOS (console arayüzü) imajını cihazsız üretir:
- `out/pmos/razer-nicole.img.zst`: microSD'ye yazılacak imaj (`pmOS_boot` + `pmOS_root` bölümleri).
- `out/pmos/pmos-boot.img`: çekirdek + pmOS initramfs. `fastboot boot` ile RAM'e yüklenir, kökü SD'de bulur.
- Giriş: kullanıcı `user`. SSH anahtarı Mac'te `~/.ssh/razer_nicole`. Yedek parola `out/pmos/parola.txt` (yalnız bu imaja ait, rastgele üretildi). Yetki: `doas`.
- İçinde: openssh, usbutils, pciutils, i2c-tools, dtc, evtest, htop, tmux, lm-sensors.

**Karta yazma (Mac):** `scripts/lab/sd-yaz.sh`
1. Kartı tak, `scripts/lab/sd-yaz.sh` (parametresiz) harici diskleri listeler, hiçbir şey yazmaz.
2. `scripts/lab/sd-yaz.sh diskN`: kontroller geçerse disk adını tekrar yazdırıp onay ister, sonra yazar (sudo).
3. Korumalar: yalnız harici ve fiziksel disk; 160 GB'tan büyük disk, APFS kapsayıcısı olan disk veya `RAZER_KORUNAN_BIRIM` ile verilen birimi taşıyan disk reddedilir. Yazarın proje SSD'si (250 GB) bu üç korumanın **her biri tarafından ayrı ayrı** reddediliyor (test edildi). Not: macOS 26'da `diskutil info` "Internal" alanı vermiyor; yalnız boyuta güvenmek SSD'yi korumazdı.

**Açılış (M1, mini initramfs başarılı olduktan sonra):**
```bash
scripts/lab/deneme.sh out/pmos/pmos-boot.img pmos-sd
ssh -i ~/.ssh/razer_nicole user@172.16.42.1
```
Kart bulunamazsa pmOS initramfs hata ayıklama kabuğuna düşer (telnet 172.16.42.1:23).

Alternatif (kullanılmıyor): Lima `blockDevices` ile kart okuyucuyu VM'e bağlayıp `pmbootstrap install --sdcard=/dev/vdX`.

## 7. pmOS deviceinfo için çıkarımlar

| Alan | Değer | Kesinlik |
|---|---|---|
| `deviceinfo_header_version` | `1` (Deneme 2 kazanırsa `2`) | Deneme 1/2 sonucuna bağlı |
| `deviceinfo_append_dtb` | `true` | Yüksek |
| `deviceinfo_dtb` | `qcom/sm8350-razer-nicole` | Kesin |
| `deviceinfo_flash_pagesize` | `4096` | Kesin (BoardConfig) |
| `deviceinfo_flash_offset_base` | `0x00000000` | Kesin (BoardConfig) |
| Diğer ofsetler | kernel `0x8000`, ramdisk `0x1000000`, tags `0x100`, dtb `0x1f00000` | pmOS standardı; ABL büyük ölçüde yok sayar |
| `deviceinfo_usb_network_function` | `ncm.usb0` | macOS için en iyi; çalışmazsa `ecm.usb0` |
| `deviceinfo_flash_kernel_on_update` | `false` | Proje kuralı (flash yok) |
| `deviceinfo_rootfs_image_sector_size` | `512` (SD) | UFS'e kurulursa 4096 |

## 8. U-Boot ve lk2nd

- **lk2nd**: LK (Little Kernel) tabanlı eski Qualcomm bootloader'lar (msm8916/8953 vb.) içindir; SM8350'deki UEFI tabanlı ABL'de geçerli değil.
- **Mainline U-Boot (`qcom_defconfig` + `qcom-phone.config`)**: ABL'den Android boot imajı olarak (`u-boot-nodtb.bin.gz` + ekli DTB, `mkbootimg --header_version 2`) `fastboot boot` ile zincirlenir; DTB/bellek bilgisini ABL'den alır; sonra kartı/USB'yi kullanarak çekirdeği (extlinux) kendisi yükler. Belgeler: <https://github.com/u-boot/u-boot/blob/master/doc/board/qualcomm/board.rst>, <https://github.com/u-boot/u-boot/blob/master/doc/board/qualcomm/phones.rst>.
- **SM8350 durumu (Ekim 2026, U-Boot `master`):** `drivers/clk/qcom/` ve `drivers/pinctrl/qcom/` altında sdm845, sm8150, sm8250, sm8550, sm8650, sc7280, x1e80100… var, **sm8350 yok**. Yani U-Boot önce `clock-sm8350.c` + `pinctrl-sm8350.c` portu ister (sm8250 örneği üzerinden, birkaç yüz satır).
- U-Boot **DTBO sorununu çözmez** (belgesi de `fastboot erase dtbo` diyor) ama: kimlik/DTB numaralarını ABL'den bağımsız kılar, çekirdeği SD'den okuyarak deneme hızını artırır, `fastboot oem log` ile log verir. M1 sonrası değerlendirilecek iyileştirme; ilk açılış için gerekli değil. Kalıcı kurulumu Seviye 3.

## 9. Yalnız canlı cihazın cevaplayabileceği sorular

1. Bu ABL `fastboot boot`'a izin veriyor mu (Deneme 0)?
2. v1/v2 boot.img kabul ediliyor mu, yoksa v3 + vendor_boot mu şart?
3. Kimliksiz DTB'yi seçiyor mu; dtbo_a'daki Razer overlay'ini uygulamaya çalışıp başarısız mı oluyor (Deneme 1 ekran mesajı)?
4. SoC revizyonu (`0x20001` mi?) ve `/proc/device-tree/qcom,board-id` gerçek değeri.
5. Splash çerçeve tamponunun biçimi (a8r8g8b8/x8r8g8b8/RGB888), stride ve `fbcon=rotate` değeri.
6. Zorla yeniden başlatma ve fastboot tuş kombinasyonları ve süreleri.
7. ABL'nin eklediği cmdline argümanları (`/proc/cmdline`) — özellikle `root=` eklenip eklenmediği.
8. Ramoops için güvenli bir bellek bölgesi (`/proc/iomem`) — sıcak yeniden başlatmada RAM korunuyorsa çöküş logunu ikinci mainline açılışında okumak için.

## Kaynaklar

- Sony Xperia 1 III upstream DT commit'i (header v1, appended DTB, emptydtbo, msm-id uyarısı): <https://lkml.iu.edu/hypermail/linux/kernel/2111.1/06489.html>
- SM8550 DTBO tartışması (qcom_tzlog/arch_timer etiketleri, pmOS `fastboot erase dtbo` pratiği): <https://lkml.iu.edu/2602.3/10118.html>, <https://lkml.iu.edu/hypermail/linux/kernel/2602.1/00445.html>
- pmOS deviceinfo örnekleri: `sources/pmaports/device/testing/device-sony-pdx215/deviceinfo`; <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/testing/device-fairphone-fp5/deviceinfo>, <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/testing/device-nothing-spacewar/deviceinfo>
- pmOS initramfs: <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/main/postmarketos-initramfs/init_functions.sh>
- U-Boot Qualcomm belgeleri: <https://github.com/u-boot/u-boot/tree/master/doc/board/qualcomm>
- Yerel: `sources/lineage-device/BoardConfig.mk`, `sources/razer-kernel/arch/arm64/boot/dts/vendor/qcom/{Makefile,lahainap*.dts*}`, `sources/razer-kernel/drivers/soc/qcom/socinfo.c:773–780`, `sources/linux-mainline/arch/arm64/boot/dts/qcom/{sm8350.dtsi,sm8350-sony-xperia-sagami.dtsi}`.
