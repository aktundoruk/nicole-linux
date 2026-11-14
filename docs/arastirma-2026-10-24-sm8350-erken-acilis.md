# Araştırma: SM8350'de ABL devrinden hemen sonra sıfırlanma (24 Ekim 2026)

> Arka plan araştırmacısının raporunun özeti. Kaynak bağlantıları rapordan aynen alındı; "çıkarım" diye işaretlenenler kaynaklı değil.

## Bulgular
- Razer Edge / G3x için kamuya açık mainline notu bulunamadı. Çalışan en yakın örnekler: Sony sagami (pdx215), OnePlus 9/9 Pro (lemonade/lemonadep), SM8350 HDK. Hepsi aynı ABL akışını kullanıyor: Image.gz + eklenmiş DTB, header v1, 2 bayt sıfır dtbo, msm-id yok. Yani hipervizör tek başına engel değil.
- Linaro: "some production devices don't boot when using slot 'a'" — <https://www.linaro.org/blog/let-s-boot-the-mainline-linux-kernel-on-qualcomm-devices/>. (Bizde A'nın sorunu `vbmeta_a`ymış; boş vbmeta ile çözüldü.)
- OnePlus 9 ilk mainline denemesi: "figure out why the device crashes when initialising tlmm or RPMh regulators" — gitlab.com/sm8350-mainline/linux commit 2640aa11. Her SM8350 kartının kendi `gpio-reserved-ranges` listesi var (mtp/hdk `<52 8>`, sagami `<44 4>`, lemonade `<52 8>`).
- Sony 7.2 yapılandırmasından farklarımız: `CONFIG_QCOM_TZMEM_MODE_SHMBRIDGE=y` (Sony: GENERIC), `CONFIG_KVM=y` (Sony: kapalı). SHM bridge bazı Qualcomm SoC'lerde sıfırlamaya yol açtığı için kara listede (sdm845, sm7150, sm8150 …): <https://github.com/torvalds/linux/blob/master/drivers/firmware/qcom/qcom_tzmem.c>, <https://lkml.iu.edu/hypermail/linux/kernel/2410.1/09951.html>.
- Konrad'ın sagami yaması: 2 bayt sıfır dtbo (silinmiş bölümün de overlay edildiği için), v3+ için `vendor_boot`'u boşaltma; v2'de "your device is corrupted" — <https://lkml.iu.edu/hypermail/linux/kernel/2111.1/06489.html>, /07236.html.
- Kopyalanabilecek kaynaklar: pmaports `linux-sony-pdx215` (7.2, linux `8d3ae59288f1`), pmaports v25.12 `device-oneplus-lemonade(p)` (cmdline `fw_devlink=permissive clk_ignore_unused pd_ignore_unused`), gitlab.com/sm8350-mainline/linux `ffb1b0db` (`sm8350-oneplus-common.dtsi`: gpio-reserved `<52 8>`, ramoops 0xe9700000, framebuffer saatleri).
- UART'sız erken açılış ayıklama: simplefb'ye initcall seviyesine göre renk şeritleri boyayan küçük sürücü; framebuffer earlycon yaması (LKML 2212.2/04336, birleştirilmemiş); ramoops (bir sonraki çalışan Linux açılışında okunur); Mu-Qcom UEFI (venus hedefi; UFS'e dokunduğu için sözleşme dışı).
- Bu ABL'de günlük veya RAM dökümü veren `fastboot oem` komutu yok (FastbootCmds.c: yalnız charger-screen, off-mode-charge, select-display-panel, device-info, display-cmdline).

## Önerilen sıra (rapordan, bugünkü bulgulara göre düzenlendi)
1. Hipervizör watchdog'u: canlı Android DT'de `/hypervisor/qcom,hh-watchdog` var → çekirdek açılınca bu watchdog beslenmezse sıfırlanma olabilir (mainline'da Gunyah watchdog sürücüsü araştırılacak).
2. Çekirdek yapılandırması: `# CONFIG_QCOM_TZMEM_MODE_SHMBRIDGE is not set`, `# CONFIG_KVM is not set`.
3. Asgari DTB ile ikiye bölme: apps_rsc regülatörlerini, stdout-path'i, uart2/pcie0/sdhc_2/QUP/remoteproc'u kapat; framebuffer'da yalnız iki GCC AXI saati.
4. Değişken azaltan cmdline: `nokaslr cpuidle.off=1 fw_devlink=permissive`.
