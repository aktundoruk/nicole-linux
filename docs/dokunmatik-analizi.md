# Dokunmatik analizi — FocalTech FT3658S (SPI), Razer Edge Wi‑Fi (`nicole`)

> Durum: cihaz bağlanmadan önce yapılan masa başı analiz. Kaynak: Razer/LineageOS
> 5.4 çekirdeğindeki `drivers/input/touchscreen/focaltech_touch_spi/` (FocalTech
> "V3.4 20211214"), `lahainap-nicole.dtsi` ve LineageOS `proprietary-*.txt`.
> `TODO(device)` ve "cihazda doğrulanmalı" işaretli her şey çıkarımdır.

## 1. Kısa sonuç

- **Denetleyicinin kendi flash belleği var. Host-download (HDL) gerekmiyor.**
  `FTS_CHIP_TYPE = 0x3658A48C` değerinin IDC biti (bit 11) 0
  (`FTS_CHIP_IDC = 0`, yani "in-cell / flash'sız" değil). Yükseltme modülü
  (`focaltech_upgrade_ft3658s.c`) **flash'ı siliyor ve yazıyor**:
  `0x09 0x0B` yükseltme modu, `0x61` silme, `0xBF` yazma, ECC doğrulama.
  PRAM yükleme (`pramboot_supported = false`) yok. Sürücü açılışta yalnızca
  **sürüm farklıysa** flash'ı güncelliyor. Bu nedenle Android bir kez açıldıktan
  sonra flash'ta geçerli bir firmware bulunur ve Linux sürücüsünün firmware
  yüklemesi gerekmez.
- Android'in kullandığı dosya:
  `request_firmware("AX6175A_Visionox_FT3658S.bin")`. Ad,
  `FTS_FW_NAME_PREX_WITH_REQUEST` + boş modül adı + `.bin` ile oluşuyor.
  Cihazdaki yeri `vendor/firmware/AX6175A_Visionox_FT3658S.bin`.
  `proprietary-firmware.txt` (satır 982) ve `proprietary-files.txt` ile
  eşleşiyor. Yanında üretim testi için `AX6175A_Visionox_FT3658S_20220301.ini`
  var (`FTS_TEST_EN = 0`, kullanılmıyor). "AX6175A" büyük olasılıkla
  Visionox'un modül/proje kodu.
- Mainline'da bu SPI protokolünü konuşan bir sürücü **yok**. `edt-ft5x06`
  yalnızca I2C. Rapor biçimi aynı ailede, ama SPI çerçevesi farklı.
  2024–2026 arasında FT3658/FT8xxx için SPI yaması bulunamadı (§11).
- Taslak sürücü: `drivers/touchscreen/focaltech_ft3658s_spi.c` (611 satır,
  GPL‑2.0, `checkpatch --strict` temiz, sahte başlıklarla sözdizimi denetimi
  yapıldı, gerçek ağaçta derlenmedi). Yanında `Kconfig.fragment` ve
  `focaltech,ft3658s.yaml` var. Firmware indirmesi **yok**, çünkü gerekmiyor.

## 2. Donanım bağlantısı (downstream DT)

`lahainap-nicole.dtsi`, `&qupv3_se12_spi { focaltech@0 { … } }`:

| Özellik | Değer | Mainline karşılığı |
|---|---|---|
| Veri yolu | QUP SE12 SPI = mainline `spi12` (`spi@a90000`, WRAP1 S4, GPI DMA1 kanal 4) | `&spi12` |
| SPI pinleri | GPIO52–55, fonksiyon `qup12`, 6 mA, bias yok | yeni pinctrl gerekir (sm8350.dtsi'de spi12 için yok) |
| CS | 0 (`reg = <0>`) | |
| Saat | `spi-max-frequency = <6000000>` | aynı |
| SPI modu | sürücü `SPI_MODE_0`, 8 bit zorluyor | sürücü aynısını yapıyor |
| IRQ | GPIO23, DT'de `0x2008` (LEVEL_LOW + QC bayrağı), **sürücü bunu yok sayıp `IRQF_TRIGGER_FALLING \| IRQF_ONESHOT` kullanıyor** | `IRQ_TYPE_EDGE_FALLING` öneriliyor |
| Reset | GPIO22 (`focaltech,reset-gpio`, bayrak 0). 0 = reset, yani aktif düşük | `reset-gpios = <&tlmm 22 GPIO_ACTIVE_LOW>` |
| AVDD | `vdd-supply = <&L3C>` (pm8350c ldo3, **3.008 V**). Sürücü 2.8–3.3 V istiyor | `vdd-supply` |
| IOVDD | `vcc_i2c-supply = <&L8C>` (pm8350c ldo8, **1.8 V**) | `iovdd-supply` |
| Koordinatlar | `focaltech,display-coords = <0 0 1080 2400>` | `touchscreen-size-x/y = 1080/2400` |
| Nokta sayısı | `focaltech,max-touch-number = <10>` | sürücüde sabit 10 |
| Pinctrl | etkin: GPIO22/23 8 mA pull‑up. Askı: ikisi de 2 mA pull‑down. Bırakma: 2 mA bias yok | |
| `panel = <&dsi_vtdr6130_amoled_cmd>` | panel bildirici bağı (§9) | |

Modül `focaltech_fts.ko` (`CONFIG_TOUCHSCREEN_FTS_SPI=m`, `nicole.config`).
Hem `modules.load` hem `modules.load.recovery` içinde ilk sırada.

## 3. SPI çerçeveleme (`focaltech_spi.c`)

Tek CS etkinleştirmesi içinde tam çift yönlü (full duplex) bir `spi_transfer`
gönderiliyor. Çerçeveler arasında CS gecikmesi yok (80 µs `udelay` yorum
satırına alınmış).

**Yazma** (`fts_write(buf, n)`, `buf[0]` = adres/komut,
`datalen = n − 1`):

```
TX: addr | 0x00 | len_hi | len_lo | [00 00 00 | data[0..len-1]]
```

`len = 0` ise yalnızca 4 baytlık başlık gönderiliyor, boş bayt da veri de
yok.

**Okuma** (`fts_read(cmd, …, n)`: yalnızca `cmd[0]` kullanılıyor, `cmdlen`
yok sayılıyor):

```
TX: addr | 0xA0 | len_hi | len_lo | 00 00 00 | 00 × (n + 2)
RX: xx   | xx   | xx     | STATUS | xx xx xx | data[0..n-1] | crc_lo | crc_hi
```

- `0xA0` = okuma (bit 7) + CRC etkin (bit 5). Yazma kodu `0x00`.
- **Durum baytı** RX[3]. `(RX[3] & 0xA0) != 0` ise denetleyici işlemi
  reddetmiş demektir ve işlem tekrar deneniyor.
- **CRC**: CRC‑16, ters (reflected) polinom 0x8408, başlangıç 0xFFFF, son XOR
  yok (CRC‑16/MCRF4XX). Kapsam yalnızca veri baytları. Sonuç **küçük uçlu
  (little endian)** gönderiliyor. Linux'taki `crc_ccitt(0xffff, buf, len)`
  ile birebir aynı; rastgele verilerle Python'da doğrulandı.
- 3 deneme. CRC hatasında da yeniden deneniyor.
- Tampon 4096 bayt, gerekirse daha büyük ayrılıyor. Dokunma okuması 62 + 9 =
  71 bayt.
- `fts_spi_transfer_direct()` ham aktarım yapıyor ve yalnızca APK/hata
  ayıklama kanalı için var.

## 4. Güç açma, reset ve zamanlama

Açılış (probe) sırası:

1. `fts_gpio_configure`: IRQ GPIO giriş, reset GPIO **yüksek** (bırakılmış).
2. `fts_power_source_init` → `fts_power_source_ctrl(ENABLE)`: **reset düşük →
   1 ms → `vdd` (3.0 V) açık → `vcc_i2c` (1.8 V) açık.** Sıra AVDD önce,
   IOVDD sonra. Arada açıkça tanımlı bir gecikme yok.
3. `fts_reset_proc(200)` (çip IDC olmadığı için): reset düşük → 1 ms →
   yüksek → **200 ms**.
4. `fts_get_ic_information`: `0xA3` ve `0x9F` 200 ms aralıkla, en çok 1 s
   boyunca yoklanıyor.

Kapatma: reset düşük → 1 ms → `vdd` kapalı → `vcc_i2c` kapalı.
Taslak sürücü bu sırayı izliyor. Yalnızca beslemeler ile reset bırakma
arasına 2 ms ekleniyor (`TODO(device)`).

## 5. Çip kimliği

`FTS_CHIP_TYPE_MAPPING {{0x8C, 0x36, 0x58, 0x00, 0x00, 0x00, 0x00, 0x36, 0xA8}}`:

| Alan | Değer | Nasıl okunur |
|---|---|---|
| type | 0x8C | – |
| Uygulama çip kimliği | **`0xA3` = 0x36**, **`0x9F` = 0x58** | normal okuma |
| ROM/PRAM boot kimliği | 0x0000 (yok) | – |
| Bootloader kimliği | **0x36 0xA8** | `0x55` gönder (upgrade spec 1.0'da yalnızca başlık; çekirdekteki eski yol `55 AA` gönderiyor) → 12 ms → `0x90`'dan 2 bayt oku |

Diğer yazmaçlar: `0xA6` FW sürümü, `0xA8` üretici kimliği, `0xE3` modül
kimliği, `0xA5` güç modu (`0x03` = uyku), `0x00` çalışma modu (`0x40` =
fabrika), `0x91` akış sayacı (ESD), `0x8F` kesme sayacı, `0x8B` şarj modu,
`0xC0` eldiven, `0xC1` kapak, `0xC8` kulaklık, **`0x8C` kenar modu (Razer:
1 = USB portları solda, 2 = sağda)**, `0xD0` jest, `0xFC` yükseltme
(`AA` ardından `55` = bootloader'a geç), `0x07` boot içinde reset.

## 6. Firmware: flash mı, host-download mı? (kritik)

| Kanıt | Sonuç |
|---|---|
| `FTS_CHIP_IDC = (0x3658A48C >> 11) & 1 = 0` | in-cell/IDC değil |
| `FTS_HID_SUPPORTTED = bit 10 = 1` | HID‑I2C dönüştürme yalnızca I2C'de, SPI'da atlanıyor |
| `upgrade_func_ft5652` (FT3658S): `pramboot_supported = false`, `appoff = 0`, `fwveroff = 0x010E`, `fwcfgoff = 0x1F80` | flash'a yazılan bir uygulama |
| `fts_ft5652_upgrade()`: `0x7A` (uzunluk), `0x09 0x0B` (yükseltme modu), silme (2 KB sayfa başına 80 ms), `fts_flash_write_buf`, ECC karşılaştırma, `0x07` reset | **flash programlama** |
| `fts_fwupg_need_upgrade()`: çipteki `0xA6` ile dosyanın `[0x010E]` baytı farklıysa veya çip geçersizse yükseltiyor | her açılışta indirme yok |
| `fts_reset_proc` ve `resume` sonrası `fts_wait_tp_to_valid` yalnızca kimlik yokluyor | RAM'e yükleme yok |

**Sonuç:** FT3658S kendi flash'ından açılıyor. Host'un her açılışta firmware
indirmesi **gerekmiyor**. Bu yüzden taslak sürücü `request_firmware()`
kullanmıyor. Flash bozulursa çip bootloader'da kalır (kimlik 0x36A8). Taslak
sürücü bu durumu tanıyıp açık bir hata yazıyor. O durumda Android'e dönüp
sürücünün yeniden yazmasına izin vermek en güvenli yol. Linux'a flash
yazıcı eklemek bu aşamada kapsam dışı. Eklenirse önerilen ad
`focaltech/ft3658s.bin` (veya açıklık için
`focaltech/AX6175A_Visionox_FT3658S.bin`). Dosya sözleşme gereği Mac ve
cihaz dışına çıkmaz.

## 7. Dokunma raporu

IRQ'da `0x01` adresinden **62 bayt** okunuyor
(`FTS_TOUCH_DATA_LEN = 10 × 6 + 2`). Arabellek önceden 0xFF ile
dolduruluyor.

| Bayt | İçerik |
|---|---|
| 0 | (yazmaç 0x01, jest/durum; kullanılmıyor) |
| 1 | bit 7..4 = olay tipi, bit 3..0 = parmak/olay sayısı |
| 2 + 6·i + 0 | bit 7..6 = olay bayrağı (0 = basma, 1 = kaldırma, 2 = temas), bit 3..0 = X[11:8] |
| 2 + 6·i + 1 | X[7:0] |
| 2 + 6·i + 2 | bit 7..4 = **ID**, bit 3..0 = Y[11:8] |
| 2 + 6·i + 3 | Y[7:0] |
| 2 + 6·i + 4 | basınç (0 ise sürücü 0x3F yazıyor) |
| 2 + 6·i + 5 | alan / touch major (0 ise 0x09) |

Olay tipleri: `0x0` varsayılan (tüm etkin noktalar sırayla; ID ≥ 0x0A olunca
durur), `0x2` olay sayısı (yalnızca `count` kadar giriş), `0x8` ek bilgi
(noktalar 4. bayttan başlıyor, `touch_analysis` kapalı), `0xB` kalem
(`FTS_PEN_EN = 0`), `0x80` jest, `0x81` FW init. Bayt 1..4'ün hepsi 0xFF ise
"firmware yeniden başladı" demektir: parmaklar bırakılıyor ve modlar geri
yükleniyor.

Raporlama MT protokol B ile yapılıyor (`input_mt_slot`, `ABS_MT_POSITION_X/Y`,
`ABS_MT_TOUCH_MAJOR`, `ABS_MT_PRESSURE` 0..255, `BTN_TOUCH`). Önceki
karede basılı olup bu karede hiç bahsedilmeyen yuvalar bırakılıyor. Mainline'daki
karşılığı `INPUT_MT_DROP_UNUSED` + `input_mt_sync_frame()`.

## 8. Koordinat eşlemesi

Razer'ın yamalı sürücüsü:

```c
ABS_MT_POSITION_X = FTS_Y_MAX_DISPLAY_DEFAULT(1080) - 1 - x;   /* 1079 - x */
ABS_MT_POSITION_Y = FTS_X_MAX_DISPLAY_DEFAULT(2400) - 1 - y;   /* 2399 - y */
```

Eksen aralıkları DT'den 0..1080 ve 0..2400 olarak bildiriliyor (bir eksik
hatası var). Yani **iki eksen de ters, takas yok**. Bu, panelin
`qcom,mdss-dsi-panel-orientation = "180"` ayarıyla uyumlu. Mainline'daki
karşılığı:

```dts
touchscreen-size-x = <1080>;
touchscreen-size-y = <2400>;
touchscreen-inverted-x;
touchscreen-inverted-y;
```

`touchscreen_report_pos()` `max − x` hesapladığı için sonuç birebir aynı
(1079 − x, 2399 − y). Panel `rotation = <180>` ile işaretlendiğinde
kompozitör görüntüyü çeviriyor. Dokunma koordinatlarının da Android'deki gibi
"mantıksal" yönde olması gerekiyor, bu yüzden aynı ters çevirme doğru. Cihazda
köşe testiyle doğrulanmalı (§13.3).

## 9. Askıya alma, sürdürme ve panel bağı

- `CONFIG_DRM` + `CONFIG_DRM_PANEL` ile sürücü `panel = <&dsi_vtdr6130_amoled_cmd>`
  özelliğini okuyor, `of_drm_find_panel` ile panelin hazır olmasını bekliyor
  (`-EPROBE_DEFER`) ve **Qualcomm'a özel `drm_panel_notifier_register()`**
  çağırıyor. Bu API mainline'da yok.
- **Askıya alma ve sürdürme panel olaylarına bağlı:**
  `DRM_PANEL_EARLY_EVENT_BLANK + POWERDOWN` → `fts_ts_suspend`.
  `DRM_PANEL_EVENT_BLANK + UNBLANK` → `resume_work`. Sistem PM'i
  (`fts_pm_suspend/resume`) yalnızca bir tamamlama (completion) bayrağı
  tutuyor; amaç PM sırasında gelen IRQ'da veri yolunun uyanmasını en çok
  700 ms beklemek.
- `fts_ts_suspend` (jest kapalıyken): ESD durdur → IRQ kapat →
  `0xA5 = 0x03` (uyku) → pinctrl askı → reset düşük → `vdd` ve `vcc_i2c`
  kapalı → parmakları bırak.
- `fts_ts_resume`: pinctrl etkin → güç aç → `fts_reset_proc(200)` → kimlik
  bekle → modları geri yükle (eldiven/kapak/şarj/kulaklık/kenar) → ESD → IRQ
  aç.
- **Ekrana bağımlılık:** Dokunmatik IC'nin beslemeleri (L3C/L8C) ve reset
  hattı (GPIO22) panelden (L12C/L13C/GPIO13, reset GPIO24) bağımsız. Kod
  açısından dokunmatik, panel kapalıyken de çalışabilmeli. Bağ yalnızca güç
  politikası (ekran kapanınca dokunmatik de kapanıyor). Ancak AMOLED on‑cell
  sensörlerin tarama zamanlamasını ekranın Vsync'ine kilitlemesi yaygın
  (**cihazda doğrulanmalı**: panel kapalıyken IRQ ve doğru veri geliyor mu?).
- Taslak sürücü sistem PM'ini (`DEFINE_SIMPLE_DEV_PM_OPS`) kullanıyor.
  Mainline'da ekran olaylarına bağlanmanın doğru yolu `drm_panel_follower`
  (`drm_panel_add_follower()`; i2c-hid böyle yapıyor). Bu, sonraki adım
  olarak bırakıldı.

## 10. ESD, jest ve diğerleri

- **ESD** (`FTS_ESDCHECK_EN = 1`): her 1000 ms'de bir çalışıyor. Son 200 ms
  içinde kesme gelmişse atlıyor. Askıdaysa, proc meşgulse veya fabrika
  modundaysa (`0x00 & 0x70 == 0x40`) atlıyor. `0xA3` üç denemede doğru
  okunamazsa ya da `0x91` akış sayacı 5 kez üst üste aynı kalırsa donanım
  reset'i atıyor (`fts_reset_proc(200)`) ve durumu geri yüklüyor. Taslakta
  yok (`TODO(device)`); kilitlenme görülürse eklenecek.
- **Jest/uyandırma:** `FTS_GESTURE_EN = 0`. Varsayılan kapalı, sysfs ile
  açılabiliyor. Razer'da kullanılmıyor.
- **Kalem:** `FTS_PEN_EN = 0`.
- **Nokta raporu denetimi (PRC):** `FTS_POINT_REPORT_CHECK_EN = 0`.
- **Ek modlar:** sysfs üzerinden eldiven `0xC0`, kapak `0xC1`, şarj `0x8B`,
  kulaklık `0xC8`, kenar `0x8C` (1 veya 2, cihazın yönüne göre kenar
  reddi). Android kullanıcı alanı bunları yazıyor olabilir. Varsayılanları
  kapalı.
- Hata ayıklama arayüzleri (Android, salt okuma için yararlı):
  `/proc/ftxxxx-debug`, `/sys/bus/spi/devices/spiN.0/fts_fw_version`,
  `fts_driver_info`, `fts_irq`, `fts_touch_point`, `fts_dump_reg` …

## 11. Mainline taraması

- `drivers/input/touchscreen/edt-ft5x06.c`: uyumlu dizgeler
  `edt,edt-ft5206/5306/5406/5506`, `evervision,ev-ft5726`,
  `focaltech,ft3518`, `focaltech,ft5426`, `focaltech,ft5452`,
  `focaltech,ft6236`, `focaltech,ft8201`, `focaltech,ft8716`,
  `focaltech,ft8719`. **Yalnızca I2C** (`regmap_init_i2c`, `i2c_driver`),
  dosyada hiç "spi" geçmiyor. Rapor biçimi (M12: 0x00'dan başlık + 6
  baytlık noktalar) aynı aileden. İleride bir seçenek, FocalTech SPI
  çerçevesini (başlık + boş baytlar + CRC) bir `regmap_bus` olarak yazıp
  `edt-ft5x06`'ya SPI probu eklemek olabilir. Upstream açısından tartışılmalı.
- `Documentation/devicetree/bindings/input/focaltech,ft8112.yaml`: i2c-hid
  tabanlı FT8112/FT3D81. Farklı protokol.
- Ağaçta "focaltech" adlı bir SPI sürücüsü yok.
- Web taraması (Ekim 2026):
  - "Add support for Focaltech FTS Touchscreen" (Joel Selvaraj, v1–v3,
    Mart–Nisan 2023; daha önce Caleb Connolly, Ocak 2022): I2C, fts5452 ve
    fts8719 için. Birleştirilmedi; bu çiplerin desteği sonradan
    `edt-ft5x06`'ya eklendi.
    [lkml v3](https://lkml.iu.edu/hypermail/linux/kernel/2304.1/07281.html),
    [patchwork 2022](https://patchwork.kernel.org/project/linux-input/patch/20220123173650.290349-2-caleb@connolly.tech/)
  - "Input: edt-ft5x06 - add support for FocalTech FT5452 and FT8719"
    (Mayıs 2024, I2C).
    [lkml](https://lkml.iu.edu/hypermail/linux/kernel/2405.2/04444.html)
  - "Input: edt-ft5x06 - add support for FocalTech FT8716" (Mart 2025, I2C).
    [lkml](https://lkml.rescloud.iu.edu/2503.1/08008.html)
  - "Support FT3518 touchscreen in xiaomi-laurel" v3/v4 (Ocak 2026, I2C,
    `edt-ft5x06`).
    [arşiv](https://ratatoskr.run/linux-arm-msm/2026/01/3378741/t)
  - "Input: ft5x06: Add support for FocalTech FT3519" (Bhushan Shah, Mart
    2026, I2C; v2/v3'te yalnızca binding'de FT3518'e geri dönüşlü uyumlu
    dizge).
    [arşiv](https://ratatoskr.run/linux-input/2026/03/3456953/t),
    [lkml v2](https://lkml.iu.edu/hypermail/linux/kernel/2603.1/13332.html)
  - **FT3658 / FT8xxx için SPI desteği ekleyen, 2024–2026 arasında gönderilmiş
    bir yama bulunamadı.**

## 12. Taslak sürücü: `drivers/touchscreen/focaltech_ft3658s_spi.c`

| Konu | Uygulama |
|---|---|
| Lisans | `GPL-2.0-only` |
| Eşleme | OF `"focaltech,ft3658s"`, SPI id `"ft3658s"` |
| SPI | `SPI_MODE_0`, 8 bit, `spi_setup`. `spi_sync_transfer` ile tek, tam çift yönlü aktarım. Tamponlar ayrı `devm_kzalloc` (DMA güvenli), `mutex` ile korunuyor |
| Okuma | `0xA0`, 3 boş bayt, `crc_ccitt(0xffff, …)` ile CRC denetimi, durum baytı denetimi, 3 deneme |
| Yazma | `0x00`, `len = 0` için yalnızca başlık |
| Güç | `devm_regulator_bulk_get` (`vdd`, `iovdd`), sırayla açma, reset aktif düşük (`devm_gpiod_get(..., GPIOD_OUT_HIGH)` = reset'te başla), 200 ms bekleme, `devm_add_action_or_reset` ile kapatma |
| Kimlik | `0xA3 == 0x36` ve `0x9F == 0x58`, 200 ms aralıkla 1 s boyunca. Başarısızsa bootloader kimliği okunup (`0x55` → 12 ms → `0x90` = `0x36A8`) "flash firmware'i yok veya bozuk" ile "SPI yanıt vermiyor" ayırt ediliyor. FW sürümü (`0xA6`) ve üretici kimliği (`0xA8`) `dev_info` ile yazılıyor |
| Giriş | `devm_input_allocate_device`, eksenler 0..4095, `touchscreen_parse_properties`, `input_mt_init_slots(10, DIRECT \| DROP_UNUSED)`, `touchscreen_report_pos`, `ABS_MT_TOUCH_MAJOR` ve `ABS_MT_PRESSURE` |
| IRQ | `devm_request_threaded_irq(…, IRQF_ONESHOT)`. Tetikleme tipi DT'den geliyor (`IRQ_TYPE_EDGE_FALLING` önerildi) |
| PM | `DEFINE_SIMPLE_DEV_PM_OPS`: askıda IRQ kapat → `0xA5 = 0x03` → güç kes. Sürdürmede güç aç → kimlik bekle → IRQ aç |
| Firmware | yok (§6) |
| TODO(device) | güç-reset gecikmeleri, IRQ tetikleme tipi, ESD, FW yeniden başlayınca modların geri yüklenmesi, panel follower |

Kullanılan her çekirdek fonksiyonunun imzası `sources/linux-mainline/include`
altında tek tek denetlendi: `crc_ccitt`, `touchscreen_parse_properties`,
`touchscreen_report_pos`, `input_mt_init_slots`, `input_mt_sync_frame`,
`devm_mutex_init`, `spi_sync_transfer`, `devm_regulator_bulk_get`,
`devm_request_threaded_irq`, `DEFINE_SIMPLE_DEV_PM_OPS`, `pm_sleep_ptr`.
Kconfig `select CRC_CCITT` içeriyor.

Kurulum: `Kconfig.fragment` dosyasındaki girdi
`drivers/input/touchscreen/Kconfig`'e, şu satır `Makefile`'a eklenir:
`obj-$(CONFIG_TOUCHSCREEN_FOCALTECH_FT3658S_SPI) += focaltech_ft3658s_spi.o`.

## 13. Kart DTS parçası

```dts
&qupv3_id_1 {
	status = "okay";
};

&gpi_dma1 {
	status = "okay";
};

&spi12 {
	pinctrl-0 = <&qup_spi12_default>;
	pinctrl-names = "default";
	status = "okay";

	touchscreen@0 {
		compatible = "focaltech,ft3658s";
		reg = <0>;
		spi-max-frequency = <6000000>;

		interrupts-extended = <&tlmm 23 IRQ_TYPE_EDGE_FALLING>;
		reset-gpios = <&tlmm 22 GPIO_ACTIVE_LOW>;

		vdd-supply = <&vreg_l3c_3p0>;
		iovdd-supply = <&vreg_l8c_1p8>;

		touchscreen-size-x = <1080>;
		touchscreen-size-y = <2400>;
		touchscreen-inverted-x;
		touchscreen-inverted-y;

		pinctrl-0 = <&ts_int_default>, <&ts_reset_default>;
		pinctrl-names = "default";
	};
};

&tlmm {
	qup_spi12_default: qup-spi12-default-state {
		pins = "gpio52", "gpio53", "gpio54", "gpio55";
		function = "qup12";
		drive-strength = <6>;
		bias-disable;
	};

	ts_int_default: ts-int-default-state {
		pins = "gpio23";
		function = "gpio";
		drive-strength = <8>;
		bias-pull-up;
	};

	ts_reset_default: ts-reset-default-state {
		pins = "gpio22";
		function = "gpio";
		drive-strength = <8>;
		bias-pull-up;
	};
};

/* &apps_rsc altındaki pm8350c-rpmh-regulators düğümüne */
	vreg_l3c_3p0: ldo3 {
		regulator-name = "vreg_l3c_3p0";
		regulator-min-microvolt = <3008000>;
		regulator-max-microvolt = <3008000>;
		regulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
	};

	vreg_l8c_1p8: ldo8 {
		regulator-name = "vreg_l8c_1p8";
		regulator-min-microvolt = <1800000>;
		regulator-max-microvolt = <1800000>;
		regulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
	};
```

Yapılandırma: `CONFIG_SPI_QCOM_GENI=y` (veya `m`), `CONFIG_QCOM_GPI_DMA=y`,
`CONFIG_TOUCHSCREEN_FOCALTECH_FT3658S_SPI=m`, `CONFIG_CRC_CCITT`
(otomatik seçilir). Hata ayıklama için `CONFIG_DYNAMIC_DEBUG=y` ve
`CONFIG_INPUT_EVDEV=y`.

## 14. Test planı (cihaz aşaması)

Hepsi Seviye 1 işlemi: kendi çekirdeğimizle açılmış sistemde modül
yükleme, sysfs ve dmesg okuma. Firmware'e veya flash'a yazma yok.

### 14.0 Android referansı (önce, salt okuma)

```sh
adb shell 'ls /sys/bus/spi/devices/'                   # spiN.0 bul
adb shell 'cat /sys/bus/spi/devices/spi*/fts_fw_version'  # FW sürümünü not et
adb shell 'cat /sys/bus/spi/devices/spi*/fts_driver_info'
adb shell 'grep -i fts /proc/interrupts'                # tetikleme tipi (Edge/Level) ve sayaç
adb shell 'dmesg | grep FTS_TS'                         # chip id, "fw version in tp:%x, host:%x"
```

Beklenen: chip id `0x3658`. FW sürümü tp ile host'ta aynı olmalı (yani flash
güncel).

### 14.1 Ekrana dokunmadan SPI iletişimi (chip ID)

1. `modprobe focaltech_ft3658s_spi` (veya yerleşik açılış). Ekrana
   **dokunulmaz**.
2. `dmesg | grep -i ft3658s` çıktısını yorumla:

   | Mesaj | Anlamı | Ne yapılır |
   |---|---|---|
   | `FT3658S, firmware 0xNN, vendor ID 0xMM` | SPI çalışıyor, CRC tutuyor, çip kimliği doğru | 14.2'ye geç. `0xNN` Android'deki değerle eşleşmeli |
   | `chip ID mismatch: 0x0000` + `no answer on SPI` / `failed to read boot ID` | hiç yanıt yok | `spi12` pinctrl (GPIO52–55 `qup12`), CS, `spi-max-frequency` (1 MHz ile dene), L3C/L8C açık mı (`/sys/kernel/debug/regulator/regulator_summary`), reset kutbu |
   | `chip ID mismatch: 0xffff` veya rastgele | MISO yüzüyor, mod veya saat yanlış | SPI modu 0, frekansı düşür |
   | `read … failed: -74` (EBADMSG, `dyndbg` ile görülür) | CRC hatası | frekansı düşür. Boş bayt sayısını (3) ve CRC'nin bayt sırasını kontrol et |
   | `controller is stuck in its bootloader` | SPI çalışıyor ama flash'ta geçerli FW yok | Android'i aç; vendor sürücü flash'ı yeniden yazar. Linux'tan yazma yok |

3. Ayrıntılı iz:
   `echo 'file focaltech_ft3658s_spi.c +p' > /sys/kernel/debug/dynamic_debug/control`
4. SPI sinyali için ek doğrulama (isteğe bağlı): `cat /sys/kernel/debug/gpio`
   ile GPIO22 (reset = 1 bırakılmış) ve GPIO23 (IRQ boştayken 1) seviyeleri.

### 14.2 IRQ doğrulaması

1. `grep -i ft3658s /proc/interrupts` → satır var, tetikleme tipi
   `Edge`, sayaç dokunmadan **sabit** (en çok birkaç sayım).
   - Sayaç hızla artıyorsa (kesme fırtınası): tetikleme tipi yanlış (seviye
     tetiklemesiyle hat düşük kalıyor) ya da okuma her seferinde hata veriyor
     ve hat temizlenmiyor. `dyndbg` açıp `failed to read touch data` aranır.
     `IRQ_TYPE_LEVEL_LOW` da denenebilir.
2. Ekrana **bir kez** dokunup kaldır → sayaç birkaç ila onlarca artmalı
   (temas sürdükçe sürekli rapor gelir; rapor hızı cihazda ölçülmeli).
3. Hiç artmıyorsa: GPIO23 pinctrl (pull‑up), `interrupts-extended` numarası,
   panel kapalıyken dokunmatik taraması duruyor mu (§9)? Panel açıkken tekrar
   denenmeli.

### 14.3 Olay doğrulaması (geliştirici)

```sh
evtest /dev/input/eventX          # "FocalTech FT3658S Touchscreen"
libinput debug-events --show-keycodes
```

- Eksen aralıkları `ABS_MT_POSITION_X 0..1079`, `Y 0..2399` olmalı.
- Ekranın **fiziksel olarak sol üst** köşesine (panel dikey, ön kamera
  yukarıdayken) dokun ve `X≈0, Y≈0` görüldüğünü kontrol et. Ters çıkarsa
  `touchscreen-inverted-x/y` kaldırılır veya değiştirilir. Eksenler takaslı
  çıkarsa `touchscreen-swapped-x-y` eklenir.
- 10 parmak: 10 ayrı `ABS_MT_TRACKING_ID` görülmeli, parmaklar kalkınca
  hepsi `-1` olmalı.
- Askıya alma: `echo mem > /sys/power/state` yalnızca platform askıya alma
  destekliyorsa denenir. Daha güvenli seçenek: `echo -n spiN.0 >
  /sys/bus/spi/drivers/focaltech-ft3658s/unbind` ve ardından `bind` →
  yeniden probe, `dmesg` temiz olmalı.

### 14.4 Son elle test (kullanıcı)

Grafik oturum (ör. Phosh, Weston veya Sway) açıkken:

1. Ekranın dört köşesine ve ortasına sırayla dokun. İmleç veya dokunma
   noktası parmağın tam altında görünmeli (yön ve ters çevirme doğru).
2. Bir çizim uygulamasında (ör. `weston-simple-touch` veya tarayıcıda bir
   çizim sayfası) çapraz çizgiler çiz: kesik, sıçrama veya gecikme olmamalı.
3. İki parmakla yakınlaştır/uzaklaştır ve kaydır (çoklu dokunma).
4. Kenarlara yakın dokunuşlar: özellikle cihaz yatay tutulurken
   kulpların/kontrolcünün değdiği kenarlarda hayalet dokunma olmamalı (Razer
   bunun için `0x8C` kenar modunu kullanıyor; gerekirse eklenir).
5. Ekranı kapatıp aç (veya askıya al ve sürdür): dokunmatik tekrar çalışmalı.
6. 10 dakika boyunca normal kullanım: `dmesg` içinde
   `failed to read touch data` olmamalı, dokunmatik donmamalı (ESD gereği
   olup olmadığını gösterir).

## 15. Riskler

1. **IRQ tetikleme tipi**: DT seviye diyor, sürücü düşen kenar kullanıyor.
   Yanlış seçim kesme fırtınasına veya kaçırılan dokunmalara yol açar
   (14.2).
2. **Panel bağımlılığı**: tarama ekranın Vsync'ine kilitliyse, panel
   sürücüsü çalışmadan dokunmatik IRQ üretmeyebilir. Önce panel
   getirilmeli ya da panel açıkken test edilmeli.
3. **Güç/reset zamanlaması**: vendor açıkça bir gecikme tanımlamıyor.
   Taslaktaki 2 ms ve 200 ms tahmin. Kimlik okunamazsa süreler
   uzatılmalı.
4. **Paylaşılan regülatörler**: L8C (1.8 V) başka tüketicilerle paylaşılıyorsa
   askıya almada kapanmaz; bu zararsız. L3C'nin 3.008 V'u
   `regulator-min/max` ile sabitlenmeli.
5. **GENI SPI + GPI DMA**: `spi12` GPI DMA kanallarıyla tanımlı. GPI
   sürücüsü veya firmware sorunu çıkarsa geni SPI FIFO moduna düşer; bu
   davranış dmesg'de doğrulanmalı.
6. **Flash bozulması**: yalnızca Android'in vendor sürücüsü flash'ı yazabilir.
   Linux tarafında yazma yolu yok, dolayısıyla risk de yok. Çip bootloader'da
   bulunursa Android'e dönülür.
7. **Kenar/şarj modları**: Android `0x8B`/`0x8C` yazıyor olabilir.
   Varsayılan (kapalı) durumda dokunmatik çalışmalı, ama şarj gürültüsünde
   hayalet dokunma görülebilir.
8. **ESD/kilitlenme**: vendor 1 s'de bir denetim yapıyor. Taslakta bu yok.
   Donma olursa eklenmeli.
