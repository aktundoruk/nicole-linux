#!/bin/bash
# Kaynak depolarını yer kazanmak için sparse/shallow olarak çeker.
set -e
cd "$(dirname "$0")"

clone_sparse() { # url branch dir paths...
  local url=$1 br=$2 dir=$3; shift 3
  if [ ! -d "$dir/.git" ]; then
    git clone --quiet --depth 1 --filter=blob:none --sparse -b "$br" "$url" "$dir"
  fi
  git -C "$dir" sparse-checkout set "$@"
}

clone_sparse https://github.com/LineageOS/android_kernel_razer_sg8175p lineage-23.2 razer-kernel \
  arch/arm64/boot/dts/vendor arch/arm64/configs \
  drivers/input/touchscreen/focaltech_touch_spi drivers/misc/haptic_nv \
  drivers/thermal/qcom drivers/power/supply drivers/usb/misc drivers/usb/typec/ucsi drivers/soc/qcom \
  techpack/display/msm/dsi include/dt-bindings drivers/misc

git clone --quiet --depth 1 -b lineage-23.2 https://github.com/LineageOS/android_device_razer_nicole lineage-device 2>/dev/null || true

clone_sparse https://github.com/torvalds/linux master linux-mainline \
  arch/arm64/boot/dts/qcom include/dt-bindings scripts/dtc/include-prefixes \
  Documentation/devicetree/bindings/display/panel Documentation/devicetree/bindings/input \
  Documentation/devicetree/bindings/hwmon Documentation/devicetree/bindings/usb \
  Documentation/devicetree/bindings/soc/qcom Documentation/devicetree/bindings/power \
  drivers/gpu/drm/panel drivers/input/touchscreen drivers/hwmon drivers/soc/qcom \
  drivers/power/supply drivers/usb/typec/mux drivers/net/wireless/ath/ath11k arch/arm64/configs \
  sound/soc/codecs sound/soc/qcom

clone_sparse https://gitlab.postmarketos.org/postmarketOS/pmaports.git main pmaports \
  device/testing/device-sony-pdx215 device/testing/linux-sony-pdx215 device/testing/firmware-sony-pdx215

echo BITTI; du -sh */ 2>/dev/null
