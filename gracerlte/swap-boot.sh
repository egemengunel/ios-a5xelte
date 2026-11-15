#!/bin/bash
# WRITES TO THE PHONE (BOOT only): swap the BOOT image from TWRP, read back and compare. iOS itself stays installed.
#   gracerlte/swap-boot.sh build/boot/notefe-boot-max.img        then: adb reboot
#   gracerlte/swap-boot.sh backup/boot-stock.img                 (Android's BOOT back)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
img=${1:?usage: swap-boot.sh IMAGE}
[[ -f $img ]] || img="$here/$1"
[[ -f $img ]] || { echo "no such image: $1" >&2; exit 1; }
BN=/dev/block/platform/155a0000.ufs/by-name
[[ "$(adb get-state 2>/dev/null)" == recovery ]] || { echo "phone not in TWRP over adb" >&2; exit 1; }
[[ "$(adb shell getprop ro.boot.bootloader | tr -d '\r')" == N935F* ]] || { echo "not the SM-N935F" >&2; exit 1; }
size=$(stat -f %z "$img")
(( size <= 41943040 )) || { echo "image larger than BOOT" >&2; exit 1; }
adb push "$img" /tmp/swap-boot.img >/dev/null
adb shell "dd if=/tmp/swap-boot.img of=$BN/BOOT bs=1048576 conv=fsync 2>/dev/null; rm /tmp/swap-boot.img"
phone=$(adb shell "head -c $size $BN/BOOT | sha256sum" | awk '{print $1}')
mac=$(shasum -a 256 "$img" | awk '{print $1}')
[[ $phone == "$mac" ]] || { echo "BOOT read-back MISMATCH: write backup/boot-stock.img or retry!" >&2; exit 1; }
echo "BOOT = $(basename "$img") verified ($mac)"
