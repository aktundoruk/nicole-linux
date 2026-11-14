# usage: agc-dene.sh GAIN STEP EXP AGAIN -> frame exposure gain
mkdir -p /tmp/ayar/simple
sed -e "s/proportionalGain: .*/proportionalGain: $1/" -e "s/maxStep: .*/maxStep: $2/" /usr/share/libcamera/ipa/simple/hi556.yaml > /tmp/ayar/simple/hi556.yaml
doas v4l2-ctl -d /dev/v4l-subdev28 --set-ctrl exposure=$3,analogue_gain=$4
LIBCAMERA_IPA_CONFIG_PATH=/tmp/ayar LIBCAMERA_LOG_LEVELS=IPASoftExposure:0 cam -c1 -s pixelformat=XRGB8888,width=1296,height=972 --capture=240 --metadata 2>/tmp/agc-log.txt \
 | awk '/seq:/{s=$0; sub(/.*seq: /,"",s); sub(/ .*/,"",s)} /ExposureTime =/{e=$NF} /AnalogueGain =/{g=$NF; print s+0, e, g}'
grep -m1 -o "proportionalGain.*" /tmp/agc-log.txt >&2
