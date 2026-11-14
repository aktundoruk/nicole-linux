# Güvenlik kuralları

Bu port tek bir cihaz üzerinde geliştirildi; kurallar onu kaybetmemek içindi. Betiklerdeki
ve yamalardaki "§2", "§3", "§8" atıfları bu belgenin bölümleridir. Aynı cihazda çalışan
herkes için de geçerli bir başlangıç noktasıdır.

## §2 Yazma seviyeleri ve yasaklar

**Serbest:** okuma (`fastboot getvar`, `/proc`, `/sys`, `dmesg`), `fastboot boot` ile
yalnız RAM'den açılış, yeniden başlatma, projeye ayrılmış microSD.

**Bildirerek, yalnız kendi slotumuzda:** `boot_x`, `vendor_boot_x`, `dtbo_x`,
doğrulaması kapalı `vbmeta_x`. Her yazmadan önce aynı bölümün yedeği alınır (alınamıyorsa
neden alınamadığı yazılır).

**Her seferinde ayrı karar:** öteki slotun bölümleri; `userdata`, `super`, `vendor`,
`system`, `odm`; bölüm tabloları (GPT) ve slot işaretleri; satın alma, dışarıya yayın.

**Seviye 4: hiçbir koşulda yapılmaz**

- Bu bölümlere hiçbir yoldan yazmak ya da silmek: `persist`, `modemst1`, `modemst2`,
  `fsg`, `fsc`, `xbl*`, `xbl_config*`, `abl*`, `aop*`, `tz*`, `hyp*`, `devcfg*`,
  `keymaster*`, `qupfw*`, `uefisecapp*`, `cpucp*`, `shrm*`, `storsec`, `devinfo`, `frp`,
  `misc`, `splash`, `ssd`, `ddr`, `cdt`.
- `fastboot erase`, `fastboot flashing lock`, belgelenmemiş `fastboot oem …` komutları.
- EDL / Firehose / Sahara işlemleri.
- PMIC, regülatör, şarj akımı/voltajı ya da fan için Razer'ın Android cihaz ağacındaki
  sınırların dışında değer yazmak; fanın soğutma denetimini devre dışı bırakmak (§8).
- Razer ya da Qualcomm firmware dosyalarını herhangi bir yere yüklemek veya yayınlamak.
  Firmware yalnız cihazda ve sahibinin bilgisayarında kalır; pakete ve imaja girmez.

## §3 Sıcaklık ve pil eşikleri

| Ölçü | Uyarı (kaydet, yükü azalt) | Durdur (yükü kes) |
|---|---|---|
| Pil sıcaklığı | ≥ 42 °C | ≥ 45 °C |
| CPU/GPU termal bölgeleri | ≥ 80 °C | ≥ 90 °C |
| Pil voltajı | ≤ 3,6 V | ≤ 3,45 V |
| Pil yüzdesi | ≤ %25 | ≤ %15 |

- Fan çalışmadan uzun süren CPU/GPU yük testi yapılmaz; yük testleri 10 dakikayı geçmez.
- **Kör dönem (§3.1):** pil ölçümü ve fan çalışmadan önce (ilk açılışlar) kendi Linux'unda
  oturum başına en fazla 30 dakika kalınır, yük çalıştırılmaz, tsens 75 °C'yi geçerse
  oturum kapatılır, 3,8 V altında deneme yapılmaz.
- Cihaz yanmaz bir zeminde, havalandırmalı bir yerde durur.

## §4 Durma kuralları

- Bir hedef için deneme sınırı vardır (örnek: 25 deneme ya da 8 saat, §4.5); sınırda
  durulur, durum yazılır, yöntem yeniden düşünülür.
- Şişme, koku ya da renk değişimi görülürse her şey derhal durur.

## §8 Fan, firmware, UFS ve slot kuralları

- **Fan:** düşük sıcaklıkta ve boştayken fan durabilir (Razer'ın davranışı), ama fan
  beslemeleri hep açık kalır; denetim çökerse ya da bir sensör okunamazsa fan tam hıza
  çıkar. CPU/GPU/video koruma eşikleri ve pil kuralları Razer'ınkilerdir ve her profilde
  tabandır; yalnız kasa (quiet therm) tablosu profile göre gevşeyebilir, en gevşek
  profilde de fan en geç 42 °C kasa sıcaklığında tam hızdadır.
- **Firmware:** cihazın kendi Android bölümlerinden salt okunur kopyalanır
  (`nicole-firmware-cek`). Yedeği yalnız sahibine ait, istemci tarafında şifreli bir yerde
  tutulabilir; hiçbir zaman herkese açık bir yere girmez.
- **UFS:** çekirdekteki yazma koruması (`drivers/ufs/0001-*`) varsayılan olarak açıktır;
  yazmaya yalnız açılış satırında adı geçen adres aralıklarında izin verilir. İlk yazma
  denemeleri Android'in kullanmadığı `rawdump` bölümünde yapıldı; öncesinde dahili diskin
  tamamı salt okunur yedeklendi ve doğrulandı.
- **Slot düzeni:** A slotu Linux (kökü `userdata`'da), B slotu Linux kurtarma sistemi
  (kökü `rawdump`'ta). Android'in sistem bölümleri yerinde kalır; Android'e dönüş, B'nin
  dört açılış imajını yedekten geri yazmaktır (`docs/geri-donus.md`).
  - Slot işaretleri: yalnız `boot_a` / `boot_b` GPT girdilerindeki etkin, öncelik, deneme,
    başarılı ve açılamaz bitleri, dar bir araçla (`nicole-slot`). A çalışırken B "başarılı"
    tutulur, çünkü ABL A'nın denemeleri bitince B'ye ancak öyleyse geçer
    (`HandleActiveSlotUnbootable`). Öteki LUN'lardaki bitleri ve açılış LU'sunu ABL kendisi
    değiştirir; Linux bunları hiç yazmaz.
  - Linux kendi açılış imajlarını yazar (`nicole-imaj --yaz`, geri okuyarak doğrular).
  - B, A'nın `boot_a` ve `vendor_boot_a` bölümlerini onarabilir (`nicole-a-onar`); A,
    B'nin bölümlerine yazmaz, kurtarma sistemi yalnız fastboot ile değişir.
  - `metadata`, `persist`, `misc`, `super` ve öteki Android bölümlerine yazılmaz.
