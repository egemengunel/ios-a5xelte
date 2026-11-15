#!/bin/bash
# WRITES TO THE PHONE: puts the drop-zone package (GPU libraries, audio plug-in, Wi-Fi firmware + Murata NVRAM,
# network, settings) into the last 128 MiB of USERDATA, just below the kernel log, with read-back verification
# (ios-a5xelte/tools/herolte-drop.py). Run in TWRP with /data UNMOUNTED, after the iOS root is flashed.
#
#   gracerlte/write-drop.sh [app=Foo.ipa ...]
#   BOT=1 [QUICK=1] [BT=N] gracerlte/write-drop.sh   the test program (QUICK=1: feature tests only, no app cycle) is gracerlte/bot (build/mesa/notefe-bot: opens apps, swipes; needs
#                                   herobot=1 on the boot line), with gracerlte/bot/bot.plan as bot.plan if present
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
D="$here/build/drop"; M="$here/build/mesa"; R="$here"
for f in "$D/wifi/fw.bin" "$D/wifi/clm.blob" "$D/wifi/nvram.txt" "$M/hero-run" "$M/lib/libhakiosgl.dylib"; do
    [[ -s $f ]] || { echo "missing $f" >&2; exit 1; }
done
wifi=(wifi/fw.bin="$D/wifi/fw.bin" wifi/clm.blob="$D/wifi/clm.blob" wifi/nvram.txt="$D/wifi/nvram.txt")
if [[ -s $D/wifi/network.txt ]]; then wifi+=(wifi/network.txt="$D/wifi/network.txt")
else echo "note: no build/drop/wifi/network.txt (run gracerlte/set-wifi.sh); Wi-Fi will start but join nothing"; fi
# Note FE extras (kernel patch 0404): the privacy database with the Photos grants (gracerlte/make-tcc.sh) and launchd's job
# list without the refused jobs (gracerlte/make-launchd.sh), if built.
extra=()
T="$D/tcc"
if [[ -s $T/TCC.db ]]; then
    extra+=(/private/var/mobile/Library/TCC/TCC.db="$T/TCC.db" /private/var/mobile/Library/TCC/TCC.db-wal="$T/TCC.db-wal"
            /private/var/mobile/Library/TCC/TCC.db-shm="$T/TCC.db-shm")
    echo "with TCC.db (Photos grants)"
fi
LD="$D/launchd${LAUNCHD:+-$LAUNCHD}"     # LAUNCHD=bt: the variant with bluetoothd kept (gracerlte/make-launchd.sh OUT=...)
# Note FE: WALLPAPER=1 adds the iPhone 8-size collection wallpapers (gracerlte/make-wallpapers.py -> build/drop/wallpaper)
if [[ ${WALLPAPER:-0} == 1 && -d $D/wallpaper ]]; then
    while IFS= read -r f; do
        extra+=("/${f#$D/wallpaper/}=$f")
    done < <(find "$D/wallpaper" -type f)
    echo "with the 375w-667h@2x wallpapers ($(find "$D/wallpaper" -type f | wc -l | tr -d ' ') files)"
fi
if [[ -s $LD/launchd.plist ]]; then
    plutil -lint "$LD/launchd.plist" >/dev/null
    extra+=(/System/Library/xpc/launchd.plist="$LD/launchd.plist")
    [[ -n ${LAUNCHD:-} ]] && echo "launchd variant: $LAUNCHD"
    echo "with launchd.plist (refused jobs removed)"
fi
test_prog="$M/eagl_ca_test"
# MESA=cache: the Mesa rebuilt with its disk shader cache (gracerlte/mesa/build-mesa-cache.sh), else upstream's.
osmesa="$M/lib/libOSMesa.8.dylib"
if [[ ${MESA:-} == cache ]]; then
    osmesa="$here/build/mesa-cache/lib/libOSMesa.8.dylib"
    [[ -s $osmesa ]] || { echo "no $osmesa" >&2; exit 1; }
    echo "Mesa: shader-cache build"
fi
if [[ ${BOT:-0} == 1 ]]; then
    test_prog="$M/notefe-bot"
    [[ -s $test_prog ]] || { echo "no $test_prog: run gracerlte/bot/build.sh" >&2; exit 1; }
    [[ -s $here/gracerlte/bot/bot.plan ]] && extra+=(bot.plan="$here/gracerlte/bot/bot.plan")
    # QUICK=1: feature tests only, no app cycle, back to TWRP in ~1 min. Written as 1 or 0 on every bot run (the drop
    # zone never deletes files, so a lone flag file would stay behind).
    echo "${QUICK:-0}" > "$here/build/bot.quick"; extra+=(bot.quick="$here/build/bot.quick")
    [[ ${QUICK:-0} == 1 ]] && echo "bot: quick mode"
    echo "${STAY:-0}" > "$here/build/bot.stay"; extra+=(bot.stay="$here/build/bot.stay")   # STAY=1: no TWRP at the end
    echo "${CCTEST:-0}" > "$here/build/cc.test"; extra+=(cc.test="$here/build/cc.test")      # CCTEST=N: Control Center opens
    echo "${CCLATE:-0}" > "$here/build/cc.late"; extra+=(cc.late="$here/build/cc.late")      # CCLATE=1: second pass 150 s on
    echo "${CAMWAIT:-15}" > "$here/build/cam.wait"; extra+=(cam.wait="$here/build/cam.wait")   # CAMWAIT=s: Camera app time
    # Note FE 0433: BT=N, the Bluetooth level the bot runs (kern.notefe_bt); always written, 2 (read only) by default
    echo "${BT:-2}" > "$here/build/bt.level"; extra+=(bt.level="$here/build/bt.level"); echo "bluetooth level ${BT:-2}"
    if [[ ${BT:-2} -ge 7 ]]; then   # 7, 8: the chip patch
        hcd="$here/build/bt/bcm4359C0_murata.hcd"      # the phone's own patch (VENDOR firmware/), private
        [[ -s $hcd ]] && extra+=(bt-murata.hcd="$hcd") && echo "with the Bluetooth patch"
    fi
    # Note FE 0437: CAM=N camera stage (0 none), WDTTEST=1 the fail-safe's one-shot test; both always written.
    echo "${CAM:-0}" > "$here/build/cam.level"; extra+=(cam.level="$here/build/cam.level")
    echo "${CAMOPTS:-}" > "$here/build/cam.opts"; extra+=(cam.opts="$here/build/cam.opts")   # 0455: "tp=2 mode=1"
    [[ -n ${CAMOPTS:-} ]] && echo "camera options: $CAMOPTS"
    echo "${WDTTEST:-0}" > "$here/build/wdt.test"; extra+=(wdt.test="$here/build/wdt.test")
    [[ ${CAM:-0} != 0 ]] && echo "camera level $CAM"; [[ ${WDTTEST:-0} != 0 ]] && echo "watchdog test $WDTTEST"
    echo "test program: notefe bot"
fi
# hero-run with the Note FE patches (gracerlte/build-hero-run.sh) if built. ENABLE="job ...": jobs hero-run leaves off
# launchd's disabled list (LAUNCHD=bt implies com.apple.bluetoothd). Always written (empty = the S7 list), effective
# from the boot after the one that writes it, as for launchd.plist.
autorun="$M/hero-run"; [[ -s $M/hero-run-notefe ]] && autorun="$M/hero-run-notefe"
# Note FE 0458: CAMMEDIA=1 lets libheroapp load libnotefecam.dylib (the camera's capture device) in mediaserverd; written
# on every run, 0 by default.
echo "${CAMMEDIA:-0}" > "$here/build/cam.media"; extra+=(cam.media="$here/build/cam.media")
enable="${ENABLE:-}"; [[ ${LAUNCHD:-} == bt ]] && enable+=" com.apple.bluetoothd"
printf '%s\n' $enable > "$here/build/enabled.list"; extra+=(enabled.list="$here/build/enabled.list")
[[ -n ${enable// } ]] && echo "kept off launchd's disabled list:" $enable
if adb shell 'mount' | grep -q ' /data '; then
    echo "/data is mounted in TWRP: unmount it (Mount menu) first" >&2; exit 1
fi
python3 "$here/gracerlte/drop.py" adb \
  autorun="$autorun" test="$test_prog" gl.env="$D/gl.env" test.env="$D/test.env" \
  disabled.list="$D/disabled.list" wallpaper.off="$D/wallpaper.off" gestures.off="$D/gestures.off" \
  lib/libdrm.2.dylib="$M/lib/libdrm.2.dylib" lib/libOSMesa.8.dylib="$osmesa" \
  lib/libheroeagl.dylib="$M/lib/libhakiosgl.dylib" lib/libherosb.dylib="$M/lib/libherosb.dylib" \
  lib/libheroapp.dylib="$M/lib/libheroapp.dylib" lib/libnotefecam.dylib="$M/lib/libnotefecam.dylib" \
  audio/HakiosAudio="$M/audio/HakiosAudio" audio/Info.plist="$M/audio/Info.plist" \
  "${wifi[@]}" ${extra[@]+"${extra[@]}"} "$@"
