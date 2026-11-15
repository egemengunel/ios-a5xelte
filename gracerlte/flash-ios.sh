#!/bin/bash
# WRITES TO THE PHONE. Flash iOS 16 onto the Note FE from TWRP, in three confirmed, verified steps:
#   1. iOS root image -> USERDATA (ERASES Android data and internal storage)   [ios-a5xelte/tools/herolte-flash-root.py]
#   2. drop zone (GPU, audio, Wi-Fi + Murata NVRAM, network)                   [gracerlte/write-drop.sh]
#   3. BOOT <- build/boot/notefe-boot-<level>.img, read back and compared
# Never touches EFS, CPEFS, RADIO, RECOVERY, SYSTEM or VENDOR. Partitions by name only.
#
#   gracerlte/flash-ios.sh [stock|camera|max]      (default stock: get to the home screen first)
# Back to Android: write backup/boot-stock.img to BOOT, Format Data in TWRP, flash a ROM.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
R="$here"; B="$here/build"
level=${1:-stock}
BN=/dev/block/platform/155a0000.ufs/by-name
img="$B/boot/notefe-boot-$level.img"
parts=("$B"/root/root.img.gz.part*)
[[ -f $img ]] || { echo "missing $img: run gracerlte/make-boot.sh" >&2; exit 1; }
[[ -f ${parts[0]} ]] || { echo "missing iOS root image parts" >&2; exit 1; }
(cd "$B/root" && shasum -a 256 -c SHA256SUMS >/dev/null) || { echo "root image checksum mismatch" >&2; exit 1; }

ask() { read -r -p "$1 Type yes to continue: " a; [[ $a == yes ]] || { echo "stopped"; exit 1; }; }

[[ "$(adb get-state 2>/dev/null)" == recovery ]] || { echo "phone not in TWRP over adb" >&2; exit 1; }
model=$(adb shell getprop ro.boot.bootloader | tr -d '\r')
[[ $model == N935F* ]] || { echo "unexpected bootloader '$model' (want N935F...)" >&2; exit 1; }
adb shell 'mount' | grep -q ' /data ' && adb shell umount /data 2>/dev/null || true
if adb shell 'mount' | grep -q ' /data '; then echo "/data is still mounted: unmount it in TWRP (Mount menu)" >&2; exit 1; fi
echo "Phone: $model, TWRP, /data unmounted. RAM level: $level"

ask "STEP 1/3: write the iOS root into USERDATA. This ERASES Android data and internal storage."
python3 "$R/tools/herolte-flash-root.py" adb "${parts[@]}" --state "$B/root/flash.state"

ask "STEP 2/3: write the drop zone (GPU, audio, Wi-Fi) at the end of USERDATA."
"$here/gracerlte/write-drop.sh"

ask "STEP 3/3: write the Note FE iOS BOOT ($level)."
size=$(stat -f %z "$img")
adb push "$img" /tmp/notefe-boot.img
adb shell "dd if=/tmp/notefe-boot.img of=$BN/BOOT bs=1048576 conv=fsync && rm /tmp/notefe-boot.img"
phone=$(adb shell "head -c $size $BN/BOOT | sha256sum" | awk '{print $1}')
mac=$(shasum -a 256 "$img" | awk '{print $1}')
[[ $phone == "$mac" ]] || { echo "BOOT read-back MISMATCH ($phone vs $mac): restore backup/boot-stock.img!" >&2; exit 1; }
echo "BOOT verified ($mac)."
echo "All written. Reboot with: adb reboot   (first boot takes several minutes on the Apple logo)"
