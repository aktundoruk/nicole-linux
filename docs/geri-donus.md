# Geri Dönüş Planı

> Durum: **taslak.** Cihaza özgü dosya adları, yapı numaraları ve sağlamalar M0'da (Faz 0) doldurulacak.

## Neden güvendeyiz

- Bütün açılış denemeleri `fastboot boot` ile yapılır. İmaj RAM'e yüklenir, hiçbir bölüm değişmez. Cihaz yeniden başladığında B slotundaki Android açılır.
- Seviye 2 yazımları (onaylanırsa) yalnızca **A slotunda** yapılır. B slotu (Android) dokunulmadan kalır. Slot düzeni 24 Ekim 2026'da aynalandı: cihaz ilk bağlandığında Android B'den açılıyordu.
- Linux tarafında dahili UFS, Faz 3 onayına kadar DTS'de kapalıdır. Kendi çekirdeğimiz dahili depolamayı göremez bile.
- Bootloader açık kaldığı sürece fastboot her zaman erişilebilir. Kilitlemek (`fastboot flashing lock`) sözleşmede yasak; özel bir yazılım yüklüyken kilitlemek cihazı açılamaz hâle getirebilir.

## Senaryolar

| Durum | Belirti | Çözüm |
|---|---|---|
| Deneme çekirdeği donuyor | Ekran siyah veya takılı, USB ağı yok | Zorla yeniden başlatma (Güç + Ses Kısma, süre M0'da ölçülecek) → Ses Kısma basılı → fastboot. Önce kendiliğinden kurtulma beklenir (watchdog/panik → Android → `adb reboot bootloader`); olmazsa zorla yeniden başlatma elle yapılır |
| Cihaz B slotundan (Android) açılmıyor | Logo döngüsü | fastboot → `fastboot --set-active=b` (Seviye 2) → gerekirse `yedek/` altındaki `boot_b`, `vendor_boot_b`, `dtbo_b`, `vbmeta_b` imajları **Kullanıcı onayıyla** (Seviye 3) geri yazılır |
| A slotu (bizim) bozuldu | A'dan açılmıyor | Önemli değil: aktif slot B'ye alınır, A'ya yedekten geri yazılır |
| `persist` zarar gördü | Wi‑Fi MAC, sensörler, seri numarası bozuk | `yedek/bolumler-*/persist.img` Kullanıcı onayıyla geri yazılır. **Yalnız bu senaryo için** yasak bir bölüme dokunulur ve bunu Kullanıcı yapar |
| Tamamen stock'a dönüş | — | Aşağıda "Android'e dönüş yolu" |

## M0'da doldurulacak

- [x] `ro.build.fingerprint`: `Razer/Nicole_EEA/Razer-Edge-WiFi:12/SKQ1.211103.001/171:user/release-keys` (bootloader `version-bootloader` boş döndü)
- [x] Aktif slot ve iki slotun içerikleri: Android B'de, Linux A'da. `tam-yedek-dogrula.py` karşılaştırması (`yedek/tam-20261104/dogrulama.txt`): 27 çiftin 6'sı aynı, 21'i farklı. Örneğin `tz` ve `xbl` çiftlerinde boy aynı, sürüm dizgeleri aynı, yalnız 1636 ve 1786 bayt farklı; `abl` çiftinde 24694 bayt. Yani **slotlar birbirinin kopyası değil**, A'nın zinciri ayrı bir yedek olarak saklanmalı
- [x] Bölüm yedeklerinin konumu ve SHA256 listesi: `yedek/tam-20261104/` (6,3 GB sıkışık, 121 GB ham), `SHA256SUMS` (parçalar), `bolum-sha256.txt` (86 bölüm). Yedeği en az iki ayrı diskte tutun.
- [x] Zorla yeniden başlatma: yalnız Güç, basılı **12,3-12,4 sn** (5 Kasım, Linux'ta ölçüldü, 3 ölçüm). Ekran kapanınca bırak: ilk turda `boot_a` denemesi iki düştü ve RTC sıfırlandı, ağ yoksa saat bundan geri gider; hemen bırakılması istenen iki turda ikisi de olmadı (neden kesin değil). Fastboot için Güç + Ses Kısma, süresi ölçülmedi.
- [ ] Stock'a dönüş için resmî kaynak (varsa) veya LineageOS yolu

## 8 Kasım 2026'dan beri: B slotu Linux kurtarma

- **A:** Linux, kök `userdata`'da. **B:** Linux kurtarma, kök `rawdump`'ta; `userdata`'ya yazabilir, A'yı onarmak için.
- **A açılmıyorsa:** 7 başarısız denemeden sonra ABL kendiliğinden B'yi açar. Ya da fastboot'ta `--set-active=b`. B'den `userdata` bağlanır, onarılır, A'nın imajı yeniden yazılır (`scripts/lab/faz4-slot-yaz.sh a`).
- **Çekirdek güncellemesi (device r27'den beri, Mac'siz):** A'da `doas apk upgrade`, `doas nicole-imaj --yaz`, yeniden başlat. Bölümlerdeki önceki imajlar `/var/lib/nicole-imaj/onceki/`'de.
  - Yeni çekirdek açılıyor ama bir şey bozuksa: `doas nicole-imaj --geri`, yeniden başlat.
  - Kök bulunamazsa `nicole-bekci` (A'da `nicole.bekci.yeniden`) 180 sn sonra yeniden başlatır, panik `panic=30` ile yeniden başlatır. Her başlangıç bir deneme; yedinci başarısız açılıştan sonra B açılır (yaklaşık 25 dk). B açıldığında (telefonun terminalinden ya da SSH ile): `doas nicole-a-onar durum` A'nın ne tuttuğunu gösterir; `doas nicole-a-onar geri` A'nın güncellemeden önceki imajlarını yazar; `doas nicole-a-onar kabuk` A'nın içine girer (apk ile eski çekirdek, mkinitfs), ardından `nicole-a-onar yaz`. **A'ya dönüş, Mac'siz (device r29):** `doas nicole-slot gec a`, yeniden başlat. ABL B'yi bırakıp A'ya kendisi geçer (bir soğuk yeniden başlatma daha). A'da 3 dk sonra `nicole-slot` B'yi yeniden hazır yapar.
- **Kurtarmaya bilerek geçmek:** A'da `doas nicole-slot gec b`, yeniden başlat.
- **Neden çalışıyor:** ABL denemesi biten slottan diğerine yalnız o "başarılı" işaretliyse geçer (abl kaynağı, `HandleActiveSlotUnbootable`). A çalışırken `nicole-slot tazele` B'yi başarılı tutar. Bu bit yoksa telefon fastboot'ta kalır: o zaman Mac'ten `--set-active`.
- **Android'e geri dönüş (denenmedi):**
  1. `boot_b`, `vendor_boot_b`, `dtbo_b`, `vbmeta_b`'yi yedekten geri yaz. `boot_b.img` ve `vbmeta_b.img` `yedek/tam-20261104/bolumler/` içinde; `vendor_boot_b` (`sde48`) ve `dtbo_b` (`sde40`) `sde.img.zst`'den, `bolum-sha256.txt` ile doğrulanarak çıkarılır.
  2. `--set-active=b`.
  3. Android `userdata`'yı biçimlendirip temiz açılır; Linux'un A'daki verisi gider.

## Android'e dönüş yolu (araştırma, 4 Kasım 2026; hiçbiri denenmedi)

- **Razer fabrika imajı yayınlamıyor.** [Geliştirici sayfası](https://developer.razer.com/?p=179) yalnız Phone 1 ve 2'yi listeliyor. Wi-Fi modeli için EDL imajı da bulunamadı (bulunan EDL paketi 5G modeli `nicolelte` için).
- **Topluluğun bulduğu tam OTA:** [Google sunucusunda 1,93 GB, Aralık 2024](https://android.googleapis.com/packages/ota-api/package/07926a5297a8b020424230d5486ef452f666647f.zip). İndirilmedi, içi görülmedi. [GSI rehberi](https://github.com/gogopowerjackets/razer-edge-gsi) bunu kurtarmadan `adb sideload` ile yüklüyor, ardından veriyi siliyor.
- **Demek ki birinci dayanak kendi yedeğimiz** (`yedek/tam-*`). Bölümler geri yazılabilir, ama RPMB yedeklenemez.
- **Veri bölümünün geri yüklemesi güvence değil.** Yedekten sonra Android açılırsa ya da yama seviyesi değişirse anahtarlar yedekle uyuşmayabilir; Android'in anahtar deposu eskiyi siler. Yedeği aldıktan sonra Android'i açmamak en temiz durum. Sistem bölümleri bundan etkilenmez, en kötü durumda veri silinip Android temiz açılır. Bu öğrenilen bir bilgi, bu cihazda denenmedi.

## Slot işaretleri

- Bitler `boot_x` GPT girdisinde: öncelik 48-49, etkin 50, deneme 51-53, başarılı 54, açılamaz 55. Başarılı işaretli slotta ABL deneme düşmez ([CLO kaynağı](https://git.codelinaro.org/clo/le/abl/tianocore/edk2/-/raw/1bccaa9321815ea6b5f10afdf4d4d6a14fe10ac1/QcomModulePkg/Library/BootLib/PartitionTableUpdate.c); Razer'ın ABL'si kapalı, davranış uyuyor ama kanıtlanmadı).
- **`qbootctl -s` kullanılmaz:** [sorun #4](https://github.com/linux-msm/qbootctl/issues/4) birkaç cihazda EDL gerektiren açılmama bildiriyor, nedeni bilinmiyor. `-m` A/B bölümlerinin hepsinde bit 54'ü iki GPT kopyasına ve birden çok LU'ya yazıyor. Yalnız `boot_a` girdisini değiştiren dar bir araç daha az dokunur. Bu yazma Kullanıcı onayı ister.
