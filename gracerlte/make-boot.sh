#!/bin/bash
# Build the Note FE BOOT images: Note FE loader (panel text at 0xd8000000), the locally built kernel with patch 0400,
# the Note FE ADT (framebuffer 0xd8000000) with each RAM level, the boot arguments, all packed into the phone's own
# BOOT (Samsung header + Note FE DTBs). Host only: writes nothing to the phone.
#
#   gracerlte/make-boot.sh                              -> build/boot/notefe-boot-{stock,camera,max}.img
#   gracerlte/make-boot.sh gracerlte/cmdline-2600.txt 2600 -> build/boot/notefe-boot-{stock,camera,max}-2600.img
#   CANVAS=8plus gracerlte/make-boot.sh gracerlte/cmdline.txt 8plus -> iPhone 8 Plus screen (1242x2208 @3x, Home button):
#     the ADT gets --iphone8plus and the boot line sweetfb_lw=1242 sweetfb_lh=2208 instead of 750/1334
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
R="$here"; B="$here/build"
K="$B/xnu-notefe/kernel.development.herolte"
L="$here/gracerlte/loader/shim/herolte/out/xnu_boot.Image"
[[ -f $K ]] || { echo "no kernel yet: run gracerlte/build-kernel.sh" >&2; exit 1; }
[[ -f $L ]] || (cd "$here/gracerlte/loader/shim/herolte" && CROSS=aarch64-elf- sh build.sh)
grep -q 'HERO_FB_BASE 0xd8000000' "$here/gracerlte/loader/shim/herolte/fbtext.h"
cmdfile=${1:-$here/gracerlte/cmdline.txt}; suffix=${2:+-$2}
C=$(tr -d '\n' < "$cmdfile")
adtcanvas=--iphone8
if [[ ${CANVAS:-8} == 8plus ]]; then
    adtcanvas=--iphone8plus
    [[ $C == *"sweetfb_lw=750 sweetfb_lh=1334"* ]] || { echo "boot line has no 750x1334 canvas to replace" >&2; exit 1; }
    C=${C/sweetfb_lw=750 sweetfb_lh=1334/sweetfb_lw=1242 sweetfb_lh=2208}
fi
(( ${#C} < 608 )) || { echo "boot arguments too long (${#C})" >&2; exit 1; }
mkdir -p "$B/adt" "$B/payload" "$B/boot"
python3 "$here/gracerlte/mkadt_notefe.py" "$B/adt/notefe-base.adt" --bank2 --bank2-mb 2048 $adtcanvas
for level in stock camera max; do
    python3 "$here/gracerlte/notefe-ram-banks.py" "$B/adt/notefe-base.adt" "$B/adt/notefe-$level.adt" \
        --level "$level" --cmdline "$here/phone-info/cmdline.txt"
    rm -f "$B/payload/notefe-$level$suffix.bin" "$B/boot/notefe-boot-$level$suffix.img"
    python3 "$R/tools/mkpayload.py" "$K" "$B/adt/notefe-$level.adt" "$B/payload/notefe-$level$suffix.bin" --cmdline "$C" >/dev/null
    python3 "$R/tools/herolte-pack-boot.py" pack "$here/backup/boot-stock.img" "$L" "$B/boot/notefe-boot-$level$suffix.img" \
        --append "$B/payload/notefe-$level$suffix.bin" --partition-size 41943040 | tail -1
done
(cd "$B/boot" && shasum -a 256 notefe-boot-*.img > SHA256SUMS.notefe && grep -- "$suffix.img" SHA256SUMS.notefe)
echo "boot arguments: ${#C} of 607 characters"
