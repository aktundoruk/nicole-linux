# Donanım Envanteri — Razer Edge Wi‑Fi (`RZ80-0461`, `nicole`, SM8350)

> Kaynak: Razer/LineageOS 5.4 çekirdeğinin cihaz ağacı (`sources/razer-kernel/`), mainline Linux 7.3‑rc6 (`sources/linux-mainline/`), LineageOS cihaz ağacı (`sources/lineage-device/`).
> Cihaz henüz bağlanmadı; buradaki her bilgi **kaynak koddan** çıkarıldı. Cihazda görülmeden kesinleşemeyecek her şey **“Cihazda doğrulanacak”** olarak işaretlendi.
> Hazırlanma tarihi: 5 Ekim 2026.

## 0. Kısaltmalar ve kaynak dosyalar

Satır numaralı atıflarda aşağıdaki kısaltmalar kullanılır. Aksi belirtilmedikçe yol `sources/razer-kernel/arch/arm64/boot/dts/vendor/qcom/` altındadır.

| Kısaltma | Dosya |
|---|---|
| `nicole` | `lahainap-nicole.dtsi` (kart dosyası) |
| `nicole-ovl` | `lahainap-nicole-overlay.dts` |
| `qrd-common` | `lahaina-qrd-common.dtsi` (nicole.dtsi:2 tarafından dahil edilir) |
| `pmic-ovl` | `lahaina-pmic-overlay.dtsi` (qrd-common:7) |
| `regs` | `lahaina-regulators.dtsi` |
| `lahaina` | `lahaina.dtsi` (SoC) |
| `pinctrl` | `lahaina-pinctrl.dtsi` |
| `qupv3` | `lahaina-qupv3.dtsi` |
| `usb` | `lahaina-usb.dtsi` |
| `pcie` | `lahaina-pcie.dtsi` |
| `audio` / `audio-ovl` | `lahaina-audio.dtsi` / `lahaina-audio-overlay.dtsi` |
| `thermal` | `lahaina-thermal.dtsi` |
| `sde`, `sde-disp`, `sde-common`, `sde-qrd` | `display/lahaina-sde.dtsi`, `display/lahaina-sde-display.dtsi`, `display/lahaina-sde-display-common.dtsi`, `display/lahaina-sde-display-qrd.dtsi` |
| `panel` | `display/dsi-panel-vtdr6130-dsc-fhd-plus-144hz-cmd.dtsi` |
| `cam` | `camera/lahaina-camera-sensor-nicole.dtsi` |
| `ML:` | `sources/linux-mainline/` altındaki yol |
| `fan.c` | `sources/razer-kernel/drivers/thermal/qcom/max31760_fan.c` |
| `straps.c` | `sources/razer-kernel/drivers/misc/thundersoft_straps.c` |
| `pinctrl-lahaina.c` | `sources/razer-kernel/drivers/pinctrl/qcom/pinctrl-lahaina.c` (blob, kısmi klondan okundu) |

### 0.1 Etkin DT nasıl oluşuyor? (önemli)

- `Makefile:1-6`: `CONFIG_MACH_RAZER_NICOLE=y` ve `CONFIG_BUILD_ARM64_DT_OVERLAY=y` (`arch/arm64/configs/vendor/nicole.config:2,8`) olduğunda yalnızca **`lahainap-nicole-overlay.dtbo`** üretilir; tabanı `lahainap.dtb`, `lahainap-v2.dtb`, `lahainap-v2.1.dtb` (SoC DT’leri) olur.
- Overlay yalnızca `lahainap-nicole.dtsi`’yi içerir (`nicole-ovl:4`). O da `lahaina-qrd-common.dtsi` + `camera/lahaina-camera-sensor-nicole.dtsi`’yi içerir (`nicole:2-3`).
- Yani **etkin zincir: `lahainap(-v2.1).dtsi` → `lahaina.dtsi` + `qrd-common` + `pmic-ovl` + `nicole`**. `lahainap-nicole.dts` (overlay’siz sürüm) ayrıca `lahainap-hhg-hsp-pro.dtsi → lahaina-hhg.dtsi → lahaina-hdk.dtsi`’yi çeker; bu dosyalar overlay yolunda **yoktur**. Bu belge overlay yolunu esas alır.
- `lahaina-qrd.dtsi` **hiçbir yolda dahil edilmez** (aşağıda redriver bölümüne bakın).
- “lahainap” SoC kimliği: `qcom,msm-id = <439 …>, <502 …>` (`lahainap.dtsi:6`, `lahainap-v2.1.dtsi:6`). Mainline `ML:include/dt-bindings/arm/qcom,ids.h:222` → `QCOM_ID_SM8350 = 439`. Yani cihaz **standart SM8350**’dir; downstream’deki “lahaina” (415) başka bir varyanttır. `qcom,board-id = <0x1001f 0x02>` (`nicole-ovl:9`).

## 1. Özet durum tablosu

Durum sütunu: **hazır** = mainline sürücü + DT yeterli; **yalnız DT** = sürücü var, kart DT’si yazılmalı; **sürücü işi** = mainline sürücü eksik/yetersiz; **bilinmiyor**.

| Çevre birimi | Mainline sürücü / compatible | Durum | Taslak DTS’de |
|---|---|---|---|
| microSD (sdhc_2) | `sdhci-msm`, `qcom,sm8350-sdhci` (sm8350.dtsi) | yalnız DT | Faz 2 açık |
| UFS | `ufs-qcom` | yalnız DT (sözleşme gereği kapalı) | **kapalı** |
| USB (a600000) | `dwc3-qcom`, `qcom,sm8350-dwc3` | yalnız DT | Faz 2 açık (gadget, HS) |
| Simple framebuffer | `simpledrm` / `simplefb` | yalnız DT | Faz 2 açık |
| Güç / ses tuşları | `pm8941-pwrkey`, `gpio-keys` | hazır | Faz 2 açık |
| ADSP/CDSP/SLPI | `qcom_q6v5_pas`, `qcom,sm8350-{adsp,cdsp,slpi}-pas` | yalnız DT + firmware | Faz 2 açık |
| Pil / şarj / Type‑C | `qcom,sm8350-pmic-glink` + `qcom_battmgr` + `pmic_glink_altmode` | yalnız DT | Faz 3 (kapalı) |
| Ekran (VTDR6130) | `visionox,vtdr6130` (`ML:drivers/gpu/drm/panel/panel-visionox-vtdr6130.c`) | **sürücü işi** (komut modu + Razer init dizisi) | Faz 3 (kapalı) |
| GPU (Adreno 660) | `msm` | yalnız DT + firmware | Faz 3 (kapalı) |
| Dokunmatik (FT3658S, SPI) | yok (`edt-ft5x06` yalnız I²C) | **sürücü işi** (başka ajan yazıyor) | Faz 3 (kapalı) |
| Fan (MAX31760) | `adi,max31760` (`ML:drivers/hwmon/max31760.c`) | **sürücü işi** (regülatör, GPIO, soğutma cihazı yok) | Faz 3 (kapalı) |
| PM8008j | `qcom,pm8008` (MFD + regülatör) | yalnız DT (IRQ bilinmiyor) | Faz 3 (kapalı) |
| FSA4480 | `fcs,fsa4480` (`ML:drivers/usb/typec/mux/fsa4480.c`) | yalnız DT | Faz 3 (kapalı) |
| NB7VPQ904M redriver | `onnn,nb7vpq904m` | **bilinmiyor** (nicole DT’sinde yok!) | Faz 3 (kapalı) |
| Wi‑Fi (QCA6490) | `ath11k_pci` (WCN6855 0x1103) + `qcom,wcn6855-pmu` | yalnız DT + firmware/board dosyası | Faz 3 (kapalı) |
| Bluetooth (QCA6490) | `hci_uart`/`btqca`, `qcom,wcn6855-bt` | yalnız DT + firmware | Faz 3 (kapalı) |
| Ses: WCD938x + RX/TX/VA makro | `wcd938x`, `lpass-*-macro` | **sürücü + SoC DT işi** (sm8350.dtsi’de LPASS makro/SoundWire düğümü yok, makro sürücülerinde sm8350 compatible yok) | yok |
| Hoparlör amfisi (aw882xx ×2) | aw88261/aw88395/aw88399/aw88081/aw88166 sürücüleri var; hangi çip olduğu belirsiz | **bilinmiyor** | yorum |
| Titreşim (AW8622x) | `ML:…/input/awinic,aw86927.yaml` yalnız AW86927/AW86938 | **sürücü işi** | yorum |
| Ön kamera (Hi‑556) | `hynix,hi556` (mainline’da var; sparse checkout’ta doğrulanamadı) + CAMSS | sürücü işi (CAMSS sm8350) | yok |
| Sensörler (SLPI) | SLPI firmware + userspace (libssc/hexagonrpc) | bilinmiyor | yok |
| Termal (tsens, ADC) | `tsens`, `qcom-spmi-adc5`, `adc-tm5` | yalnız DT | ADC kanalları Faz 2 açık, fan bölgeleri Faz 3 |

## 2. PMIC listesi

| PMIC | Rol | Razer kaynak | Mainline dtsi | Not |
|---|---|---|---|---|
| PMK8350 | PON (güç, RESIN), RTC, ADC (VADC + ADC_TM), SDAM | `pmk8350.dtsi:30-48` (PON), `pmic-ovl:285-492` (ADC) | `ML:arch/arm64/boot/dts/qcom/pmk8350.dtsi` | |
| PM8350 (“B”) | SMPS/LDO B, GPIO (ses+ GPIO6, joystick VBUS GPIO8) | `regs:118-342`, `pmic-ovl:11-40` | `pm8350.dtsi` | |
| PM8350C (“C”) | SMPS/LDO C, BOB, flaş, PWM | `regs:346-789` | `pm8350c.dtsi` | `pm8350c_flash` açık (`qrd-common:346-348`) — Edge’de flaş yok, Cihazda doğrulanacak |
| PM8350B (“D”) | Şarj donanımı (ADSP yönetir), L1D, haptik bloğu | `regs:793-807`, `qrd-common:259-299` | `pm8350b.dtsi` | `pm8350b_haptics` DT’de açık ama Edge AW8622x kullanıyor (Cihazda doğrulanacak) |
| PMR735A (“E”) | SMPS/LDO E (Wi‑Fi aon, anten anahtarı) | `regs:811-969` | `pmr735a.dtsi` | |
| PMR735B | yalnız termal/GPIO | `pmic-ovl:9,430-433` | `pmr735b.dtsi` | |
| PM8008 “j” | Harici I²C LDO (kamera, fan) | `pmic-ovl:168-273`; nicole düzeltmeleri `nicole:179-191` | `qcom,pm8008` (bağlama: `ML:Documentation/devicetree/bindings/mfd/qcom,pm8008.yaml`, kısmi klondan okundu) | adres 0x0c/0x0d, `qupv3_se13_i2c` |
| PM8008 “i” | — | `pmic-ovl:61-166` | — | **nicole’da kapalı** (`nicole:166-170`), reset GPIO33 “NC” (`nicole:333-345`) → kartta muhtemelen yok |
| SMB139x ×2 | Paralel şarj (ADC kanalları) | `pmic-ovl:363-397` | — | ADSP yönetir; Cihazda doğrulanacak |

## 3. Regülatör eşlemesi (Razer → mainline)

RPMh adlandırması: Razer etiketindeki son harf PMIC kimliğidir (`qcom,pmic-id`): **B = PM8350, C = PM8350C, D = PM8350B, E = PMR735A**. Etiketler `regs` dosyasında `L3C: pm8350c_l3: regulator-pm8350c-l3` biçimindedir (`regs:579`). Taslak DTS aynı adları (`pm8350c_l3` vb.) etiket olarak kullanır.

| Razer etiketi | Mainline düğüm (taslak etiket) | Razer aralığı (µV) | Kaynak | Bilinen tüketiciler |
|---|---|---|---|---|
| S10B | `regulators-0/smps10` (`pm8350_s10`) | 1 800 000 sabit | `regs:121-126` | WCD938x (`audio-ovl:257-267`), WLAN io (`lahaina:5399`), fan vcca (`nicole:533`) |
| S11B | `smps11` (`pm8350_s11`) | 752 000–1 012 000 | `regs:133-138` | WLAN dig / BT aon (`lahaina:5397,5649`) |
| S12B | `smps12` (`pm8350_s12`) | 1 224 000–1 360 000 | `regs:150-156` | PM8008 l1/l2 girişi, WLAN rfa2 |
| L1B | `ldo1` (`pm8350_l1`) | 912 000–920 000 | `regs:168-174` | DSI PHY 0.9 V (`sde:91`), USB QMP PHY (`usb:147`) |
| L2B | `ldo2` (`pm8350_l2`) | 3 072 000 | `regs:187-193` | USB HS PHY 3.1 V (`usb:127`) |
| L3B | `ldo3` | 904 000 | `regs:207-213` | — |
| L5B | `ldo5` (`pm8350_l5`) | 880 000–888 000 | `regs:242-248` | USB HS PHY, UFS PHY, PCIe |
| L6B | `ldo6` (`pm8350_l6`) | 1 200 000–1 208 000 | `regs:282-288` | DSI 1.2 V (`sde:90`), PHY PLL’leri |
| L7B | `ldo7` (`pm8350_l7`) | 2 400 000–3 008 000 | `regs:302-308` | UFS VCC (`qrd-common:24-26`) |
| L9B | `ldo9` (`pm8350_l9`) | 1 200 000 | `regs:336-342` | UFS VCCQ |
| S1C | `regulators-1/smps1` (`pm8350c_s1`) | 1 800 000–1 952 000 | `regs:349-354` | PM8008j l3/l4 girişi, WLAN rfa1 |
| S3C | `smps3` | 300 000–704 000 | `regs:377-382` | — |
| S10C | `smps10` | 1 048 000–1 128 000 | `regs:504-509` | — |
| L1C | `ldo1` (`pm8350c_l1`) | 1 800 000 | `regs:522-528` | USB HS PHY 1.8 V |
| L2C | `ldo2` | 1 800 000 | `regs:561-567` | — |
| **L3C** | `ldo3` (`pm8350c_l3`) | **3 008 000 sabit** | `regs:579-585` | Dokunmatik vdd (`nicole:156`). Sagami 3.304 V kullanıyor — kopyalanmamalı |
| L4C / L5C | `ldo4` / `ldo5` | 1 704 000–3 000 000 | `regs:597-621` | — |
| L6C | `ldo6` (`pm8350c_l6`) | 1 800 000–2 960 000 | `regs:634-640` | SD I/O (`qrd-common:45-47`) |
| L7C | `ldo7` | 3 008 000 | `regs:654-660` | — |
| **L8C** | `ldo8` (`pm8350c_l8`) | 1 800 000 | `regs:672-678` | Dokunmatik vcc_i2c (`nicole:157`) |
| L9C | `ldo9` (`pm8350c_l9`) | 2 960 000–3 008 000 (taslakta 2.96 V’a sabitlendi) | `regs:691-697` | SD vdd (`qrd-common:41-43`) |
| L10C | `ldo10` | 1 200 000 | `regs:711-717` | — |
| L11C | `ldo11` | 2 400 000–3 008 000 | `regs:729-735` | — |
| L12C | `ldo12` (`pm8350c_l12`) | 1 800 000–2 000 000 | `regs:748-754` | Panel vddio, nicole 1.86 V ister (`nicole:302-305`, `sde-disp:98`) |
| L13C | `ldo13` (`pm8350c_l13`) | 3 000 000 | `regs:769-775` | Panel vdd 3.0 V (`sde-disp:99`, `sde-common:49-57`) |
| BOB | `bob` (`vreg_bob`) | 3 008 000–3 960 000 | `regs:784-789` | PM8008j l5–l7 girişi, mikrofon bias |
| L1D | (tanımlanmadı) | 1 200 000 | `regs:801-807` | — |
| S1E/S2E/S3E | `regulators-2/smps1..3` | 1.20–1.28 V / 0.50–1.02 V / 2.20–2.352 V | `regs:814-843` | S2E = WLAN aon (`lahaina:5395`) |
| L1E…L7E | `ldo1..7` | `regs:855-969` | | L7E 2.8 V = Wi‑Fi/BT anten anahtarı (`lahaina:5405,5653`) |
| pm8008j_l1 | `pm8008j/regulators/ldo1` | 1 200 000 (nicole) | `nicole:179-182` | Kamera vdig (`cam:16`) |
| pm8008j_l2 | `ldo2` | 944 000–1 056 000 | `pmic-ovl:219-226` | — |
| pm8008j_l3 | `ldo3` | 1 728 000–1 800 000 | `pmic-ovl:228-235` | Kamera vio |
| pm8008j_l4 | `ldo4` | 1 728 000–1 800 000 | `pmic-ovl:237-244` | — |
| pm8008j_l5 | `ldo5` | 2 696 000–2 904 000 | `pmic-ovl:246-253` | Kamera vana |
| **pm8008j_l6** | `ldo6` | 2 800 000–2 900 000 (nicole max) | `pmic-ovl:255-262`, `nicole:184-186` | Fan motoru “vdda / VDD_FAN” (`nicole:532`, `fan.c:30-31`) |
| **pm8008j_l7** | `ldo7` | 3 200 000–3 300 000 (nicole) | `nicole:188-191` | Fan kontrolcüsü VDD; sürücü 3.3 V’a zorlar (`fan.c:28-29`) |
| display_panel_avdd | `panel_avdd` (regulator-fixed) | “5.5 V”, GPIO13 **aktif düşük** | `sde-disp:21-34`, `nicole:295-299,320-330` | Panel avdd |
| joystick_usb_vbus | `joystick_usb_vbus` (regulator-fixed) | 5 V, `pm8350_gpios 8`, always-on | `nicole:542-553` | Kontrolcü (Cihazda doğrulanacak) |

## 4. Bellek haritası: reserved-memory / remoteproc farkları

**Sonuç: Sabit (no-map) carveout’ların tamamı Razer ile mainline arasında birebir aynı.** Remoteproc yükleme adresleri değişmediğinden Razer firmware’leri mainline `sm8350.dtsi` carveout’larıyla uyumlu olmalı.

| Bölge | Razer (`lahaina`) | Mainline (`ML:arch/arm64/boot/dts/qcom/sm8350.dtsi`) | Fark |
|---|---|---|---|
| hyp | 0x80000000 + 0x600000 (`lahaina:298-301`) | 425-428 | aynı |
| xbl_aop | 0x80700000 + 0x160000 (`:303-306`) | 430-433 | aynı |
| cmd_db | 0x80860000 + 0x20000 (`:308-312`) | 435-439 | aynı |
| xbl_uefi_log | 0x80880000 + 0x14000 (`:314-317`) | 441-444 | aynı |
| smem | 0x80900000 + 0x200000 (`:319-322`) | 446-451 | aynı |
| cpucp_fw | 0x80b00000 + 0x100000 (`:324-327`) | 453-456 | aynı |
| cdsp_secure_heap | 0x80c00000 + 0x4600000 (`:329-332`) | 458-461 | aynı |
| pil_camera | 0x85200000 + 0x500000 (`:334-337`) | 463-466 | aynı |
| pil_video | 0x85700000 + 0x500000 (`:339-342`) | 468-471 | aynı |
| pil_cvp | 0x85c00000 + 0x500000 (`:344-347`) | 473-476 | aynı |
| **pil_adsp** | 0x86100000 + 0x2100000 (`:349-352`) | 478-481 | aynı |
| **pil_slpi** | 0x88200000 + 0x1500000 (`:354-357`) | 483-486 | aynı |
| **pil_cdsp** | 0x89700000 + 0x1e00000 (`:359-362`) | 488-491 | aynı |
| pil_ipa_fw / gsi | 0x8b500000+0x10000 / 0x8b510000+0xa000 (`:364-372`) | 493-501 | aynı |
| **pil_gpu** (zap) | 0x8b51a000 + 0x2000 (`:374-377`) | 503-506 | aynı |
| pil_spss | 0x8b600000 + 0x100000 (`:379-382`) | 508-511 | aynı |
| pil_modem | 0x8b800000 + 0x10000000 (`:384-387`) | 513-516 | aynı |
| **rmtfs** | **dinamik**: `qcom,sharedmem-uio`, reg `<0x0 0x280000>` (`lahaina:3026-3031`) | **sabit** 0x9b800000 + 0x280000 (518-525) | **FARK** — Razer’da bu aralık Android için normal RAM. Modem yok → taslakta `&rmtfs_mem` kapatıldı |
| hyp_reserved / trustedvm | 0xd0000000+0x800000 / 0xd0800000+0x76f7000 (`:389-397`) | 527-535 | aynı |
| qrtr_shbuf, neuron 0/1 | 0xd7ef7000…0xd8000000 (`:399-412`) | 537-550 | aynı |
| removed_mem | 0xd8800000 + 0x6800000 (`:414-417`) | 552-555 | aynı |
| **cont_splash** | 0xe1000000 + 0x2300000, **no-map yok** (`:516-519`) | **yok** | taslakta no-map olarak eklendi (sagami gibi) |
| disp_rdump | 0xe1000000 + 0x800000 (`sde:5-8`, soc altında) | yok | splash’in alt kümesi |
| **dfps_data** | 0xe3300000 + 0x100000 (`:535-538`) | **yok** | taslakta no-map eklendi |
| demura 0/1 | boyut 0 (`:525-533`) | yok | kullanılmıyor |
| Dinamik CMA havuzları | adsp 12 MB, sdsp 8 MB, cdsp 4 MB, user_contig 16 MB, qseecom 20 MB, qseecom_ta 16 MB, secure_display 164 MB, cnss_wlan 20 MB, linux,cma 32 MB, mem_dump 48 MB, sp 16 MB, audio_cma 28 MB, memshare 8 MB, non_secure_display 100 MB (`:419-559`) | yok | Mainline’da gerekmez; yalnız Android ION/qseecom içindir |

Ek notlar:
- `lahainap.dtsi:9-11` IPA’yı kapatır → taslakta `&ipa` kapalı.
- `pil_modem_mem` mainline’da da kalır; Razer DT’si de ayırıyor, dokunulmadı.
- ABL çalışma anında reserved-memory’yi değiştirebilir (ör. splash). **Cihazda doğrulanacak**: Faz 0 `/sys/firmware/fdt` dökümü ile karşılaştırma.

### Remoteproc’lar

| Alt sistem | Razer düğümü | PAS id | Firmware adı (downstream) | Mainline | Taslak `firmware-name` | Durum |
|---|---|---|---|---|---|---|
| ADSP (LPASS) | `qcom,lpass@17300000` (`lahaina:4478-4523`) | 1 | `adsp` | `&adsp` (`qcom,sm8350-adsp-pas`, sm8350.dtsi:1891) | `qcom/sm8350/razer/nicole/adsp.mbn` | Faz 2 açık |
| CDSP | `qcom,turing@…` (`lahaina:4525-4570`) | 18 | `cdsp` | `&cdsp` (2511) | `…/cdsp.mbn` | Faz 2 açık |
| SLPI | `qcom,ssc@5c00000` (`lahaina:5111-5150`) | 12 | `slpi` | `&slpi` (2269) | `…/slpi.mbn` | Faz 2 açık |
| MPSS | `qcom,mss@8a800000` (`lahaina:4427-4476`) | 4 | `modem` | `&mpss` (2227) | — | **kapalı** (Wi‑Fi SKU; 5G SKU harici Quectel modem kullanıyor: `nicole:494-499`, `lineage-device/init/init.target.rc` Quectel RIL) |
| Video | `lahaina:4573-4595` | 9 | `venus` | `&iris` | — | Faz 3+ |
| CVP / SPSS / IPA | `lahaina:4742,5159,4616` | 26 / 14 / 0xf | `evass`, `spss`, `ipa_fws` | — | — | kullanılmayacak |

ADSP, “charger_pd” koruma alanını taşır (`lahaina:5558-5562`: `qcom,protection-domain = "tms/servreg", "msm/adsp/charger_pd"`) → pmic_glink için pd-mapper gerekir.

## 5. Ekran / DSI / DSC

| Alan | Değer | Kaynak |
|---|---|---|
| Panel | Visionox VTDR6130, AMOLED, **komut modu**, DSC | `panel:2-6` |
| Çözünürlük / boyut | 1080×2400, 71×158 mm | `panel:41-42,54-55` |
| Yenileme | 60 / 90 / 120 / 144 Hz (timing@0..3), DSI clock 851.7 MHz, yalnız v-front-porch değişir (3436/1484/508/20) | `panel:52-61,162-171,272-281,382-391` |
| DSC | slice 540×20 (DT), PPS içinde slice_height 0x28 = 40, 8 bpc, 8 bpp, block prediction | `panel:153-159,78` |
| Topoloji | `<2 2 1>` (2 LM, 2 DSC, 1 DSI) | `sde-common:809` |
| DSI | yalnız DSI0 + PHY0 | `nicole:569-575` |
| Şerit | 4 lane, `lane_map_0123` | `panel:21-27` |
| Panel yönü | `"180"` (Android açılışta yatay: `vendor.prop:101` ORIENTATION_90) | `panel:40` |
| Reset GPIO | 24 (reset dizisi 1/10 ms, 0/25 ms, 1/20 ms) → mainline `GPIO_ACTIVE_LOW` | `sde-qrd:206`, `nicole:572`, `panel:31` |
| TE GPIO | 82, `mdp_vsync`, pull-down | `sde-qrd:207`, `pinctrl:3056-3067` |
| Besleme | vddio = L12C 1.86 V; vdd = L13C 3.0 V; avdd = GPIO13 anahtarlı (aktif düşük); lab/ibb silindi | `sde-disp:98-102`, `nicole:295-330` |
| DSI denetleyici beslemesi | vdda‑1p2 = L6B, PHY vdda‑0p9 = **L1B** (HDK’da L5B) | `sde:90-91` |
| Arka ışık | DCS (`bl_ctrl_dcs`), 1–2047, ters DBV | `sde-qrd:200-205` |
| Splash | 0xe1000000 + 0x2300000 | `lahaina:516-519` |

Mainline: `panel-visionox-vtdr6130.c` var (bağlama `ML:Documentation/devicetree/bindings/display/panel/visionox,vtdr6130.yaml`; zorunlu `vddio`, `vci`, `vdd`, `reset-gpios`, `port`). Ancak sürücü **video modu** kullanıyor (`MIPI_DSI_MODE_VIDEO`, sürücü 292. satır) ve init dizisi Razer’ınkinden farklı (Razer’da `6F 02`, `B3/C3/D0/C7/BD` ekleri, farklı `B1` ve `CE` yerine `D3`; `panel:69-130`). Mainline’da “vdd” 1.2 V LDO (sm8550‑qrd); Razer’da ayrı 1.2 V ray görünmüyor. → **sürücü işi**.

## 6. Dokunmatik

| Alan | Değer | Kaynak |
|---|---|---|
| Çip | FocalTech FTS (FT3658S), SPI | `nicole:141-164` |
| Veri yolu | `qupv3_se12_spi` @0xa90000 → mainline `&spi12` (wrapper `qupv3_id_1`) | `qupv3:592-611`, `ML sm8350.dtsi:1420` |
| CS / hız | reg 0, 6 MHz | `nicole:146-147` |
| Pinler | GPIO52–55 `qup12`, 6 mA | `pinctrl:879-893` |
| Reset | GPIO22 | `nicole:150` |
| IRQ | GPIO23, 0x2008 = düşen kenar + oneshot; PDC uyandırma 84 | `nicole:148-151`, `pinctrl-lahaina.c` PDC haritası |
| Besleme | vdd = L3C (3.008 V), vcc_i2c = L8C (1.8 V) | `nicole:154-157` |
| Diğer | 10 parmak, 1080×2400, pinctrl `ts_active` (22/23, 8 mA pull-up) | `nicole:152-153`, `pinctrl:1609-1622` |
| Firmware | downstream sürücüde gömülü olabilir — Cihazda doğrulanacak | — |
| Mainline | yok (`edt-ft5x06` yalnız I²C) | — |
| Durum | **sürücü işi**; taslakta `focaltech,ft3658s` yer tutucu | |

## 7. Fan (MAX31760) ve termal

| Alan | Değer | Kaynak |
|---|---|---|
| Veri yolu | `i2c-gpio`: SDA GPIO8, SCL GPIO9, open drain, 5 µs; pinler pull-up 16 mA | `nicole:449-460,512-524` |
| Adres | 0x50, `maxim,max31760` | `nicole:526-528` |
| Besleme | vdd = pm8008j_l7 (sürücü 3.3 V), vdda/fan = pm8008j_l6 (2.8–2.9 V), vcca = S10B 1.8 V | `nicole:530-533`, `fan.c:28-38,424-480` |
| GPIO’lar | GPIO78 `usb_charge_contrl` (probe’da 0), GPIO93 `dpr_contrl` (probe’da 1); işlevleri belgelenmemiş | `nicole:534-535`, `fan.c:370-397` |
| Seviyeler | 0–7 → görev çevrimi {0x00,0x4e,0x71,0x97,0xb2,0xcc,0xe8,0xff} | `fan.c:80` |
| Ek sysfs | `fan_speed` (RPM, TC1H/TC1L), `fan_duty`, `usb_charge_en`, `dpr_en` | `fan.c:129-264` |
| Android servisi | `fan_control 1/0` | `lineage-device/init/init.target.rc:208-219` |
| Mainline | `adi,max31760` sürücüsü var ama regülatör/GPIO/soğutma cihazı yok; bağlama `additionalProperties: false` | `ML:drivers/hwmon/max31760.c:551-555`, `ML:Documentation/devicetree/bindings/hwmon/adi,max31760.yaml` |
| Durum | **sürücü işi** (soğutma cihazı, regülatör açma, GPIO) + PM8008 | |

### Fan soğutma haritası (nicole’un termal bölgeleri)

| Razer bölgesi | Sensör | Tetikler (°C, histerezis) → fan seviyesi | Kaynak | Mainline karşılığı |
|---|---|---|---|---|
| cpu-1-6-step | tsens0 13 (`thermal:546`) | 80/90/95 (5) → 5/6/7 | `nicole:619-656` | `cpu6-bottom-thermal` |
| cpu-1-7-step | tsens0 14 (`thermal:584`) | 80/90/95 (5) → 5/6/7 | `nicole:658-695` | `cpu7-bottom-thermal` |
| gpuss-0-step | tsens1 1 (`thermal:623`) | 85/90/95 (5/5/0) → 5/6/7 | `nicole:697-734` | `gpu-top-thermal` |
| gpuss-1-step | tsens1 2 (`thermal:645`) | 85/90/95 (5/5/0) → 5/6/7 | `nicole:736-773` | `gpu-bottom-thermal` |
| video-step | tsens1 6 | 90 (2) → 7 | `nicole:775-794` | `video-thermal` |
| quiet-therm-step (deri) | PMK ADC_TM, PM8350 AMUX_THM2 | 32/34/36/38/40/42 (2) → 2/3/4/5/6/7 | `nicole:835-909` | yeni `quiet-thermal` (adc-tm) |
| quiet-therm-usr | aynı | 38–46 (userspace) | `nicole:911-948` | — |
| smb-temp-therm-usr | PM8350B AMUX_THM3 | 125 | `nicole:800-813` | ADC kanalı |
| Kapatılan bölgeler | gpu-skin-avg, camera, rear-cam, socd, hot-pock, tof | | `nicole:796-833` | — |

Diğer SoC termal sınırları (downstream): cpu-1-6/1-7 108/110 °C izolasyon (`thermal:543-611`), GPU 95 °C (`thermal:619-660`), xo-therm-step 78/80 °C (`pmic-ovl:627-646`).

Termal ADC kanalları (`pmic-ovl:285-361`, `nicole:589-616`): PMK8350 THM1 (xo), PM8350 THM1 (msm), THM2 (quiet/cam_flash), THM4 (wide_rfc), THM5 (rear_tof), PM8350B THM3 (smb_temp), THM4 (usb_conn), GPIO2 (wl_chg), PM8350B chg_temp/iin/ichg, SMB139x×2.

## 8. USB / Type‑C / redriver / pmic_glink

| Alan | Değer | Kaynak |
|---|---|---|
| Denetleyici | usb0 `ssusb@a600000` (mainline `&usb_1` / `&usb_1_dwc3`), OTG, SuperSpeed+ | `usb:6-78`, BoardConfig `androidboot.usbcontroller=a600000.dwc3` |
| İkinci denetleyici | usb1 + PHY’leri **kapalı** | `nicole:577-587` |
| HS PHY | `usb2_phy0` @88e3000: vdd L5B, vdda18 L1C, vdda33 L2B | `usb:118-127` |
| SS/DP PHY | `usb_qmp_dp_phy` @88e8000: vdd L1B, core L6B | `usb:142-150` |
| Rol / Type‑C | ADSP üzerinden `qcom,ucsi-glink`, `qcom,altmode-glink`, `qcom,battery-charger` | `lahaina:5558-5581` |
| Yön GPIO | GPIO81 `usb_phy` işlevi (port select) | `pinctrl:3652-3678` |
| FSA4480 | 0x42, `qupv3_se13_i2c`, IRQ/besleme tanımsız | `audio:204-209` |
| **NB7VPQ904M** | 0x1c, `onnn,redriver`, GPIO81, EQ tabloları | **yalnızca `lahaina-qrd.dtsi:27-65`** — nicole zincirinde YOK |
| OCP | IRQ GPIO79 (düşen), kontrol GPIO48 (aşırı akımda 0’a çekilir) | `nicole:347-359,501-510`, `drivers/soc/qcom/ocp_irq.c:35-48` |
| Mainline | `qcom,sm8350-pmic-glink` (`ML:…/soc/qcom/qcom,pmic-glink.yaml:31`), `qcom_battmgr.c`, `pmic_glink_altmode.c`, `fsa4480.c`, `nb7vpq904m.c` | yalnız DT |

**Bilinen gerçeklerle çelişki:** Görevde “NB7VPQ904M 0x1c @ se13, GPIO81” verilmişti. Bu düğüm yalnız `lahaina-qrd.dtsi`’de var; nicole overlay’i bu dosyayı dahil etmiyor (`nicole:2` → `qrd-common`). Kartta redriver olup olmadığı **Cihazda doğrulanacak** (`i2cdetect -y <se13>` 0x1c). GPIO81 ise usb_phy port-select pinidir ve mainline HDK’da `orientation-gpios` olarak kullanılıyor (`ML sm8350-hdk.dts:45`).

## 9. Wi‑Fi / Bluetooth (QCA6490)

| Alan | Değer | Kaynak |
|---|---|---|
| Wi‑Fi | `qcom,cnss-qca6490`, PCIe RC0 | `lahaina:5375-5386` |
| GPIO | WLAN_EN 64, BT_EN 65, SW_CTRL 153, XO clk 201 | `lahaina:5380-5382`, `nicole:5-12` |
| Besleme | aon S2E 1.012 V, dig S11B 1.012 V, io S10B 1.8 V, rfa1 S1C 1.9–1.952 V, rfa2 S12B 1.35–1.36 V, anten L7E 2.8 V | `lahaina:5395-5406` |
| PCIe0 | PERST 94, CLKREQ 95, WAKE 96; PHY 1.8 V L6B, 0.9 V L5B | `pcie:38-51`, `pinctrl:2895-2930` |
| BT | `qcom,qca6490`, UART = QUP SE18 4 telli (GPIO68–71) → mainline `&uart18` | `lahaina:5638-5660`, `qupv3:843-863` |
| Mainline | `ath11k_pci` WCN6855 (0x1103) (`ML:drivers/net/wireless/ath/ath11k/pci.c:32,38`), `qcom,wcn6855-pmu` güç sıralayıcı (örnek `sm8450-hdk.dts`), `qcom,wcn6855-bt` | yalnız DT |
| Firmware | ath11k WCN6855 hw2.1 `amss.bin`, `m3.bin`, `board-2.bin` (Razer board-id’siyle), BT `qca/hpbtfw*.tlv`, `hpnv*` | Cihazda doğrulanacak (dosya adları) |
| PCIe1 | wil6210 (11ad) açık görünüyor (`qrd-common:224-226`, `lahaina:5662-5664`); nicole yalnız ayar yapıyor (`nicole:981-984`); 5G SKU’da Quectel olabilir | Cihazda doğrulanacak (`lspci`) |

## 10. Ses

| Bileşen | Değer | Kaynak | Mainline |
|---|---|---|---|
| Bolero / LPASS makroları | `qcom,num-macros = 3` → RX, TX, VA; **WSA makrosu kapalı** | `nicole:18-20,34-36` | Makro sürücüleri var ama sm8350 compatible’ı yok; `sm8350.dtsi`’de makro/SoundWire düğümü yok (yalnız APR/q6afe, `sm8350.dtsi:1929-1995`) |
| SoundWire | swr1 (RX) 1 cihaz, swr2 (TX) 1 cihaz, swr0 (WSA) kapalı | `nicole:22-41` | — |
| WCD938x | `qcom,wcd938x-codec`, reset GPIO88, beslemeler S10B (rxtx/io/buck), BOB 3.296 V (mic bias); micbias 1.8 V | `audio-ovl:230-282,472-477`, `pinctrl:2839-2850` | `wcd938x.c` var |
| WSA883x ×2 | kapalı | `nicole:43-57` | — |
| Hoparlör amfisi | 2× Awinic `aw882xx_smartpa` @0x34 (IRQ GPIO90, kanal 0) ve @0x35 (IRQ GPIO119, kanal 1), `qupv3_se17_i2c` (GPIO72/73), DSP spin modu | `nicole:193-223`, `pinctrl:1552-1564` | aw88261/aw88081/aw88395/aw88399/aw88166 sürücüleri var; hangi çip olduğu **Cihazda doğrulanacak** (çip kimliği) |
| I²S | PRI MI2S: SCK 125, WS 128, SD0 126, SD1 127; RX 1 hat, TX 2 hat | `nicole:59-77`, `pinctrl:2412-2502` | q6afe `PRIMARY_MI2S_*` |
| Mikrofon | AMIC2 + DMIC1/2 (VA), USB‑C analog ses (mbhc usbc) | `nicole:79-110` | |
| Kart adı | `lahaina-hhg-snd-card` (HHG = Qualcomm el konsolu referansı) | `nicole:80` | |
| Firmware | ADSP + ACDB/aw882xx parametre dosyaları | — | Cihazda doğrulanacak |
| Durum | **sürücü + SoC DT işi** | | |

## 11. Titreşim (haptik)

| Alan | Değer | Kaynak |
|---|---|---|
| Çip | Awinic AW8622x (`awinic,haptic_nv`, sürücü `AW8622X_DRIVER`) | `nicole:225-262`, `drivers/misc/haptic_nv/haptic_nv.h:15-25` |
| Veri yolu / adres | `qupv3_se19_i2c` (GPIO76/77) → mainline `&i2c19`, reg 0x5a (`aw862xx_i2c_addr = 0x58`) | `nicole:225-232`, `pinctrl:1580-1592` |
| IRQ / reset | IRQ GPIO44 (0x2008), reset GPIO106; GPIO16/17 hi‑Z | `nicole:233-240,435-447` |
| Kalibrasyon | f0_pre 0x92E vb. | `nicole:241-259` |
| PMIC haptik | `pm8350b_haptics` qrd-common’da açık; `swr_haptics` nicole’da kapalı | `qrd-common:259-299`, `nicole:26-28` |
| Mainline | `awinic,aw86927.yaml` yalnız AW86927/AW86938 | **sürücü işi** |

## 12. Fiziksel tuşlar

| Tuş | Kaynak donanım | Kaynak | Mainline |
|---|---|---|---|
| Güç | PMK8350 PON `kpdpwr` (PON_HLOS 0x1300, IRQ 0x13/7) | Razer `pmk8350.dtsi:30-42` | `&pon_pwrkey` |
| Ses − | PMK8350 PON `resin` (IRQ 0x13/6), KEY_VOLUMEDOWN | Razer `pmk8350.dtsi:44-47` | `&pon_resin` + `linux,code` |
| Ses + | `pm8350_gpios 6`, aktif düşük, pull-up, power-source 1 | `qrd-common:306-323`, `pmic-ovl:12-19` | `gpio-keys` |

## 13. microSD (sdhc_2)

| Alan | Değer | Kaynak |
|---|---|---|
| Denetleyici | `sdhc_2` @0x8804000 (fstab `8804000.sdhci`) | `lineage-device/init/fstab.qcom:47` |
| Kart algılama | **GPIO80, ACTIVE_HIGH**, pull-up (referanstaki GPIO92 ACTIVE_LOW’un yerine) | `nicole:270-293`, `qrd-common:53` |
| Besleme | vdd = L9C 2.95–2.96 V, 800 mA; vdd-io = L6C 1.808–2.96 V | `qrd-common:40-47` |
| Pinler | clk 16 mA, cmd/data 10 mA pull-up (mainline 16 mA) | `pinctrl:99-123` |
| Diğer | `cap-mmc-hw-reset`, GCC_SDCC2_BCR reset | `nicole:289-292` |
| Durum | yalnız DT — polariteyi **Cihazda doğrulanacak** | |

## 14. UFS

`ufshc@1d84000` + `ufsphy_mem@1d87000`, 2 lane; vcc L7B 2.504–2.95 V, vccq L9B, phy L5B/L6B, vccq-parent S12B (`lahaina:3044-3075`, `qrd-common:9-38`). **Sözleşme gereği Faz 3 onayına kadar DTS’de kapalı.**

## 15. Kamera (yalnız liste)

| Alan | Değer | Kaynak |
|---|---|---|
| Sensör | Hynix Hi‑556 (TXD modülü), tek kamera, EEPROM aynı modülde | `cam:10-83`, `lineage-device/proprietary-files.txt:104-108` |
| Veri yolu | CCI1 (`cci-master 1`), CSIPHY5, MCLK5 GPIO105 19.2 MHz, reset GPIO115, sensör dönüşü 270° | `cam:30-48` |
| Besleme | vio pm8008j_l3 1.8 V, vana pm8008j_l5 2.8 V, vdig pm8008j_l1 1.2 V, BOB 3.2–3.96 V | `cam:53-63` |
| Mainline | `hi556` sürücüsü mainline’da var (sparse checkout’ta doğrulanamadı); SM8350 CAMSS desteği Cihazda/kaynakta doğrulanacak | |

## 16. Sensörler

Sensörler SLPI üzerinden yönetiliyor; kart DT’sinde I²C düğümü yok. LineageOS dosya listesinde HHG profilleri: `lahaina_hhg_ak991x_0.json` (manyetometre), `lahaina_hhg_lsm6dst_0.json` (IMU), `lahaina_hhg_sx9302x_0.json` (SAR), `lahaina_hhg_tmd3702_0.json` (ışık/yakınlık) (`lineage-device/proprietary-files.txt:849-870`). Hangilerinin gerçekten takılı olduğu **Cihazda doğrulanacak**. Mainline’da SLPI firmware’i + userspace (libssc) yolu gerekir.

## 17. “thundersoft,straps” SKU / kart revizyonu

| Strap | GPIO’lar (MSB→LSB) | Yorum | Kaynak |
|---|---|---|---|
| `sku` | GPIO7, GPIO6, GPIO3 (pull-up, giriş) | değer 0 → `androidboot.hardware.sku=5g`, diğer → `wifi` | `nicole:462-476,555-566`, `straps.c:28-66` |
| `board_rev` | GPIO51, GPIO50, GPIO45 | 0 EVB, 1 T0, 2 EVT1, 3 EVT2, 4 DVT1, 5 DVT2, 6 DVT3, 7 MP | `nicole:477-489`, `straps.c:69-84` |

Okuma: `value = (gpio[n-1] << (n-1)) | … | gpio[0]` (`straps.c:28-45`). Mainline’da sürücü yok; taslak DTS bu pinlere pull-up uygular ve `gpio-line-names` verir → `gpioget` ile okunabilir. Beklenen: SKU ≠ 0 (Wi‑Fi), rev = 7 (MP) — **Cihazda doğrulanacak** (`/proc/cmdline` içindeki `androidboot.hardware.sku/board_rev`).

## 18. Diğer GPIO’lar

| GPIO | İşlev | Kaynak |
|---|---|---|
| 12, 26, 33 | NC (pull-down) | `nicole:333-345` |
| 13 | Panel AVDD etkin (aktif düşük) | `nicole:295-330` |
| 16, 17 | Haptik hi‑Z | `nicole:435-447` |
| 18, 19 | Hata ayıklama UART (QUP SE3, `serial0`) | `qupv3:72-85`, `lahaina:46` |
| 35 | PM8008j reset | `pinctrl:2880-2892` |
| 48 | OCP kontrol (HHG’de fan_en idi) | `nicole:505`, `lahaina-hhg.dtsi:91` |
| 49, 116 | 5G modül güç kesme / reset (5G SKU) | `nicole:494-499` |
| 56–59 | **TZ’ye ayrılmış** (nicole’a özel liste) | `pinctrl-lahaina.c:1940-1946` |
| 79 | USB OCP IRQ | `nicole:347-359` |
| 86 | `sim_gpio` | `nicole:361-373` |
| 88 | WCD938x reset | `pinctrl:2839-2850` |
| 203 | UFS reset | (mainline HDK) |

## 19. SM8350 HDK / MTP / Sagami’den farklar (port tuzakları)

1. **Ayrılmış GPIO’lar**: HDK/MTP `gpio-reserved-ranges = <52 8>` kullanır (`ML sm8350-hdk.dts:561`). Nicole’da 52–55 dokunmatik SPI’dır; Razer yalnız **56–59**’u ayırır (`pinctrl-lahaina.c:1940-1946`). Yanlış aralık ya dokunmatiği engeller ya da TZ korumalı pine erişimde (gpiolib yön okuması) SError/yeniden başlatma yaratır.
2. **SD kart algılama** GPIO80 aktif yüksek (HDK: GPIO92).
3. **Ekran**: HDK’da LT9611 HDMI köprüsü; nicole’da VTDR6130 komut modu + DSC. DSI PHY beslemesi L1B (HDK L5B).
4. **Modem/IPA yok**; rmtfs Razer’da dinamik.
5. **PM8008 yalnız “j”**; “i” yok (HDK iki tane kullanır).
6. **L3C 3.008 V** (sagami 3.304 V), SD L9C ≤ 2.96 V.
7. **İkinci USB denetleyici yok** (HDK usb_2’yi hub ile kullanır); PCIe1 kullanılmıyor.
8. **Fan** ve i2c-gpio veri yolu yalnız bu cihazda; mainline sürücüsü soğutma cihazı değil.
9. **Hoparlörler WSA değil**, MI2S üzerinden aw882xx; WSA makrosu kapalı.
10. **QUP SE13 “qcom,shared”** (`qupv3:754`): downstream bu SE’yi başka bir yürütme ortamıyla paylaşıyor; mainline `i2c-qcom-geni`’de karşılığı yok.
11. **Önyükleme**: boot header v3 + `vendor_boot` + ayrı `dtbo` (`BoardConfig.mk`: `BOARD_BOOT_HEADER_VERSION := 3`, `BOARD_KERNEL_SEPARATED_DTBO := true`). ABL DTB’yi vendor_boot’tan seçip dtbo’yu uygular; `fastboot boot` ile mainline DTB’nin nasıl seçileceği **Cihazda doğrulanacak**. Sagami notu: SM8350’de msm/board-id eklemek ABL’yi bozabilir (`ML sm8350-sony-xperia-sagami.dtsi:17-22`).
12. **Hata ayıklama UART** pedleri bilinmiyor; ekran konsolu (simplefb) birincil çıktı olmalı.
13. **Panel 180° monteli**, cihaz yatay kullanılıyor → konsol döndürme gerekir.
