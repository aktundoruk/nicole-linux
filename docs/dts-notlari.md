# DTS Notları — `dts/sm8350-razer-nicole.dts` (taslak)

> Bu belge taslak mainline cihaz ağacının neyi açtığını, neyi ertelediğini, hangi varsayımlara dayandığını ve Faz 0’da canlı cihazdan neyin doğrulanması gerektiğini anlatır. Donanım ayrıntıları ve kaynak atıfları için: `docs/donanim-envanteri.md`.
> Tarih: 5 Ekim 2026 · Taban: Linux 7.3‑rc6 `sm8350.dtsi`, yapı `sm8350-hdk.dts` ve `sm8350-sony-xperia-sagami.dtsi`’den.

## 1. Derleme

```sh
dts/build-dtb.sh            # çıktı: dts/out/sm8350-razer-nicole.dtb
```

- Ön işlem: `clang -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -P` + `include`, `arch/arm64/boot/dts/qcom`, `scripts/dtc/include-prefixes`. macOS’taki `/usr/bin/cpp` sarmalayıcısı `-x assembler-with-cpp` bayrağını bozduğu için betik Darwin’de `clang -E` kullanır (Linux’ta `cpp`). `CPP=… LINUX=… DTC=…` ile değiştirilebilir.
- `dtc -I dts -O dtb -@` (overlay için semboller açık).
- Durum: **hatasız ve uyarısız derleniyor** (DTB ≈ 126 KB). Kapatılan iki dtc kontrolü (`unique_unit_address`, `avoid_unnecessary_addr_size`) yalnız `sm8350.dtsi`’nin kendisinden gelir; çekirdeğin `Makefile.dtbs`’i de bunları susturur.
- `dtbs_check` (şema doğrulaması) çalıştırılmadı; bilinen şema ihlalleri aşağıda (Bölüm 5).

## 2. Faz 2’de (ilk açılış) açık olanlar

| Blok | Ayrıntı |
|---|---|
| Kimlik | `model = "Razer Edge Wi-Fi"`, `compatible = "razer,nicole", "qcom,sm8350"`, `chassis-type = "handset"`. msm-id/board-id **yok** (yorum satırında hazır). |
| Konsol | `serial0 = &uart2` (QUP SE3, GPIO18/19), `stdout-path = "serial0:115200n8"`; ekran için **cmdline’a `console=tty0` eklenmeli** (son verilen `console=` `/dev/console` olur). |
| simple-framebuffer | `/chosen/framebuffer@e1000000`: 1080×2400, stride 4320, `a8r8g8b8`. Saatler `GCC_DISP_HF/SF_AXI_CLK`, güç alanı `dispcc MDSS_GDSC`, beslemeler L12C, L13C, panel_avdd (GPIO13), L6B, L1B. Amaç: regülatör/genpd/rpmhpd temizliği ~30 sn sonra ekranı karartmasın. `simpledrm` güç alanını, beslemeleri ve saatleri destekler (kısmi klondan `drivers/gpu/drm/sysfb/simpledrm.c` okundu). |
| reserved-memory | `cont_splash_mem` 0xe1000000+0x2300000 no-map, `dfps_data_mem` 0xe3300000+0x100000 no-map; `&rmtfs_mem` kapalı. Geri kalan carveout’lar mainline ile birebir aynı. |
| Regülatörler | PM8350 (b), PM8350C (c), PMR735A (e) RPMh blokları; aralıklar Razer `lahaina-regulators.dtsi` ile aynı ya da daha dar (L9C 2.96 V’a sabit). PM8350B L1D tanımlanmadı. |
| Tuşlar | Güç = `pon_pwrkey`, Ses− = `pon_resin` (KEY_VOLUMEDOWN), Ses+ = `gpio-keys` → `pm8350_gpios 6`. |
| RTC | `pmk8350_rtc` açık. |
| microSD | `sdhc_2`: CD GPIO80 aktif yüksek, vmmc L9C, vqmmc L6C, `no-sdio`, `no-mmc`; cmd/data sürüş gücü Razer’daki gibi 10 mA. |
| USB | `usb_1` **yalnız peripheral + high-speed**, `phys = <&usb_1_hsphy>`; QMP PHY kapalı. Type‑C yön sorunu olmadan USB ağı (NCM/RNDIS) için. |
| Remoteproc | `adsp`, `cdsp`, `slpi` açık; `firmware-name = "qcom/sm8350/razer/nicole/{adsp,cdsp,slpi}.mbn"`. Dosya yoksa sessizce çevrimdışı kalırlar. `mpss` ve `ipa` kapalı. |
| ADC | `pmk8350_vadc` salt-okunur kanallar: xo, msm, quiet (deri), wide_rfc, rear_tof, smb_temp, usb_conn. docs/guvenlik-kurallari.md §3 sıcaklık kaydı için. |
| TLMM | `gpio-reserved-ranges = <56 4>` (Razer’ın kendi listesi), 203 girişlik `gpio-line-names`, strap pinlerine pull-up (`gpioget` ile SKU/rev okunabilir). |
| UFS | `ufs_mem_hc` ve `ufs_mem_phy` **kapalı** (sözleşme, Seviye 4). |

## 3. Ertelenenler (PHASE 3, `status = "disabled"`)

| Blok | Durum / açmak için gerekenler |
|---|---|
| `pmic-glink` | Bağlayıcı + HS → `usb_1_dwc3_hs`, SS → redriver → `usb_1_qmpphy_out`, SBU → FSA4480. Açmak için: ADSP firmware, pd-mapper, `qupv3_id_1` + `i2c13`, `usb_1_qmpphy`, `usb_1_dwc3`’te `dr_mode = "otg"` + `usb-role-switch`, `maximum-speed` silinir, `phys` iki PHY’ye geri alınır. |
| `i2c13` | PM8008j @0x0c (regülatörler l1–l7), FSA4480 @0x42, NB7VPQ904M @0x1c (varlığı belirsiz). |
| `i2c-fan` + MAX31760 | i2c-gpio GPIO8/9; `fancontroller` düğümünde önerilen bağlama uzantıları (`vdd/fan/vcca-supply`, `usb-charge-en-gpios`, `dpr-en-gpios`, `#cooling-cells`). Mainline sürücüsü bunları henüz okumuyor. |
| Termal fan haritaları | `cpu6/7-bottom`, `gpu-top/bottom`, `video` bölgelerine Razer tetikleri eklendi (etkisiz: `fancontroller` soğutma cihazı değil); yeni `quiet-thermal` (adc-tm) kapalı. |
| Ekran | `mdss`, `mdss_dsi0` (+ `panel@0` `visionox,vtdr6130`, reset GPIO24, TE GPIO82, `rotation = <180>`), `mdss_dsi0_phy` kapalı. **mdss açılınca simplefb devre dışı kalır** — panel sürücüsü hazır olmadan açılmamalı. |
| GPU | `gpu` kapalı, zap: `qcom/sm8350/razer/nicole/a660_zap.mbn`. |
| Dokunmatik | `spi12` + `touchscreen@0` (`focaltech,ft3658s` yer tutucu; `reset-gpios`, `interrupts-extended`, `vdd-supply`, `iovdd-supply`). `qupv3_id_1` + `gpi_dma1` açılmalı. |
| Wi‑Fi / BT | `wcn6855-pmu` (GPIO64/65/153/201), `pcie0` → `wifi@0` `pci17cb,1103`, `uart18` → `qcom,wcn6855-bt`. |
| Joystick VBUS | `pm8350_gpios 8` regulator-fixed, kapalı. |
| `i2c17`, `i2c19` | Hoparlör amfisi ve haptik için yalnız yorum; düğüm yok (çip kimliği bilinmiyor / sürücü yok). |
| Ses, kamera, sensörler | DT’de yok — SoC düzeyinde iş gerekiyor (envanter §10, §15, §16). |

## 4. Varsayımlar ve TODO listesi

Taslakta `TODO(cihaz)` ile işaretli olanlar ve diğer varsayımlar:

1. **Splash biçimi**: `a8r8g8b8`, stride = 1080×4, dolgu yok. Yanlışsa ekranda kayık/renk bozuk görüntü olur → `x8r8g8b8` veya `r8g8b8` (stride 3240) denenir.
2. **Splash adresi**: ABL’nin `fastboot boot` sırasında da 0xe1000000’u taradığı varsayıldı (sagami aynı adresi kullanıyor).
3. **Konsol döndürme**: panel 180° monteli, cihaz yatay kullanılıyor → `fbcon=rotate:1` veya `3` denenmeli.
4. **Hata ayıklama UART pedleri** bilinmiyor; erişilemezse yalnız ekran + USB.
5. **SD kart algılama polaritesi** (GPIO80 ACTIVE_HIGH, `nicole:287`). Yanlışsa kart görünmez → bayrak çevrilir veya geçici `broken-cd`.
6. **msm-id/board-id**: ABL DTB’yi reddederse yorumdaki satırlar açılır.
7. **PM8008j IRQ = GPIO34** (HDK’daki 32/33–34/35 düzeninden çıkarım; Razer DT’sinde IRQ yok). Mainline bağlama `interrupts`’ı zorunlu tutuyor.
8. **FSA4480 IRQ ve vcc** (vcc = BOB varsayıldı, HDK gibi).
9. **NB7VPQ904M varlığı, vcc (S10B varsayıldı) ve şerit sırası** (`<3 2 1 0>` varsayıldı). Yoksa `usb_1_qmpphy_out` doğrudan `pmic_glink_ss_in`’e bağlanır.
10. **WCN6855 PMU besleme eşlemesi**: Razer’ın aon/dig/io/rfa1/rfa2 adları mainline PMU girişlerine çıkarımla eşlendi.
11. **Wi‑Fi PCI kimliği** 17cb:1103 (QCA6490 = WCN6855 hw2.1) — Android’de `lspci` / sysfs.
12. **Panel “vdd” beslemesi**: mainline 1.2 V bekliyor; Razer’da yalnız GPIO13 anahtarlı avdd var.
13. **Dokunmatik reset polaritesi** (ACTIVE_LOW varsayıldı).
14. **Fan GPIO78/93 işlevi** (“usb_charge”, “dpr”) belgelenmemiş; Razer sürücüsünün başlangıç değerleri (78=0, 93=1) korunmalı.
15. **QUP SE13 paylaşımı** (`qcom,shared`): mainline başka bir EE ile çakışabilir.
16. **dispcc probe’u splash’i bozabilir** (paylaşımlı RCG “park” davranışı). Ekran dispcc yüklenince kararırsa: geçici olarak simplefb’den `power-domains` çıkarılıp `&dispcc { status = "disabled"; }` + `pd_ignore_unused` denenir (bu durumda rpmhpd sync_state MMCX’i düşürebilir — dikkat).
17. **pmic-glink’in ertelenmesi pil izlemeyi engeller**: docs/guvenlik-kurallari.md §3 pil sıcaklığı/voltajı kaydını şart koşuyor; mainline’da pil verisi yalnız `qcom_battmgr` (pmic_glink) üzerinden gelir. Öneri: “Faz 2.5” olarak USB’ye dokunmadan yalnız `pmic-glink` (connector’sız ya da mevcut grafla) + ADSP açılsın. O zamana kadar sıcaklık için ADC kanalları ve tsens kullanılır; pil voltajı okunamaz.
18. **Faz 2’de fan muhtemelen çalışmaz**: MAX31760’ın VDD’si PM8008j_l7’den geliyor; Linux PM8008’i açmadan çip enerjisiz kalır. docs/guvenlik-kurallari.md §3 gereği Faz 2’de yük testi yapılmamalı; fan desteği öne çekilmeli (PM8008 sürücüsü + regülatörleri always-on + mainline `max31760` ile elle `pwm1`).

Önerilen Faz 2 çekirdek komut satırı:

```
console=ttyMSM0,115200n8 console=tty0 fbcon=rotate:1 clk_ignore_unused pd_ignore_unused regulator_ignore_unused rootwait root=/dev/mmcblk1p2
```

(`regulator_ignore_unused` mainline’da mevcut: `drivers/regulator/core.c` 6850-6856, kısmi klondan okundu. `mmcblk` numarası `mmc1` alias’ına göre; Cihazda doğrulanacak.)

Çekirdek yapılandırması için hatırlatma (arm64 `defconfig`’te görünmeyenler): `CONFIG_DRM_SIMPLEDRM` (veya `CONFIG_FB_SIMPLE`), `CONFIG_SENSORS_MAX31760`, `CONFIG_PINCTRL_SM8350` (varsayılan olup olmadığı kontrol edilmeli), `CONFIG_SM_DISPCC_8250` (defconfig’te var, sm8350’yi de kapsar), `CONFIG_USB_CONFIGFS_NCM`/`RNDIS` (var).

## 5. Bilinen şema (dtbs_check) uyumsuzlukları

- `fan-controller@50`: `vdd-supply`, `fan-supply`, `vcca-supply`, `usb-charge-en-gpios`, `dpr-en-gpios`, `#cooling-cells` — `adi,max31760.yaml` `additionalProperties: false`. Bağlama uzantısı önerisi, bilinçli.
- `touchscreen@0`: `focaltech,ft3658s` için bağlama yok (sürücüyle birlikte yazılacak).
- `framebuffer@e1000000`: `dsi-vdda-supply`, `dsi-phy-supply` adları serbest desen (`^[a-zA-Z0-9-]+-supply$`), şemaya uygun.

## 6. Faz 0 doğrulama listesi (canlı cihaz, `/sys/firmware/fdt` dökümü)

Not: `/sys/firmware/fdt` root ister; root yoksa `/proc/device-tree` (herkes okuyabilir) aynı ağacın açılmış hâlidir. Döküm: `dtc -I dtb -O dts fdt > live.dts`. Öncelik sırasıyla:

### P0 — İlk açılıştan önce şart

1. **`/reserved-memory`**: her düğümün adresi/boyutu, ABL’nin eklediği/değiştirdiği bölgeler. Özellikle `splash_region` (0xe1000000/0x2300000 hâlâ mı?), `dfps_data_region`, `pil_*` bölgeleri, `cdsp_secure_heap`, `removed_region`. Mainline ile fark varsa taslağa override eklenir.
2. **`/memory`**: 6 GB’ın gerçek aralıkları ve delikleri (splash bölgesi RAM içinde mi?).
3. **`/chosen`**: `bootargs` (özellikle `androidboot.hardware.sku`, `board_rev`, `androidboot.console`), ABL’nin eklediği `linux,initrd-*`, `kaslr-seed`; olası `framebuffer` düğümleri.
4. **Kök `qcom,msm-id` / `qcom,board-id` / `qcom,pmic-id`**: hangi taban DTB’nin (lahainap / v2 / v2.1) seçildiği.
5. **Panel/splash**: `qcom,dsi-display-primary` altında seçilen panel (`qcom,dsi-default-panel`), ABL’nin işaretlediği etkin zamanlama (`qcom,mdss-dsi-timing-default` vb.) ve “cont_splash” bayrakları → simplefb biçimi/çözünürlüğü için ipucu.
6. **`sdhc_2` (`8804000.sdhci`)**: `cd-gpios` son değeri ve `status`.
7. **TLMM**: root varsa `/sys/kernel/debug/gpio` ve `/sys/kernel/debug/pinctrl/*/pinmux-pins` → 56–59’un ayrıldığını, GPIO80 (CD), 13 (avdd), 24, 82 durumlarını gör.

### P1 — Faz 2’nin çevresi

8. **`qupv3_se13_i2c` (`a94000.i2c`) altındaki düğümler**: pm8008i@8/9, pm8008j@c/d, fsa4480@42 durumları; redriver@1c **olmadığını** teyit et. Root varsa `i2cdetect -y <bus>` (yalnız tarama, yazma yok).
9. **Regülatörler**: `pm8008j_l6/l7`, `L3C`, `L8C`, `L9C`, `L12C`, `L13C` için son min/max; `/sys/kernel/debug/regulator/regulator_summary` (root) ile çalışan Android’deki gerçek voltajlar.
10. **USB**: `ssusb@a600000` → `dwc3` `dr_mode`, `usb1` kapalı mı; `lsusb` / `/sys/bus/usb/devices` ile kontrolcü (joystick) nereye bağlı.
11. **PCIe**: `pcie0`/`pcie1` `status`; `/sys/bus/pci/devices/*/{vendor,device}` → QCA6490 kimliği, PCIe1’de cihaz var mı.
12. **Fan**: `max31760@50` düğümü, `maxim,usb_charge_contrl`/`dpr_contrl`; çalışma anında `/sys/class/thermal/cooling_device*/` (fan_speed, fan_duty) değerleri ve hangi termal bölgelere bağlı olduğu.
13. **Termal bölgeler**: `/sys/class/thermal/thermal_zone*/type,temp` listesi → Faz 2’de karşılaştırma tabanı (docs/guvenlik-kurallari.md §3).

### P2 — Sonraki fazlar için

14. **Dokunmatik**: `focaltech@0` düğümü, `spi12` (`a90000.spi`) durumu; `/sys/bus/spi/devices`.
15. **Ses**: `aw882xx_smartpa@34/35` durumları; root varsa çip kimliği (reg 0x00, yalnız okuma).
16. **Haptik**: `haptic_nv@5A`; çip kimliği.
17. **Kamera**: `qcom,cam-sensor0` (Hi‑556) ve pm8008j beslemeleri.
18. **Sensörler**: `/vendor/etc/sensors/config/` altındaki hangi JSON’ların yüklendiği (logcat `sensors`).
19. **Firmware dosyaları**: `/vendor/firmware_mnt/image/` (adsp/cdsp/slpi `.mdt/.bNN`, `a660_zap`), `/vendor/firmware/` (Wi‑Fi `amss.bin`, `m3.bin`, `bdwlan*`, BT `hpbtfw*`/`hpnv*`). Yalnız Mac’e kopyalanır, dışarı yayılmaz (docs/guvenlik-kurallari.md Seviye 4).
20. **SoC sürümü**: `/sys/devices/soc0/{soc_id,revision}` → 439 ve 2.1 beklenir.
