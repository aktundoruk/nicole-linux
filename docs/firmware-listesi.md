# Firmware listesi — Razer Edge Wi‑Fi (nicole, SG8175P / SM8350 ailesi)

> Durum: cihaz bağlanmadan önce hazırlandı (5 Ekim 2026). `TODO(cihaz)` işaretli her satır canlı cihazda doğrulanmalı.
> Kural (docs/guvenlik-kurallari.md §2, Seviye 4): Razer/Qualcomm firmware dosyaları **yalnız bu Mac'te ve cihazda** kalır; hiçbir yere yüklenmez, commit edilmez (`.gitignore` zaten `*.mbn`, `*.mdt`, `*.bNN`, `firmware/`, `yedek/` dışlıyor).
> Dosyaların cihazdan alınması: `scripts/faz0/03-firmware.sh` (root ile salt okuma, çıktı `$YEDEK_KOK/firmware-<zaman>/`).

## 0. Özet

| # | Bileşen | Mainline sürücü | Kaynak | Bölünmüş mü? | Hedef (rootfs) | Faz / KT |
|---|---|---|---|---|---|---|
| 1 | ADSP (ses DSP'si + **pil/şarj/USB‑C**: pmic_glink) | `qcom_q6v5_pas` (`qcom,sm8350-adsp-pas`) | `/vendor/firmware_mnt/image/adsp.mdt` + `adsp.bNN` | Evet → `pil-squasher` | `qcom/sm8350/razer/nicole/adsp.mbn` | **M3** (pil, fan sıcaklığı), USB‑C rol/altmode |
| 2 | CDSP (hesaplama DSP'si) | `qcom_q6v5_pas` (`qcom,sm8350-cdsp-pas`) | `/vendor/firmware_mnt/image/cdsp.mdt` + `cdsp.bNN` | Evet | `qcom/sm8350/razer/nicole/cdsp.mbn` | İsteğe bağlı (M2 sonrası) |
| 3 | SLPI (sensör hub) | `qcom_q6v5_pas` (`qcom,sm8350-slpi-pas`) | `/vendor/firmware_mnt/image/slpi.mdt` + `slpi.bNN` | Evet | `qcom/sm8350/razer/nicole/slpi.mbn` | Sözleşme dışı (sensörler); başlangıçta kapalı |
| 4 | Modem (MPSS) | — | **Yok sayılır** (Wi‑Fi SKU, bkz. §2.4) | — | — | Kullanılmaz |
| 5 | IPA | — | `/vendor/firmware/ipa_fws.mdt` + `.b00–b04` | Evet | — | Kullanılmaz (`lahainap.dtsi` IPA'yı kapatıyor) |
| 6 | GPU SQE | `msm` (a6xx) | linux-firmware `qcom/a660_sqe.fw` (v1.12) | Hayır | `qcom/a660_sqe.fw` (dağıtım paketi) | **M2** |
| 7 | GPU GMU | `msm` (a6xx GMU) | linux-firmware `qcom/a660_gmu.bin` (v3.01.0A) | Hayır | `qcom/a660_gmu.bin` (dağıtım paketi) | **M2** |
| 8 | GPU ZAP shader | `msm` + `qcom_scm` | `/vendor/firmware/a660_zap.mdt` + `.b00–b02` (+ `a660_zap.elf`) | Evet | `qcom/sm8350/razer/nicole/a660_zap.mbn` | **M2** |
| 9 | Video (Iris/Venus, VPU 2.0) | `venus` / `iris` (`qcom,sm8350-iris`) | `/vendor/firmware/vpu20_4v.mbn` (tek parça) veya `.mdt`+`.b00–b19` | Gerekmez (`.mbn` var) | `qcom/sm8350/razer/nicole/vpu20_4v.mbn` | Sözleşme dışı |
| 10 | Wi‑Fi (QCA6490 = WCN6851/WCN6855 ailesi) | `ath11k_pci` | `/vendor/firmware_mnt/image/qca6490/` → `amss.bin`/`amss20.bin`, `m3.bin`, `bdwlan.*`, `regdb.bin` | Hayır; **board-2.bin üretilmeli** | `ath11k/WCN6855/hw1.1/…` veya `hw2.x/…` | **M4** |
| 11 | Bluetooth (aynı çip) | `hci_uart` + `btqca` | `/vendor/bt_firmware/image/hpbtfwXX.tlv`, `hpnvXX.bYY` | Hayır | `qca/razer/nicole/…` (DT `firmware-name`) | M4 sonrası |
| 12 | Dokunmatik FT3658S (§7) | projedeki `focaltech_ft3658s_spi` | `/vendor/firmware/AX6175A_Visionox_FT3658S.bin` | Hayır | **Gerekmez** (yalnız yedek) | M5 |
| 13 | Ses amfisi (Awinic aw882xx ×2) | (ileride `aw88261`/`aw88395` uyumlu mu?) | `/vendor/firmware/aw882xx_acf.bin` | Hayır | — | Sözleşme dışı |
| 14 | Titreşim (aw8622x) | yok | `/vendor/firmware/aw8622x_*.bin` | — | — | Sözleşme dışı |
| 15 | Hexagon dosya sistemi (`/vendor/dsp`, sensör registry) | `hexagonrpcd` (kullanıcı alanı) | `dsp` bölümü (ext4) + `/vendor/etc/sensors`, `/mnt/vendor/persist/sensors` | — | `/usr/share/qcom/sm8350/Razer/nicole/` | Sözleşme dışı |
| 16 | QUP (QUPv3 seri motor) firmware | — | XBL yüklüyor (`qupfw` bölümü) | — | — | Linux'ta gerekmez |
| 17 | Kamera ICP, EVA (`evass`), CVP | yok / mainline'da desteklenmiyor | `/vendor/firmware/CAMERA_ICP.elf`, `evass.*` | — | — | Kapsam dışı |

En zor üç kalem: **(a) Wi‑Fi board verisi** (board-2.bin adı + çip revizyonu, §5), **(b) a660_zap** (OEM imzalı olmalı, linux-firmware'deki kopya çalışmaz, §3), **(c) Bluetooth NVM** (ROM sürümü + board-id'ye bağlı dosya adı, §6).

## 1. Genel kurallar

### 1.1 Cihazdaki konumlar (LineageOS ağacından)

- `modem` bölümü (vfat, NON‑HLOS) → `/vendor/firmware_mnt` (`init/fstab.qcom`: `/dev/block/bootdevice/by-name/modem … /vendor/firmware_mnt vfat ro,shortname=lower …`). Dosyalar `image/` altında, **8.3 küçük harf** adlarla (`adsp.b00`, `bdwlan.e1b` …).
- `dsp` bölümü (ext4) → `/vendor/dsp` (Hexagon kitaplıkları; FastRPC/hexagonrpcd).
- `bluetooth` bölümü (vfat) → `/vendor/bt_firmware` (`image/` altında BT rampatch/NVM).
- `vendor` (super içinde) → `/vendor/firmware/` (GPU, video, IPA, dokunmatik, amfi, haptik; `proprietary-files.txt` satır 75–1061).
- Android'in firmware arama yolu: `init/ueventd.qcom.rc:31` → `firmware_directories /vendor/firmware_mnt/image/` (+ varsayılan `/vendor/firmware`, `/odm/firmware`).
- `proprietary-firmware.txt` yalnız bölüm imajlarını listeler (`modem.img`, `dsp.img`, `bluetooth.img`, `abl.img` …); bunlar **Faz 0 yedeğinden** (veya LineageOS OTA `payload.bin`'inden) de çıkarılabilir. Bölüm imajını açmak için: `modem.img`/`bluetooth.img` vfat → `mtools` (`mcopy -i modem.img -s ::image ./`), `dsp.img` ext4 → `debugfs -R 'rdump / out' dsp.img`.

### 1.2 Bölünmüş (split) firmware ve `pil-squasher`

Qualcomm PIL imajları Android'de `NAME.mdt` (ELF başlığı + program başlık tablosu + hash segmenti) ve her segment için `NAME.b00 … NAME.bNN` olarak durur. Mainline `qcom_q6v5_pas`/`mdt_loader` `.mdt` + `.bNN` okuyabilir, ancak projede (ve pmOS'ta) **tek parça `.mbn`** tercih edilir: dağıtımı ve `firmware-name` kullanımı kolaydır, imza korunur.

```bash
# VM içinde (vm-setup.sh kurar):
pil-squasher adsp.mbn  /yol/firmware_mnt/image/adsp.mdt   # .b00..bNN aynı dizinde olmalı
pil-squasher a660_zap.mbn /yol/vendor/firmware/a660_zap.mdt
```

- Kaynak: <https://github.com/linux-msm/pil-squasher> (Ubuntu'da paket **yok**, `vm-setup.sh` kaynaktan derler).
- pmOS örnekleri aynı yolu izliyor: `firmware-oneplus-instantnoodlep` (`pil-squasher "$builddir/adsp/adsp.mbn" "$builddir/adsp/adsp.mdt"`) — <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/testing/firmware-oneplus-instantnoodlep/APKBUILD>.
- Doğrulama: `file adsp.mbn` → "ELF 32-bit LSB executable, QUALCOMM DSP6"; boyut ≈ tüm `.bNN` toplamı.

### 1.3 Hedef yol kuralı

- Cihaza özgü/imzalı: `/lib/firmware/qcom/sm8350/razer/nicole/<ad>.mbn` (pmOS'ta usr-merge: fiziksel yol `/usr/lib/firmware/…`; çekirdek açısından fark yok). DTS'te `firmware-name = "qcom/sm8350/razer/nicole/adsp.mbn";` (zaten `dts/sm8350-razer-nicole.dts:404–414, 823`).
- Genel (imzasız, Qualcomm'un dağıttığı): linux-firmware'deki yerinde bırakılır (`qcom/a660_sqe.fw`, `ath11k/…`, `qca/…`).
- **PD mapper JSON'ları** (`adspr.jsn`, `adspua.jsn`, `battmgr.jsn`, `cdspr.jsn`, `slpir.jsn`, `slpius.jsn`): mainline'da çekirdek içi `qcom_pd_mapper` (CONFIG_QCOM_PD_MAPPER) SM8350 tablosunu içeriyor (`drivers/soc/qcom/qcom_pd_mapper.c:588,661` — kök `compatible` içinde `"qcom,sm8350"` olmalı, DTS'te var). Kullanıcı alanı `pd-mapper` kullanılmayacaksa `.jsn` gerekmez; yine de yedekte tutulur.

## 2. Uzak işlemciler (remoteproc)

Razer DT'si (`sources/razer-kernel/.../lahaina.dtsi`): `qcom,firmware-name = "adsp"` (4498), `"cdsp"` (4545), `"slpi"` (5130), `"modem"` (4443), `"venus"` (4594), `"ipa_fws"` (4618), `"evass"` (4746), `"spss"` (5189), `"trustedvm"` (5202).

### 2.1 ADSP — en önemli DSP

- Kaynak: `/vendor/firmware_mnt/image/adsp.mdt` + `adsp.b00…bNN` (sayı cihazda belli olur; SM8350'de tipik 20–30 segment).
- Dönüştürme: `pil-squasher adsp.mbn adsp.mdt`.
- Hedef: `qcom/sm8350/razer/nicole/adsp.mbn`.
- Neden kritik: SM8350'de **pil göstergesi, şarj, USB‑C rol/yön, DP altmode** ADSP üzerindeki `battmgr`/`pmic_glink` servisinden geliyor (`qcom_battmgr.c` SM8350 tabloları: `drivers/power/supply/qcom_battmgr.c:429–527`). M3 (Güç) ADSP olmadan bitmez. Ayrıca ses (APR/q6afe) ileride ADSP'ye bağlı.
- Bağımlılık: GLINK‑SMEM, QRTR, `qcom_pd_mapper`, `qcom_sysmon`. Modüller rootfs'tan yükleneceği için firmware'in initramfs'ta olması **gerekmez** (pmOS bazı cihazlarda koyuyor: `firmware-xiaomi-elish-initramfs`).
- Not: ADSP, Android'de bazı modülleri FastRPC ile `/vendor/dsp/adsp` (ve `/vendor/lib/rfsa/adsp`) üzerinden çekiyor (ses efektleri, aptX). Pil/şarj için gerekmez; ses aşamasında `hexagonrpcd` ile değerlendirilir.

### 2.2 CDSP

- `/vendor/firmware_mnt/image/cdsp.mdt` + `.bNN` → `cdsp.mbn`. Hedef `qcom/sm8350/razer/nicole/cdsp.mbn`.
- Kilometre taşlarında gerekmiyor; remoteproc altyapısını test etmek için iyi bir "ilk DSP" (yan etkisi az). İstenmezse DTS'te `&remoteproc_cdsp` kapalı bırakılabilir.

### 2.3 SLPI

- `/vendor/firmware_mnt/image/slpi.mdt` + `.bNN` → `slpi.mbn`.
- Sensörler (IMU vb.) SLPI'da, kullanıcı alanında `hexagonrpcd` + `libssc` gerektirir; sensör registry dosyaları `/vendor/etc/sensors/config/lahaina_hhg_*.json` (proprietary-files.txt 848–920) ve `/mnt/vendor/persist/sensors`. **Persist'e asla yazılmaz** (Seviye 4) — yalnız okunup kopyalanır.
- Sözleşme kapsamı dışında; ilk aşamada DTS'te `status = "disabled"` önerilir (bazı SM8350 cihazlarında SLPI, registry yokken tekrar tekrar çöküp log kirletiyor — doğrulanmadı).

### 2.4 Modem — Wi‑Fi SKU'da yok

- Razer DT'si `lahainap*.dtsi` kullanıyor: `qcom,msm-id = <439 …>, <502 …>`. İndirilmiş Razer çekirdeğindeki `drivers/soc/qcom/socinfo.c:773–780` → **439 = "SG8175P"** (Snapdragon G3x Gen 1), 502 = "SM8325P", 415 = "LAHAINA" (SM8350). Mainline `qcom,ids.h:222` 439'u `QCOM_ID_SM8350` olarak adlandırıyor; bu yalnız isim farkı, sayı aynı.
- 5G SKU (RZ45‑0460, Verizon) hücresel bağlantıyı **harici Quectel modül** ile yapıyor (`lahainap-nicole.dtsi:494` `quectel,5g-module-ctrl`, `extract-files.py` Quectel RIL düzeltmeleri). Dolayısıyla Wi‑Fi SKU'da MPSS firmware'i kullanılmaz; DTS'te `&mpss` kapalı kalmalı.
- `TODO(cihaz)`: `ls /vendor/firmware_mnt/image/modem*` — dosya olsa bile yüklenmeyecek. `cat /sys/devices/soc0/soc_id` (439 beklenir).

### 2.5 IPA

- `lahainap.dtsi:9` → `&ipa_hw { status = "disabled"; }`. IPA yalnız modem veri yolu için; Wi‑Fi SKU'da gereksiz. `/vendor/firmware/ipa_fws.*` yedekte kalır, paketlenmez.

## 3. GPU (Adreno 660)

| Dosya | Kaynak | İmza | Not |
|---|---|---|---|
| `qcom/a660_sqe.fw` | linux-firmware (WHENCE: "File: qcom/a660_sqe.fw … Version: v1.12") | İmzasız mikro kod | Cihazdaki `/vendor/firmware/a660_sqe.fw` yedek; sürüm farkı sorun çıkarırsa cihazınki denenir. |
| `qcom/a660_gmu.bin` | linux-firmware ("qcom/a660_gmu.bin … v3.01.0A") | İmzasız | Cihazdaki `/vendor/firmware/a660_gmu.bin` yedek. |
| `a660_zap.mbn` | **Cihaz**: `/vendor/firmware/a660_zap.mdt` + `a660_zap.b00–b02` (+ `a660_zap.elf`) | **OEM (Razer) imzalı** — TrustZone doğrular | `pil-squasher a660_zap.mbn a660_zap.mdt` → `qcom/sm8350/razer/nicole/a660_zap.mbn` |

- **Tuzak:** linux-firmware'de `qcom/sm8350/a660_zap.mbn` var ama bu `../qcm6490/a660_zap.mbn` dosyasına **sembolik bağ** (WHENCE: "Link: qcom/sm8350/a660_zap.mbn -> ../qcm6490/a660_zap.mbn"). QCM6490 IoT platformu için Qualcomm anahtarıyla imzalı; secure boot'u açık bir Razer cihazında TZ bunu reddeder → `msm` "zap shader" yükleyemez → GPU açılmaz. DTS bu yüzden kendi yolumuzu gösteriyor (`dts/sm8350-razer-nicole.dts:823`).
- `a660_zap.elf` Android'de bazen tek parça olarak da duruyor; `pil-squasher` çıktısıyla `cmp` edilip hangisinin tam olduğu kontrol edilmeli (`TODO(cihaz)`).
- pmOS'ta SQE/GMU `firmware-qcom-adreno-a660` paketinden geliyor (FP5/Nothing Phone (1) paketleri böyle bağlanıyor).

## 4. Video (Iris / Venus, VPU 2.0)

- Razer: `lahaina-vidc.dtsi:37` `vidc,firmware-name = "vpu20_4v"`; cihazda `/vendor/firmware/vpu20_4v.mbn` **tek parça** olarak zaten var (proprietary-files.txt 1059), ayrıca `.mdt` + `.b00–b19` ve `vpu20_4v_unsigned.mbn`.
- Mainline: `sm8350.dtsi:2756` `compatible = "qcom,sm8350-iris", "qcom,sm8250-venus"`; `sm8350-hdk.dts` `firmware-name = "qcom/vpu/vpu20_p4_sm8350.mbn"` kullanıyor — bu dosya **linux-firmware'de yok** (WHENCE'te `vpu20_p4_gen2_s6.mbn`, `vpu20_p4_sm8450_s7.mbn` var, sm8350 yok). Video firmware'i TZ tarafından doğrulandığı için yine **cihazınki** kullanılmalı: `qcom/sm8350/razer/nicole/vpu20_4v.mbn`.
- `vpu20_4v_unsigned.mbn` kullanılmaz (TZ reddeder).
- Kilometre taşı yok; donanım video çözme ileride.

## 5. Wi‑Fi — QCA6490 / WCN6851 / WCN6855 (ath11k)

### 5.1 Çip kimliği

- Razer DT: `lahaina.dtsi:5375` `wlan: qcom,cnss-qca6490@b0000000`, `compatible = "qcom,cnss-qca6490"`, PCIe0 (`qcom,wlan-rc-num = <0>`), `wlan-en-gpio = <&tlmm 64>`, BT‑EN 65, SW_CTRL 153; nicole ekstra `qcom,xo-clk-gpio = <&tlmm 201 0>` (`lahainap-nicole.dtsi:10–12`).
- Mainline: PCI kimliği `17cb:1103` → `ath11k_pci` bunu WCN6855 sayar; revizyon `soc_hw_version` ile seçilir (`drivers/net/wireless/ath/ath11k/pci.c:1035–1070`): major 2 / minor 0x00–0x01 → **hw2.0**, major 2 / minor 0x10–0x11 → **hw2.1** (veya QCA2066/QCA6698AQ alt türleri). **Major 1 desteklenmiyor**: `Unsupported WCN6855 SOC hardware version: 1 16`.
- **Önemli bulgu:** Haziran 2026'da Dmitry Baryshkov SM8350 HDK için "WCN6851" desteği gönderdi; commit mesajı: WCN6851 "SM8350 platformlarında bulunan, WCN6855'in daha eski bir sürümü, kendini **hw1.1** olarak tanıtıyor" ve yeni `ATH11K_HW_WCN6855_HW11`, firmware dizini `WCN6855/hw1.1` ekliyor. Bu seri 7.3‑rc6 ağacımızda **yok** (`grep HW11` boş). SM8350 HDK ile nicole aynı DT soyundan (`lahaina-hdk.dtsi` → `lahaina-hhg.dtsi` → `lahainap-hhg-hsp-pro.dtsi`) geliyor; bu yüzden nicole'ün de **hw1.1** olması kuvvetle muhtemel.
  - Seri: <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/00215.html> (0/7), ath11k yaması <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/00219.html>, DT <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/00228.html>, `num_vdevs` tartışması <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/09843.html> (v2'deki 4 değeri orijinal firmware'i çökertiyor, 3'e dönülecek).
  - Eylem: M4'e gelindiğinde bu serinin güncel sürümü `drivers/wifi/` altına `.patch` olarak konur (`build-kernel.sh` otomatik uygular). DT tarafında `"qcom,wcn6851-pmu", "qcom,wcn6855-pmu"` ve `"qcom,wcn6851-bt", "qcom,wcn6855-bt"` uyumluları bu seriyle geliyor.
- `TODO(cihaz)`: Android'de (root) `dmesg | grep -i cnss` → `Get device version info, family number…, major version: 0x?` ve `Target capability: chip_id: 0x…, chip_family: 0x…, board_id: 0x…, soc_id: 0x…`; ayrıca `cat /sys/bus/pci/devices/*/{vendor,device,subsystem_vendor,subsystem_device}` (Wi‑Fi açıkken PCIe0 bağlantısı kurulur).

### 5.2 Android tarafında dosya adları (cnss2 kaynağından)

Razer çekirdeğinin `drivers/net/wireless/cnss2/` kaynağı (<https://github.com/LineageOS/android_kernel_razer_sg8175p/tree/lineage-23.2/drivers/net/wireless/cnss2>):

- WLAN düğümünde `qcom,same-dt-multi-dev` var (`lahaina.dtsi`), bu da `cnss_use_fw_path_with_prefix()`'i doğru yapıyor → tüm adların başına **`qca6490/`** eklenir (`pci.c:44–50`, `main.c:3083–3089`). Arama yolu `/vendor/firmware_mnt/image/` olduğundan gerçek konum: **`/vendor/firmware_mnt/image/qca6490/`** (önek yoksa yedek ad da denenir).
- Ana firmware: major sürüm 2 ise `amss20.bin`, değilse `amss.bin` (`pci.c:5355–5385`). → Dizinde hangisinin bulunduğu çip revizyonu hakkında ipucu verir.
- M3: `m3.bin` (`pci.c:48`).
- Board data (`qmi.c:18–28, 515–575`): OTP'deki `board_id`
  - `0xFF` ise `bdwlan.elf` (GlobalFoundries üretimi çipte `bdwlang.elf`),
  - `< 0xFF` ise `bdwlan.eXX` (`XX` = board_id onaltılık, ör. `bdwlan.e1b`),
  - `> 0xFF` ise `bdwlanXX.eYY`;
  - `.bin` biçimi için `bdwlan.bXX` (ELF tercih edilir).
- Regülasyon: `regdb.bin`.

### 5.3 Mainline ath11k ne istiyor?

Dizin: `/lib/firmware/ath11k/WCN6855/<hw>/` (`<hw>` = `hw1.1`, `hw2.0` veya `hw2.1`):

| Dosya | Kaynak | Not |
|---|---|---|
| `amss.bin` | hw2.x: linux-firmware (`WLAN.HSP.1.1-03125-QCAHSPSWPL_V1_V2_SILICONZ_LITE-3.6510.41`; hw2.1 → hw2.0'a bağ). hw1.1: linux-firmware'de **yok** → cihazın `qca6490/amss.bin` (veya `amss20.bin`) dosyası `amss.bin` adıyla. | PCIe Wi‑Fi firmware'i çipin kendi ROM'u tarafından doğrulanıyor (Qualcomm imzası), OEM imzası yok → linux-firmware kopyası hw2.x'te çalışmalı. |
| `m3.bin` | Aynı mantık | |
| `board-2.bin` | **Üretilmeli** (aşağıda) | linux-firmware'deki board-2.bin'de Razer girdisi yok. |
| `regdb.bin` | linux-firmware veya cihazın `qca6490/regdb.bin` | `supports_regdb = true` (core.c:542). Önce board-2.bin içindeki REGDB, sonra `regdb.bin` aranır (core.c `ath11k_core_fetch_regdb`). |

`firmware-name` DT özelliği (wifi@0 düğümünde) verilirse `amss.bin`/`m3.bin` `ath11k/WCN6855/<hw>/<firmware-name>/` altından okunur, **ama `board*` dosyaları her zaman ana dizinden** (`core.h:1342–1358`). Yani `amss.bin`'i cihazınkiyle değiştirmek istersek linux-firmware dosyasını ezmeden `firmware-name = "razer-nicole"` + `ath11k/WCN6855/hw2.1/razer-nicole/amss.bin` yapılabilir.

### 5.4 board-2.bin ve `qcom,calibration-variant`

ath11k (PCI, `ATH11K_BDF_SEARCH_BUS_AND_BOARD`) board adını şöyle kurar (`core.c:1509–1556`):

```
bus=pci,vendor=17cb,device=1103,subsystem-vendor=SSSS,subsystem-device=DDDD,qmi-chip-id=C,qmi-board-id=B,variant=V
```

Arama sırası: (1) tam ad + `variant`, (2) `variant`'sız tam ad, (3) `bus=pci,qmi-chip-id=C`, (4) `board.bin` (API 1). `variant`, DT'deki `qcom,calibration-variant` (yeni ad) veya `qcom,ath11k-calibration-variant` (eski ad) özelliğinden gelir (`core.c:1477–1497`; 32 karaktere kadar).

Sonuç: **Evet, mainline için cihazın `bdwlan.*` dosyasından bir board-2.bin girdisi üretmek gerekiyor.** Önerilen ad değişkeni: `qcom,calibration-variant = "Razer_Nicole";` (upstream örnekleri: `"LE_X13S"`, `"MS_SP9_5G"`, `"QC_8350_HDK"`).

Yöntem (VM'de, `vm-setup.sh` `ath11k-bdencoder`'ı kurar — <https://github.com/qca/qca-swiss-army-knife/blob/master/tools/scripts/ath11k/ath11k-bdencoder>):

1. İlk açılışta board-2.bin girdisi olmadan ath11k'yi yükle; hata mesajı tam adı verir:
   `failed to fetch board data for bus=pci,vendor=17cb,device=1103,subsystem-vendor=…,qmi-chip-id=…,qmi-board-id=…,variant=Razer_Nicole from ath11k/WCN6855/hw…/board-2.bin`
   (Ayrıntı için `modprobe ath11k debug_mask=0x…` ile "using board name" satırı.)
2. `qmi-board-id` değerine karşılık gelen Android dosyasını seç: `0xff` (255) → `bdwlan.elf`; aksi hâlde `bdwlan.e<hex>`. GlobalFoundries çipinde `bdwlang.*`.
3. Mevcut linux-firmware board-2.bin'ine ekle (hw2.x) veya sıfırdan oluştur (hw1.1):
   ```bash
   # hw2.x: upstream dosyaya ekle (kopya üzerinde)
   cp /lib/firmware/ath11k/WCN6855/hw2.0/board-2.bin .
   ath11k-bdencoder -a board-2.bin bdwlan.e1b \
     "bus=pci,vendor=17cb,device=1103,subsystem-vendor=17cb,subsystem-device=0108,qmi-chip-id=2,qmi-board-id=27,variant=Razer_Nicole"
   # hw1.1: JSON ile sıfırdan
   cat > board-2.json <<'EOF'
   [{"board": [{"names": ["bus=pci,vendor=17cb,device=1103,subsystem-vendor=…,subsystem-device=…,qmi-chip-id=…,qmi-board-id=…,variant=Razer_Nicole"],
                "data": "bdwlan.elf"}],
     "regdb": [{"names": ["bus=pci"], "data": "regdb.bin"}]}]
   EOF
   ath11k-bdencoder -c board-2.json -o board-2.bin
   ```
   (Yukarıdaki sayılar örnektir — gerçek değerler 1. adımdan.)
4. ath11k ELF biçimli BDF'yi tanıyor (`qmi.c:2439` ELF sihirli baytına bakıp `ATH11K_QMI_BDF_TYPE_ELF` seçiyor); `bdwlan.eXX` olduğu gibi kullanılabilir.
5. Paketleme: hw2.x'te board-2.bin linux-firmware ile çakışır → `firmware-razer-nicole-wifi` paketi `replaces="linux-firmware-ath11k"` ile birleştirilmiş dosyayı kurar (pmOS `firmware-oneplus-instantnoodlep` aynı yolu izliyor). Alpine linux-firmware dosyaları `.zst` sıkıştırılmış olabilir; APKBUILD bunu açıyor.

### 5.5 Güç sıralaması ve DT notu (DTS ekibine)

Mainline'da Wi‑Fi/BT, `qcom,wcn6855-pmu` (pwrseq) düğümüyle açılıyor; HDK yaması: `wlan-enable-gpios = <&tlmm 64>`, `bt-enable-gpios = <&tlmm 65>`, `swctrl-gpios = <&tlmm 153>`, beslemeler S10B 1.8 V, S11B 0.95 V, S2E 0.85 V, S12B 1.25 V, S1C 1.86 V. **nicole'de ek olarak GPIO 201 "xo-clk"** var (Razer `qcom,xo-clk-gpio`); mainline bağlamasında karşılığı (`xo-clk-gpios`) var mı `TODO`. Mevcut DTS PCIe0 ve Wi‑Fi'yi kapalı tutuyor — M4'te açılacak.

## 6. Bluetooth (aynı çipin BT çekirdeği, UART18)

- Razer: `bluetooth: bt_qca6490` (`lahaina.dtsi:5638`), BT_EN GPIO 65, nicole'de XO reset GPIO 201. Android HAL dosyaları `/vendor/bt_firmware/image/` altında.
- Mainline `btqca.c` (WCN6855 türü; WCN6851 uyumlusu da WCN6855 yolunu kullanacak) — <https://github.com/torvalds/linux/blob/master/drivers/bluetooth/btqca.c>:
  - rampatch: `qca/wcnhpbtfw%02x.tlv`, bulunamazsa `qca/hpbtfw%02x.tlv` (`%02x` = ROM sürümü, ör. `10`, `21`).
  - NVM: `qca/wcnhpnv%02x[g].b%02x` (çipten okunan board‑id; `g` = GlobalFoundries), yoksa `.bin`, yoksa `hpnv…` adları.
  - DT `firmware-name = "<nvm>", "<rampatch>";` ile tam ad verilebilir (iki girdili biçim 2025'te eklendi; ad `qca/` altına göre).
- linux-firmware'de **SM8350 HDK için** `qca/wcnhpbtfw10.tlv` (BTFM.HSP.1.0.0‑00978) + `qca/wcnhpnv10.bin`, `qca/wcnhpnv10.b06` var; 2.1 ROM için `wcnhpbtfw21.tlv` + çok sayıda `wcnhpnv21.bXX`. HDK'da çip "QCA Product ID 0x13, ROM version 0x100" bildiriyor → `…10.…` dosyaları.
- Beklenen Android dosyaları (`TODO(cihaz)`: `ls /vendor/bt_firmware/image/`): `hpbtfw10.tlv` + `hpnv10.bin`/`hpnv10.bXX` (ROM 1.0) veya `hpbtfw21.tlv` + `hpnv21.*` (ROM 2.1). Bölüm başka çipler için `msbtfw11.*`, `htbtfw20.*` de içerebilir — onlar kullanılmaz.
- Öneri: rampatch'i linux-firmware'den al (genel), **NVM'i cihazdan** al (anten/kalibrasyon ayarı Razer'a özgü), DT'de:
  ```dts
  firmware-name = "razer/nicole/hpnv10.bXX", "razer/nicole/hpbtfw10.tlv";
  ```
  → dosyalar `/lib/firmware/qca/razer/nicole/`. (`btqca` adı `qca/` önekiyle birleştirdiği için `qcom/sm8350/...` kuralı burada uygulanamıyor; bu bilinçli bir istisna.)
- Faz: sözleşmede BT kilometre taşı yok; M4 ile aynı yamalar/PMU düğümüyle birlikte gelir.

## 7. Dokunmatik — FocalTech FT3658S (SPI, QUP SE12)

- Razer sürücüsü (`sources/razer-kernel/drivers/input/touchscreen/focaltech_touch_spi/`): `FTS_AUTO_UPGRADE_EN 1`, `FTS_FW_REQUEST_SUPPORT 1`, `FTS_FW_NAME_PREX_WITH_REQUEST "AX6175A_Visionox_FT3658S"` → açılışta `request_firmware("AX6175A_Visionox_FT3658S.bin")` (`focaltech_flash.c:41–43, 1936`), bulunamazsa sürücüye gömülü `.i` dizisine düşer; IC'deki sürüm farklıysa **flash'a yazar**.
- Cihazda: `/vendor/firmware/AX6175A_Visionox_FT3658S.bin` + `…_20220301.ini` (üretim testi eşikleri). `goodix_*.bin` başka bir panel varyantı için (kullanılmaz).
- Projedeki mainline taslak sürücü (`drivers/touchscreen/focaltech_ft3658s_spi.c`) **firmware istemiyor**; IC firmware'ini flash'tan çalıştırıyor, yalnız "bootloader'da takılı" durumunu algılıyor (satır 272–301). → Mainline için dosya **gerekmez**; yalnız flash bozulursa kurtarma için yedekte tutulur. Dokunmatik flash'ına yazmak bu sözleşmede yapılmaz.

## 8. Ses (sözleşme dışı, not)

- Lahaina sesi APR/Elite (q6afe/q6asm/q6adm) — mainline'da `SND_SOC_SM8250` makine sürücüsü + APR; AudioReach topolojisi (`*-tplg.bin`) **gerekmez**. ACDB (`/vendor/etc/acdbdata/HDK/lahaina-hhg-snd-card/*.acdb`) mainline'da kullanılmaz.
- Hoparlör amfileri `awinic,aw882xx_smartpa` @0x34/0x35 (i2c17): `/vendor/firmware/aw882xx_acf.bin`. Mainline'da `aw88261`/`aw88395`/`aw88399` sürücüleri ACF biçimli dosya istiyor; hangi çip olduğu (çip ID kaydı) ve ACF uyumu `TODO(cihaz)`.

## 9. Faz 0 sonrası yapılacaklar (kontrol listesi)

1. `03-firmware.sh` çıktısında şunları doğrula:
   - `vendor/firmware_mnt/image/{adsp,cdsp,slpi}.mdt` ve `.bNN` sayıları
   - `vendor/firmware_mnt/image/qca6490/` içeriği (`amss.bin` mi `amss20.bin` mi, `bdwlan.*` listesi, `regdb.bin`, `m3.bin`)
   - `vendor/bt_firmware/image/` içeriği
   - `vendor/firmware/a660_zap.*`, `vpu20_4v.mbn`
   - `modem.mdt` var mı (yalnız bilgi)
2. Android'de (root) çip bilgilerini kaydet: `dmesg | grep -iE 'cnss|bt_|qca|ath'`, `cat /sys/devices/soc0/{soc_id,revision,machine}`, `cat /proc/device-tree/qcom,msm-id | xxd`, `cat /proc/device-tree/qcom,board-id | xxd`, PCI alt sistem kimlikleri.
3. `pil-squasher` ile `.mbn`'leri üret, `pmaports/firmware-razer-nicole` için yerel dump tar'ını hazırla (bkz. APKBUILD başındaki açıklama).

## Kaynaklar

- linux-firmware WHENCE (GPU, ath11k, qca, vpu girdileri): <https://gitlab.com/kernel-firmware/linux-firmware/-/blob/main/WHENCE>
- pil-squasher: <https://github.com/linux-msm/pil-squasher>
- ath11k-bdencoder: <https://github.com/qca/qca-swiss-army-knife/tree/master/tools/scripts/ath11k>
- btqca.c (mainline): <https://github.com/torvalds/linux/blob/master/drivers/bluetooth/btqca.c>
- WCN6851 / SM8350 HDK serisi: <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/00215.html>, <https://lkml.iu.edu/2606.0/00593.html>
- Razer cnss2 kaynağı: <https://github.com/LineageOS/android_kernel_razer_sg8175p/tree/lineage-23.2/drivers/net/wireless/cnss2>
- pmOS örnek firmware paketleri: <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/testing/firmware-oneplus-instantnoodlep/APKBUILD>, <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/testing/firmware-xiaomi-elish/APKBUILD>
- Yerel: `sources/lineage-device/{proprietary-files.txt,init/fstab.qcom,init/ueventd.qcom.rc}`, `sources/razer-kernel/arch/arm64/boot/dts/vendor/qcom/{lahaina.dtsi,lahainap*.dtsi,lahainap-nicole*.dts*}`, `sources/linux-mainline/drivers/net/wireless/ath/ath11k/{core.c,core.h,pci.c,qmi.c}`.
