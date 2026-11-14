# Panel analizi — Visionox VTDR6130 (Razer Edge Wi‑Fi, `nicole`)

> Durum: cihaz bağlanmadan önce yapılan masa başı analiz. Kaynaklar:
> Razer/LineageOS 5.4 çekirdeği (`sources/razer-kernel/`) ve mainline 7.3‑rc6
> (`sources/linux-mainline/`). "Cihazda doğrulanmalı" işaretli her değer
> çıkarımdır.

## 1. Kısa sonuç

- Mainline `panel-visionox-vtdr6130.c` **olduğu gibi kullanılamaz**. Sürücü aynı
  panel IC'sini SM8550 HDK/QRD modülü için **video modunda** sürüyor. Razer ise
  **komut modunda (TE ile)** sürüyor ve Razer'ın modülüne özgü ek ayar
  yazmaçları gönderiyor. Bunun dışında besleme seti farklı (nicole'de 1.2 V
  `vdd` yok, onun yerine GPIO13 ile anahtarlanan bir panel rayı var),
  parlaklık üst sınırı farklı (2047 / 4095), reset darbesi daha uzun ve panel
  180° ters monte edilmiş.
- Çözüm: `drivers/panel/0001-drm-panel-visionox-vtdr6130-razer-nicole.patch`.
  Yama sürücüye varyant tanımı (`struct visionox_vtdr6130_desc`) ekliyor ve
  yeni bir uyumlu dizge tanımlıyor: `"visionox,vtdr6130-razer-nicole"`. Bu
  varyantın kendi init dizisi, modu, DSI bayrakları, DSC parametreleri,
  beslemeleri ve reset süreleri var. Mevcut `"visionox,vtdr6130"` davranışı
  değişmiyor. Yama ayrıca panel-common `rotation` özelliğini de destekliyor.
  `git apply --check` ile mainline'a temiz uygulandığı ve `checkpatch --strict`
  çıktısının temiz olduğu doğrulandı. Derlenmedi, çünkü burada çekirdek ağacı
  yok.
- `razer,` üretici öneki mainline'da **yok** (`vendor-prefixes.yaml`). Bu yüzden
  uyumlu dizge, `visionox,rm69299-shift` örneğindeki gibi panel üreticisi
  önekiyle verildi. Kart DTS'i yukarı gönderilecekse `razer` öneki zaten
  eklenmek zorunda kalacak. O zaman isim tartışmaya açılabilir.

## 2. Kaynak dosyalar

| Ne | Dosya |
|---|---|
| Panel tanımı (4 zamanlama, komutlar, DSC) | `arch/arm64/boot/dts/vendor/qcom/display/dsi-panel-vtdr6130-dsc-fhd-plus-144hz-cmd.dtsi` |
| Panel ek ayarları (ESD, topology, PHY timings) | `.../display/lahaina-sde-display-common.dtsi` (`&dsi_vtdr6130_amoled_cmd`, satır ~783) |
| Parlaklık, reset ve TE GPIO'su | `.../display/lahaina-sde-display-qrd.dtsi` (`&dsi_vtdr6130_amoled_cmd`, satır ~199) |
| DSI ekranı, regülatörler, TE kaynağı | `.../display/lahaina-sde-display.dtsi` (`&sde_dsi`) |
| nicole geçersiz kılmaları | `.../lahainap-nicole.dtsi` (`&sde_dsi`, `&display_panel_avdd`, `&dsi_panel_pwr_supply`) |
| Pinctrl | `.../lahaina-pinctrl.dtsi` (`sde_dsi_active/suspend`, `sde_te_active`) |
| Ayrıştırıcı | `techpack/display/msm/dsi/dsi_panel.c` |
| Razer'a özgü kod | `techpack/display/msm/dsi/dsi_display.c` (yalnızca ESD okuma bayrakları, `CONFIG_MACH_RAZER_NICOLE`) |

## 3. Parametre karşılaştırması

| Parametre | Razer (nicole) | Mainline sürücü | Not |
|---|---|---|---|
| Çözünürlük | 1080×2400 | 1080×2400 | aynı |
| Fiziksel boyut | 71×158 mm | 71×157 mm | yama 158 kullanıyor |
| Mod | **komut modu** (`dsi_cmd_mode`) | **video modu** (`MIPI_DSI_MODE_VIDEO`) | asıl fark |
| Şerit (lane) | 4 (`lane_map_0123`, lane0‑3) | 4 | aynı |
| Piksel biçimi | RGB888 (bpp 24) | RGB888 | aynı |
| EoT | eklenmiyor (`tx-eot-append` yok) | `MIPI_DSI_MODE_NO_EOT_PACKET` | aynı |
| Saat şeridi | sürekli değil (`force-clock-lane-hs` yok) | `MIPI_DSI_CLOCK_NON_CONTINUOUS` | aynı |
| DSI denetleyici | yalnızca DSI0 / PHY0 (nicole `&sde_dsi` geçersiz kılıyor), topology `<2 2 1>` = 2 LM, 2 DSC, 1 arayüz | tek DSI | panel dtsi'deki `dsi-sec-ctrl-num = <1>` kullanılmıyor |
| Bit hızı | `qcom,mdss-dsi-panel-clockrate = 851700000` (şerit başına 851.7 Mbps) | moddan hesaplanıyor | ↓ hesap |
| Yön | `qcom,mdss-dsi-panel-orientation = "180"` | yok | yama `rotation = <180>` okuyor |
| HDR | peak 4 200 000, blackness 3230, primaries | yok | kullanılmıyor |

### 3.1 Zamanlamalar (4 mod)

Dört modun hepsinde yatay değerler ve piksel saati aynı. Yenileme hızı yalnızca
VFP (dikey ön kenar) ile değişiyor:

| | timing@0 | timing@1 | timing@2 | timing@3 | Mainline |
|---|---|---|---|---|---|
| Yenileme | 60 Hz | 90 Hz | 120 Hz | 144 Hz | 144 Hz |
| HFP / HSW / HBP | 20 / 4 / 20 | 20 / 4 / 20 | 20 / 4 / 20 | 20 / 4 / 20 | 20 / 2 / 20 |
| VFP | 3436 | 1484 | 508 | 20 | 20 |
| VSW / VBP | 4 / 16 | 4 / 16 | 4 / 16 | 4 / 16 | 2 / 18 |
| Htotal × Vtotal | 1124×5856 | 1124×3904 | 1124×2928 | 1124×2440 | 1122×2440 |
| Piksel saati | 394.93 MHz | 394.93 MHz | 394.93 MHz | 394.93 MHz | 394.23 MHz |
| `0x6C` | `02` | `02` | `01` | `01` | `01` |
| Sayfa 0x13 yazmacı | `D3` | `D3` | `CE` | `CE` | `CE` |

Şerit hızı hesabı (mainline msm DSI, `dsi_adjust_pclk_for_compression`):
hdisplay 1080 → 1080×8/24 = 360. Yeni htotal 1124−1080+360 = 404.
pclk = 394 928 kHz × 404/1124 ≈ 141.95 MHz. Bayt saati pclk×24/(8×4) ≈
106.46 MHz, yani şerit başına **851.7 Mbps**. Bu, Razer'ın
`panel-clockrate` değeriyle birebir aynı. Yamadaki 144 Hz modu bu yüzden
Razer'ın yatay değerlerini (HSW = 4) kullanıyor.

`qcom,mdss-dsi-panel-phy-timings = [00 1C 08 07 17 16 07 07 08 02 04 00 19 0C]`
(dört mod için aynı). Mainline 5 nm DSI PHY bunları kendisi hesaplıyor. Gerekirse
karşılaştırmak için not alındı.

### 3.2 DSC

| | Razer (DT, host'un gönderdiği PPS) | Mainline sürücü | `0x70` ham PPS (her ikisinde aynı) |
|---|---|---|---|
| Sürüm | 1.1 (`qcom,mdss-dsc-version` yok, varsayılan `0x11`) | 1.2 | `0x12` |
| Dilim genişliği | 540 (satır başına 2 dilim) | 540, `slice_count = 2` | 540 |
| Dilim yüksekliği | **20** | **40** | 40 |
| bpc / bpp | 8 / 8 | 8 / 8 (`8 << 4`) | **10** / 8 |
| Paket başına dilim | 1 | 1 (`DSC_ALL_SLICES_IN_PKT` yok) | – |
| Blok tahmini | açık | açık | açık |
| line_buf_depth | (hesaplanan 9) | (hesaplanan 9) | 11 |

- `0x70` komutu 94 baytlık ham bir PPS taşıyor. Razer ile mainline'da bayt bayt
  aynı (doğrulandı). İçindeki değerler 10 bpc'lik ve dilim yüksekliği 40 olan
  bir yapılandırmaya ait (`flatness 7/16`, `rc_quant_incr_limit 15`, ilk RC
  aralığı `0/8/+2`). Host'un ekran açıldıktan sonra gönderdiği gerçek PPS
  paketi (DSI tipi 0x0A) bunu geçersiz kılıyor gibi görünüyor. Razer 20,
  mainline 40 dilim yüksekliğiyle çalışıyor. **Cihazda doğrulanmalı.**
- Yama nicole için Razer'ın kanıtlanmış değerlerini kullanıyor: DSC 1.1, dilim
  yüksekliği 20. SM8350 DPU'su (`dpu_7_0_sm8350.h`, `dce_*` blokları) iki
  dilimi de destekliyor.
- PPS sırası: Razer, `dsi_display_enable` içinde önce ON komutlarını, ardından
  `dsi_panel_update_pps` çağrısıyla PPS'i gönderiyor. Mainline de
  `display_on` + 20 ms sonrasında PPS gönderiyor. Sıra aynı.

### 3.3 TE (tearing effect)

- Panel: `35 00` → TE açık, V‑blank modu (`MIPI_DSI_DCS_TEAR_MODE_VBLANK`).
- Razer: `te-pin-select = 1`, `te-dcs-command = 1`, `te-check-enable`,
  `te-using-te-pin`, `qcom,platform-te-gpio = <&tlmm 82 0>`,
  `qcom,panel-te-source = <0>`, `wr-mem-start 0x2C`, `wr-mem-continue 0x3C`.
- SoC: GPIO82, `mdp_vsync` fonksiyonu (mainline `pinctrl-sm8350.c`:
  `PINGROUP(82, mdp_vsync, ...)` doğrulandı). Pinctrl 2 mA, pull‑down.
- Mainline: DSI uç noktasında `qcom,te-source` (`dsi_host.c` içinde
  `of_property_read_string(endpoint, "qcom,te-source")`). Varsayılan
  `mdp_vsync_p`, Razer'ın kaynak 0'ıyla eşleşiyor. Açıkça yazılması önerilir.

### 3.4 Reset

`qcom,mdss-dsi-reset-sequence = <1 10>, <0 25>, <1 20>;` Bunlar fiziksel
seviyeler. Hat aktif düşük (`qcom,platform-reset-gpio = <&tlmm 24 0>`).
`dsi_panel_reset()` her adımda `usleep_range(ms*1000, ms*1000+100)` kullanıyor.

| Adım | Razer | Mainline |
|---|---|---|
| bırak (yüksek) | 10 ms | 10 ms |
| reset (düşük) | **25 ms** | 10 ms |
| bırak (yüksek) | **20 ms** | 10 ms |

Kapanışta Razer `reset_gpio = 0` yapıp regülatörleri kapatıyor. Mainline de
reset'i aktif edip regülatörleri kapatıyor. Yama nicole için 10/25/20 ms
kullanıyor.

`qcom,mdss-dsi-lp11-init`: reset'ten önce DSI şeritleri LP‑11'de olmalı.
Mainline'daki karşılığı `panel.prepare_prev_first = true` ve sürücüde zaten
var.

### 3.5 Güç ve regülatörler

nicole'deki etkin değerler (`lahaina-sde-display.dtsi` +
`lahaina-sde-display-common.dtsi` + `lahainap-nicole.dtsi` geçersiz
kılmaları):

| Sıra | Downstream adı | Kaynak | Gerilim | Yük | Gecikme |
|---|---|---|---|---|---|
| 1 | `vddio` | `L12C` (pm8350c ldo12) | **1.86 V** (nicole geçersiz kılması; tanım aralığı 1.8–2.0 V) | 60.7 mA | açılıştan sonra 20 ms |
| 2 | `vdd` | `L13C` (pm8350c ldo13) | 3.0 V | 10 mA | kapanmadan önce ve sonra 2 ms (nicole) |
| 3 | `avdd` | `display_panel_avdd`: `qti-regulator-fixed`, **GPIO13, aktif düşük** (nicole), adı "5.5 V", rampa 233 µs, `regulator-boot-on`, proxy | 5.5 V (adı) | 100 mA | – |

- Varsayılan Qualcomm `lab`/`ibb` (LCD bias) girdileri nicole'de kaldırılmış.
  `entry@3` silinmiş, `entry@2` ise `avdd` olarak yeniden adlandırılmış.
- Mainline sürücü `vddio`, `vci` (3.0 V) ve `vdd` (SM8550'de 1.2 V) istiyor.
  nicole'de 1.2 V'luk ayrı bir panel rayı **yok** (büyük olasılıkla modül
  üzerinde VDDIO'dan üretiliyor; **cihazda doğrulanmalı**). Buna karşılık
  GPIO13 ile açılan bir ray var. Bu ray AMOLED modülündeki güç IC'sini
  (ELVDD/ELVSS/AVDD) açıyor olmalı. Downstream'deki "avdd 5.5 V" adı LCD
  kalıntısı.
- Eşleme: `vddio` → L12C, `vci` → L13C (downstream'deki adı `vdd`, 3.0 V),
  `avdd` → GPIO13 sabit regülatörü.
- `regulator_bulk_enable()` beslemeleri paralel açar ve sıra garanti değildir.
  Yama nicole için beslemeleri sırayla açıyor (vddio → 20 ms → vci → avdd) ve
  ters sırada, aralarda 2 ms bekleyerek kapatıyor.
- DSI denetleyici ve PHY beslemeleri (`lahaina-sde.dtsi`): `vdda-1p2` = L6B
  (1.2 V), PHY `vdda-0p9` = L5B (0.88 V). Bunlar mainline `sm8350-hdk.dts`
  ile aynı (`vreg_l6b_1p2`, `vreg_l5b_0p88`).

### 3.6 Parlaklık

- `qcom,mdss-dsi-bl-pmic-control-type = "bl_ctrl_dcs"` → DCS 0x51.
- `bl-min-level 1`, **`bl-max-level 2047`**, `brightness-max-level 255`
  (Android kullanıcı alanı 0..255, 1..2047 aralığına eşleniyor).
- `qcom,mdss-dsi-bl-inverted-dbv`: `dsi_panel_update_backlight()` değeri bayt
  takası yapıp `mipi_dsi_dcs_set_display_brightness()`'e veriyor. Sonuç: 0x51
  **2 bayt, büyük uçlu (big endian)**. Mainline'daki
  `mipi_dsi_dcs_set_display_brightness_large()` tam olarak bunu yapıyor.
- Init dizisinde Razer `51 07 FF` (2047) yazıyor, mainline `51 00 00`.
- Mainline `max_brightness = 4095`. 2047'nin üstü büyük olasılıkla HBM (yüksek
  parlaklık) aralığı. El cihazında ısı ve yanma riski olduğu için yama
  nicole'de 2047 ile sınırlıyor.

### 3.7 ESD (bilgi amaçlı, yamada yok)

`qcom,esd-check-enabled`, `reg_read`, LP modunda:
`06 … 68` (2 bayt, beklenen `00 00`), `06 … 0A` (1 bayt, beklenen `9C` = güç
modu: booster açık, uykudan çıkmış, ekran açık), `39 … FF 5A 80`,
`15 … 65 37`, `06 … F5` (3 bayt, beklenen `00 00 00`). Razer'ın tek çekirdek
değişikliği bu okumaların bayraklarıyla ilgili. Mainline'da panel ESD
çerçevesi yok. Gerekirse ileride `0x0A == 0x9C` denetimi eklenebilir.

## 4. Komut dizileri — bayt bayt

Downstream biçimi: `tip son vc ack bekleme(ms) uzunluk(2 bayt) yük…`.
`39` = DCS uzun yazma, `05` = DCS kısa yazma (parametresiz), `06` = DCS
okuma, `15` = DCS kısa yazma (1 parametre). Açılış komutları
`dsi_lp_mode`, kapanış komutları `dsi_hs_mode` ile gönderiliyor. Yalnızca
`11` (120 ms) ve `29` (20 ms) için bekleme tanımlı.

### 4.1 Açılış dizisi (timing@3 = 144 Hz; diğer modlar yalnızca ★ satırlarında farklı)

| # | Razer nicole | Mainline | Açıklama / fark |
|---|---|---|---|
| 1 | `03 01` | `03 01` | sıkıştırma/DSC etkin (üreticiye özgü, çıkarım) |
| 2 | `35 00` | `35 00` (set_tear_on VBLANK) | TE açık |
| 3 | `53 20` | `53 20` | WRCTRLD: BCTRL=1 |
| 4 | `51 07 FF` | **`51 00 00`** | başlangıç parlaklığı (2047 / 0) |
| 5 | `59 09` | `59 09` | |
| 6 | `6C 01` | `6C 01` | ilk değer; 60/90 Hz'de 26. satır `02` yazıyor |
| 7 | `6D 00` | `6D 00` | |
| 8 | **`6F 02`** | **`6F 01`** | büyük olasılıkla arayüz modu: `02` komut, `01` video (**çıkarım**) |
| 9 | `70` + 94 bayt ham PPS | aynısı | baytlar eşit (12 00 00 AB 30 80 09 60 04 38 00 28 02 1C 02 1C 02 00 02 0E 00 20 03 DD 00 07 00 0C 02 77 02 8B 18 00 10 F0 07 10 20 00 06 0F 0F 33 0E 1C 2A 38 46 54 62 69 70 77 79 7B 7D 7E 02 02 22 00 2A 40 2A BE 3A FC 3A FA 3A F8 3B 38 3B 78 3B B6 4B B6 4B F4 4B F4 6C 34 84 74 00 00 00 00 00 00) |
| 10 | `F0 AA 10` | `F0 AA 10` | sayfa 0x10 |
| 11 | `B3 C6` | – | **yalnızca Razer** |
| 12 | `C3 44` | – | **yalnızca Razer** |
| 13 | `D0 84 15 50 14 14 00 35 48 1F 4F 1F 00 48 1F 50 00 00 00 05 05` | – | **yalnızca Razer** |
| 14 | `F0 AA 12` / `C7 2E 73 32 74` | – | **yalnızca Razer** |
| – | – | `B1 …` / `F0 AA 13` / `CE …` | mainline bunları burada, Razer sonda gönderiyor (içerik 144 Hz ile aynı) |
| 15 | `F0 AA 14` | `F0 AA 14` | sayfa 0x14 |
| 16 | `B2 03 33` | aynı | |
| 17 | `B4 00 33 00 00 00 3E 00 00 00 3E 00 00` | aynı | |
| 18 | `B5 00 09 09 09 09 09 09 06 01` | aynı | |
| 19 | `B9 00 00 08 09 09 09` | aynı | |
| 20 | `BC 10 00 00 06 11 09 3B 09 47 09 47 00` | aynı | |
| 21 | `BE 10 10 00 08 22 09 19 09 25 09 25 00` | aynı | |
| 22 | `F0 AA 15` / `BE 22 44 22 22 11 11 44 44 44 44 00` / `BD 22` | – | **yalnızca Razer** |
| 23 | `FF 5A 80` / `65 14` / `FA 08 08 08` | aynı | |
| 24 | `FF 5A 81` / `65 05` / `F3 0F` | aynı | |
| 25 | – | `F0 AA 00` / `FF 5A 82` / `F9 00` / `FF 51 83` / `65 04` / `F8 00` / `FF 5A 00` / `65 01` / `F4 9A` | **yalnızca mainline** (SM8550 video modu). `FF 51 83`, büyük olasılıkla `FF 5A 83` yerine yazım hatası (gözlem) |
| 26 ★ | `6C 01` | – | 120/144 Hz grubu. 60/90 Hz'de `6C 02` |
| 27 | `F0 AA 10` | | |
| 28 ★ | `B1 01 38 00 14 00 1C 00 01 66 00 14 00 14 00 01 66 00 14 05 CC 00` | (yukarıda, aynı) | 60/120 Hz: `… 00 14 01 FC 00 01 66 00 14 0D 6C 00` |
| 29 | `F0 AA 13` | | |
| 30 ★ | `CE 09 11 09 11 08 C1 07 FA 05 A4 00 3C 00 34 00 24 00 0C 00 0C 04 00 35` | (yukarıda, aynı) | ↓ tablo |
| 31 | `F0 AA 00` / `FF 5A 00` | `FF 5A 00` | |
| 32 | `11` + 120 ms | `11` + 120 ms | uykudan çık |
| 33 | `29` + 20 ms | `29` + 20 ms | ekran açık |
| 34 | (host) PPS 0x0A | `mipi_dsi_picture_parameter_set_multi` | |

★ Moda göre değişen satırlar:

| Mod | `6C` | `B1` kuyruğu | Sayfa 0x13 |
|---|---|---|---|
| 60 Hz | `02` | `… 01 FC 00 01 66 00 14 0D 6C 00` | `D3 15 C2 15 C2 15 02 13 25 0D 8A 00 90 00 7D 00 57 00 0C 00 0C 0B 00 7E` |
| 90 Hz | `02` | `… 00 14 00 01 66 00 14 05 CC 00` | `D3 0E 81 0E 81 0E 01 0C C3 09 06 00 60 00 53 00 3A 00 0C 00 0C 07 00 54` |
| 120 Hz | `01` | `… 01 FC 00 01 66 00 14 0D 6C 00` | `CE 0A E1 0A E1 0A 81 09 92 06 C5 00 48 00 3E 00 2B 00 0C 00 0C 05 00 3F` |
| 144 Hz | `01` | `… 00 14 00 01 66 00 14 05 CC 00` | `CE 09 11 09 11 08 C1 07 FA 05 A4 00 3C 00 34 00 24 00 0C 00 0C 04 00 35` |

Yorum (çıkarım): `B1` içindeki `0x01FC` = 508 (120 Hz VFP), `0x0D6C` = 3436
(60 Hz VFP), `0x0014` = 20 (144 Hz VFP), `0x05CC` = 1484 (90 Hz VFP).
`0x6C` "tam/yarım hız" grubunu seçiyor. Panel komut modunda kendi iç
zamanlayıcısıyla tazeleniyor ve frekansı bu yazmaçlar belirliyor.

### 4.2 Kapanış dizisi

| Razer | Mainline |
|---|---|
| `28` (00 parametre ile, 0 ms), HS | `28` + 20 ms |
| `10` (00 ile) + 120 ms, HS | `10` + 120 ms |

Mainline'ın kapanış dizisi Razer'ınkini kapsıyor. Yama onu olduğu gibi
kullanıyor.

### 4.3 Çalışırken mod değiştirme (`qcom,mdss-dsi-timing-switch-command`, LP)

```
6C xx          + 32 ms bekleme (0x20)
F0 AA 10
B1 …           (moda göre)
F0 AA 13
D3 … | CE …    (moda göre)
F0 AA 00
```

`drm_panel` API'si `prepare()` sırasında hangi modun seçildiğini bildirmiyor.
Bu yüzden yama şimdilik **yalnızca 144 Hz** modunu sunuyor. Bu seçim
mainline'ın test ettiği B1/CE değerleriyle aynı ve Razer'ın panel adı da
"144hz". Dört modun hepsinde piksel saati aynı olduğu için ileride çoklu mod
desteği kolay eklenebilir: ya `prepare` öncesinde seçilen mod bir köprü
(bridge) veya `atomic_enable` üzerinden alınır, ya da yukarıdaki geçiş
dizisi gönderilir. Isı veya güç sorunu olursa ilk deneme olarak 60 Hz
tablosu kullanılabilir.

## 5. Yamanın özeti

Dosya: `drivers/panel/0001-drm-panel-visionox-vtdr6130-razer-nicole.patch`.
İki dosyaya dokunuyor: `panel-visionox-vtdr6130.c` ve
`visionox,vtdr6130.yaml`.

- `struct visionox_vtdr6130_desc`: mod, besleme listesi ve sırası, isteğe
  bağlı besleme başına açılış gecikmesi, reset süreleri, DSI bayrakları, DSC
  sürümü ve dilim yüksekliği, en yüksek parlaklık, `on()` fonksiyonu.
- `"visionox,vtdr6130"` → eski değerler (davranış değişmiyor).
- `"visionox,vtdr6130-razer-nicole"` →
  - komut modu: `MIPI_DSI_MODE_NO_EOT_PACKET | MIPI_DSI_CLOCK_NON_CONTINUOUS`,
    `MIPI_DSI_MODE_VIDEO` yok;
  - `visionox_vtdr6130_nicole_on()`: §4.1'deki Razer dizisinin birebir
    kopyası (144 Hz);
  - mod 1080×2400@144: HFP/HSW/HBP 20/4/20, VFP/VSW/VBP 20/4/16, saat
    394 928 kHz, 71×158 mm;
  - DSC 1.1, dilim 540×20, 8 bpc, 8 bpp;
  - beslemeler `vddio`, `vci`, `avdd` sıralı açılıyor, vddio sonrası 20 ms;
  - reset 10/25/20 ms;
  - `max_brightness = 2047`.
- Tüm varyantlar için `drm_of_get_panel_orientation()` ve `.get_orientation`
  (DT'de `rotation` yoksa davranış değişmiyor).
- Binding: `compatible` enum'a çevrildi, `avdd-supply` ve `rotation`
  eklendi, `vdd`/`avdd` için `if/then/else` ile koşullu zorunluluk tanımlandı.

## 6. Kart DTS parçası (yapıştırmaya hazır)

Regülatör etiketleri, kart DTS'inde pm8350c RPMh LDO'ları için kullanılan
isimlere göre uyarlanmalı. Burada `vreg_l12c_1p8`, `vreg_l13c_3p0`,
`vreg_l6b_1p2` ve `vreg_l5b_0p88` varsayıldı. Gerilimler downstream'den
alındı.

```dts
/* --- kök düğüme --- */
/ {
	/* GPIO13, aktif düşük; downstream "display_panel_avdd" */
	panel_avdd: regulator-panel-avdd {
		compatible = "regulator-fixed";
		regulator-name = "panel_avdd";
		regulator-min-microvolt = <5500000>;
		regulator-max-microvolt = <5500000>;
		gpio = <&tlmm 13 GPIO_ACTIVE_LOW>;
		/* enable-active-high YOK: aktif düşük */
		startup-delay-us = <233>;
		/* ABL ekranı açık bırakıyor (splash) */
		regulator-boot-on;

		pinctrl-0 = <&panel_avdd_en>;
		pinctrl-names = "default";
	};
};

/* --- &apps_rsc altındaki pm8350c-rpmh-regulators düğümüne --- */
	vreg_l12c_1p8: ldo12 {
		regulator-name = "vreg_l12c_1p8";
		regulator-min-microvolt = <1860000>;
		regulator-max-microvolt = <1860000>;
		regulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
	};

	vreg_l13c_3p0: ldo13 {
		regulator-name = "vreg_l13c_3p0";
		regulator-min-microvolt = <3000000>;
		regulator-max-microvolt = <3000000>;
		regulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
	};

/* --- ekran --- */
&mdss {
	status = "okay";
};

&mdss_dsi0 {
	vdda-supply = <&vreg_l6b_1p2>;
	status = "okay";

	panel@0 {
		compatible = "visionox,vtdr6130-razer-nicole";
		reg = <0>;

		reset-gpios = <&tlmm 24 GPIO_ACTIVE_LOW>;

		vddio-supply = <&vreg_l12c_1p8>;
		vci-supply = <&vreg_l13c_3p0>;
		avdd-supply = <&panel_avdd>;

		rotation = <180>;

		pinctrl-0 = <&disp0_reset_n_active>, <&mdp_vsync>;
		pinctrl-1 = <&disp0_reset_n_suspend>, <&mdp_vsync>;
		pinctrl-names = "default", "sleep";

		port {
			panel0_in: endpoint {
				remote-endpoint = <&mdss_dsi0_out>;
			};
		};
	};
};

&mdss_dsi0_out {
	remote-endpoint = <&panel0_in>;
	data-lanes = <0 1 2 3>;
	qcom,te-source = "mdp_vsync_p";
};

&mdss_dsi0_phy {
	vdds-supply = <&vreg_l5b_0p88>;
	status = "okay";
};

&tlmm {
	panel_avdd_en: panel-avdd-en-state {
		pins = "gpio13";
		function = "gpio";
		drive-strength = <8>;
		bias-disable;
	};

	disp0_reset_n_active: disp0-reset-n-active-state {
		pins = "gpio24";
		function = "gpio";
		drive-strength = <8>;
		bias-disable;
	};

	disp0_reset_n_suspend: disp0-reset-n-suspend-state {
		pins = "gpio24";
		function = "gpio";
		drive-strength = <2>;
		bias-pull-down;
	};

	mdp_vsync: mdp-vsync-state {
		pins = "gpio82";
		function = "mdp_vsync";
		drive-strength = <2>;
		bias-pull-down;
	};
};
```

Gerekli çekirdek yapılandırması: `CONFIG_DRM_MSM=y|m`,
`CONFIG_DRM_MSM_DSI=y`, `CONFIG_DRM_MSM_DSI_7NM_PHY=y` (SM8350'nin
`qcom,sm8350-dsi-phy-5nm` PHY'si `dsi_phy_7nm.c` içinde),
`CONFIG_DRM_PANEL_VISIONOX_VTDR6130=m` (yama uygulanmış),
`CONFIG_BACKLIGHT_CLASS_DEVICE=y`. DPU tarafında DSC ve komut modu SM8350
için mainline'da mevcut.

> Erken açılış için not: ABL ekranı açık bırakıyor (`regulator-boot-on` ve
> proxy oylarının nedeni bu). msm DRM yüklenene kadar `simple-framebuffer`
> ile splash belleği kullanılabilir. Bu, kart DTS'ini hazırlayan ajanın
> konusu.

## 7. Cihazda doğrulanacaklar

1. **GPIO13 rayı:** aktif düşük olduğu ve panelin bu ray olmadan yanmadığı.
   `/sys/kernel/debug/gpio` üzerinden GPIO13'ün seviyesi okunmalı
   (Android'de root gerekir, Linux'ta serbest).
2. **1.2 V VDD:** ayrı bir ray olmadığı varsayımı. Panel L12C, L13C ve GPIO13
   ile yanıyorsa varsayım doğru.
3. **Reset GPIO24 kutbu** (aktif düşük) ve 10/25/20 ms sürelerinin yeterli
   olduğu.
4. **`0x6F` anlamı:** `02` ile komut modu. Görüntü gelmezse ilk deney: aynı
   dizi `6F 01` ve video modu bayraklarıyla (yani mainline varyantı).
5. **DSC:** dilim yüksekliği 20 ile görüntünün bozulmadığı. Bozulursa 40
   denenmeli (mainline'ın SM8550'de kullandığı değer). DSC sürümü 1.1
   yerine 1.2 de denenebilir.
6. **TE:** `dmesg`'de `pp done timeout` veya `vblank timeout` olmaması. TE
   kesmesi DPU içinde sayılıyor. FPS'nin 144 Hz'e oturduğu `kmscube` veya
   `drm_info` vblank zaman damgalarıyla kontrol edilmeli.
7. **Şerit hızı:** `debugfs/clk/…/disp_cc_mdss_byte0_clk` değerinin ≈106.46 MHz
   olması (851.7 Mbps / 8).
8. **Parlaklık:** `/sys/class/backlight/*/max_brightness = 2047`. 0 değerinin
   ekranı tamamen karartıp karartmadığı ve 2047'de ısı durumu.
9. **Yön:** `rotation = <180>` ile DRM bağlayıcısında "panel orientation =
   Upside Down" görünmesi ve kompozitörün görüntüyü doğru çevirmesi.
10. **Android referansı (Seviye 1, salt okuma):**
    `adb shell ls /sys/class/backlight/` ve ilgili `max_brightness` dosyası,
    `adb shell dmesg | grep -i -E "dsi|panel|vtdr"` ile seçilen zamanlama ve
    saat değerleri.
11. ESD ve mod değiştirme şimdilik yok. Uzun testlerde panel donarsa §3.7'deki
    `0x0A` okuması eklenmeli.
