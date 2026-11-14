# nicole-linux: mainline Linux on the Razer Edge

A port of mainline Linux and postmarketOS to the **Razer Edge Wi-Fi** handheld
(codename *nicole*, Qualcomm SM8350 / Snapdragon G3x Gen 1). The Razer Edge 5G uses
the same board (LineageOS lists both as *nicole*), so most of this should apply to it
too, but it was only tested on the Wi-Fi model.

> **Not affiliated with, endorsed by or supported by Razer Inc.** "Razer" and
> "Razer Edge" are trademarks of their owner and are used here only to say which
> device this is for. Unlocking the bootloader may void your warranty, and flashing
> the wrong thing can leave the device unusable. You do this at your own risk.

## Status

Kernel: mainline v7.3-rc6 plus the patches in `drivers/` (see below).

| Works | Notes |
|---|---|
| Display | Visionox VTDR6130, DSI with DSC, 1080x2400 at 144 Hz; video mode (`nicole_video=1`) or the vendor command mode |
| Touch | FocalTech FT3658S over SPI (own driver, `drivers/touchscreen/`) |
| GPU | Adreno 660 (msm/freedreno, Vulkan) |
| Wi-Fi, Bluetooth | WCN6851 (ath11k), firmware from the device itself |
| Audio | Speakers (with a hard volume ceiling, there is no speaker protection) and microphones via UCM |
| USB-C | Device mode (USB networking), host mode, DisplayPort alt mode |
| Power | Battery and charging via pmic_glink, fan control from the vendor's thermal tables, suspend to idle (s2idle) at about 35 mA |
| Sensors | Accelerometer, light, proximity through the sensor DSP (SLPI, hexagonrpcd + libssc) |
| Haptics | Awinic AW8622x (own driver, `drivers/haptics/`) |
| Front camera | Hi-556 through CAMSS, 2592x1944 RAW at 30 fps (libcamera with the patches in `pmaports/libcamera`) |
| Video decode | iris |

Not done or not verified: headset audio path, rear cameras, the SoC's deepest sleep
state (CXSD is never reached yet), modem (the Wi-Fi model has none).

## Layout

| Path | What |
|---|---|
| `drivers/` | Kernel patches by subsystem, the touchscreen and haptics drivers. Applied in path order by `scripts/build/build-kernel.sh`. |
| `dts/` | The board device tree `sm8350-razer-nicole.dts` and the camera part. |
| `pmaports/` | postmarketOS packages: kernel, device package (fan, audio, sensors, sleep, slot and image tools), firmware recipe, libcamera fork. |
| `scripts/` | Build (VM setup, kernel, boot images, packages), first-day inventory and backup (`faz0/`), lab and test tools. |
| `scripts/lab/` | The author's lab tools for this one device. Several of them write to the phone's storage (boot partitions, the GPT, userdata) behind guards and opt-in variables. They are a record of how the port was done, not install instructions; read a script before running it. |
| `docs/` | Analysis and plans (mostly in Turkish): hardware inventory, boot plan, panel and touch analysis, firmware list, rollback. |

## Building

1. A Linux build environment. On macOS, `scripts/build/lima-razer.yaml` describes an
   Ubuntu arm64 VM (Lima, Apple Silicon, native arm64 builds); `scripts/build/vm-setup.sh`
   installs the toolchain and pmbootstrap inside it.
2. `scripts/build/build-kernel.sh --tag v7.3-rc6 --export-config` applies `drivers/` and
   `dts/` to a clean mainline tree, builds it and exports the combined patch and config
   into `pmaports/linux-razer-nicole/`.
3. `scripts/build/paket-derle.sh` builds the packages with pmbootstrap.
4. **Firmware is never part of this repository.** It is proprietary (Razer, Qualcomm). The
   device package's `nicole-firmware-cek` copies it from the phone's own Android
   partitions, opened read-only; `pmaports/firmware-razer-nicole` packages a local dump.

## Safety design

The port was developed on a single device, so not losing it mattered more than speed
(the rules: `docs/guvenlik-kurallari.md`, in Turkish):

- A/B slots: slot A boots Linux, slot B holds a Linux rescue system; a kernel that fails
  to boot uses up A's tries and the bootloader falls back to B (`nicole-slot`, `nicole-a-onar`).
- Kernel updates are written from the phone itself to its own boot partitions only, and
  read back (`nicole-imaj --yaz`, `--geri`).
- A local UFS patch refuses writes outside the ranges given on the kernel command line,
  so nothing touches the bootloader, firmware or calibration partitions by accident.
- An initramfs watchdog (`nicole-bekci`) returns to fastboot instead of hanging.

## Upstream

Fixes that belong upstream are being sent or are already on the lists. Some patches here
are other people's, carried for testing with their authorship kept (the originals, with
their sign-offs, are on the mailing lists):
Xi Zhang (DPU command mode cleanup), Praveen Talari (qcom-geni serial),
Vladimir Zapolskiy (SM8350 camera clock controller), Dmitry Baryshkov (WCN6851).

## Licenses

| What | License |
|---|---|
| Kernel patches, drivers, device tree (`drivers/`, `dts/`, `pmaports/linux-razer-nicole/`) | GPL-2.0-only (`LICENSES/GPL-2.0.txt`) |
| Device tree binding schemas (`*.yaml` under `drivers/`) | GPL-2.0-only OR BSD-2-Clause, the kernel's rule for bindings (`LICENSES/BSD-2-Clause.txt`) |
| libcamera patches (`pmaports/libcamera/`) | LGPL-2.1-or-later, as libcamera (`LICENSES/LGPL-2.1.txt`) |
| libcamera tuning files (`pmaports/libcamera/*.yaml`) | CC0-1.0, as libcamera's own tuning files (`LICENSES/CC0-1.0.txt`) |
| Scripts and the other package recipes | MIT (`LICENSES/MIT.txt`) |
| The lab kernel module `scripts/lab/modul/uyku-iz/` | GPL-2.0 (`LICENSES/GPL-2.0.txt`), as a kernel module |
| Documents (`docs/`, this README) | CC BY 4.0 (`LICENSES/CC-BY-4.0.txt`) |

Patches by other authors keep their own license. Each file's SPDX tag, where it has one,
is the authority.

## How this was made

Most of the code, the analysis and the documents were written with an AI coding
assistant (Claude, Anthropic), working on the device over SSH and in a build VM. The
author reviewed the work, made the decisions and tested everything on the phone; he
takes responsibility for it.

## Türkçe özet

Razer Edge Wi‑Fi (nicole, SM8350) için mainline Linux ve postmarketOS portu. Ekran,
dokunmatik, GPU, Wi‑Fi, Bluetooth, ses, USB‑C (DisplayPort dahil), fan, pil, sensörler,
titreşim, ön kamera ve uyku çalışıyor. Firmware bu depoda yok: cihazın kendi Android
bölümlerinden kopyalanıyor. Razer ile bağlantısı yoktur; kilidi açmak garantiyi
düşürebilir, risk kullanıcıya aittir. Belgelerin çoğu Türkçedir.
