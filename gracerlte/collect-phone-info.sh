#!/bin/bash
# Stage 0: read-only survey of the Note FE over adb. Run with the phone in TWRP (best) or in rooted Android.
# Writes nothing to the phone except a temporary copy in /tmp of the live device tree. Results go to phone-info/.
#
#   gracerlte/collect-phone-info.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/phone-info"
mkdir -p "$out"
BN=/dev/block/platform/155a0000.ufs/by-name

adb get-state >/dev/null 2>&1 || { echo "No phone over adb. Boot TWRP (Power+VolDown+Home, then Power+VolUp+Home) and plug it in."; exit 1; }

# TWRP runs adb as root; Android needs su.
if [ "$(adb shell id -u 2>/dev/null | tr -d '\r')" = 0 ]; then SU() { adb shell "$1"; }; mode=twrp-or-root
else SU() { adb shell "su -c '$1'"; }; mode=android-su; fi
echo "adb mode: $mode"

run() { local f="$1"; shift; echo "== $f"; SU "$*" > "$out/$f" 2>&1; head -c 2000 "$out/$f"; echo; }

run model.txt          'getprop ro.product.model; getprop ro.product.device; getprop ro.boot.bootloader; getprop ro.bootloader; getprop ro.build.version.release'
run partitions.txt     "ls -l $BN/"
run partition-sizes.txt "for p in BOOT RECOVERY SYSTEM USERDATA CACHE EFS RADIO VENDOR; do [ -e $BN/\$p ] && echo \"\$p \$(blockdev --getsize64 $BN/\$p)\"; done"
run cmdline.txt        'cat /proc/cmdline'
run iomem.txt          'cat /proc/iomem'
run meminfo.txt        'head -3 /proc/meminfo'
run touch.txt          'for d in /sys/bus/i2c/devices/*; do n=$(cat $d/name 2>/dev/null); [ -n "$n" ] && echo "$(basename $d) $n"; done'
run wifi-files.txt     'ls -l /vendor/etc/wifi /system/etc/wifi /system/vendor/etc/wifi 2>/dev/null; ls /system_root/system/etc/wifi 2>/dev/null'
run fb.txt             'dmesg 2>/dev/null | grep -iE "fb_handover|framebuffer|decon.*(0x|addr)|s6e3|panel|lcd_info" | head -40'

echo "== live device tree"
SU 'cat /sys/firmware/fdt > /tmp/live.dtb && chmod 644 /tmp/live.dtb' && adb pull /tmp/live.dtb "$out/live.dtb" && SU 'rm /tmp/live.dtb'
ls -l "$out"

if [ -s "$out/live.dtb" ]; then
    for level in stock camera max; do
        python3 "$here/gracerlte/notefe-ram-banks.py" --show --level "$level" --fdt "$out/live.dtb" \
            --cmdline "$out/cmdline.txt" > "$out/ram-$level.txt" 2>&1
        tail -1 "$out/ram-$level.txt" | sed "s/^/RAM $level: /"
    done
fi
echo "Done. Read phone-info/*.txt; touch.txt should list sec_ts (supported) and not an Atmel/mxt chip."
