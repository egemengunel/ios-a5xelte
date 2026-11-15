#!/bin/bash
# Build the Note FE libheroapp.dylib (gracerlte/heroapp/heroapp.c: upstream gpu/eagl/src/heroapp.c + Note FE fixes) with
# Xcode's iPhoneOS SDK, linked to the drop zone's libdrm.2 like upstream, and put it in build/mesa/lib (the upstream
# build is kept once as libheroapp.dylib.upstream). Then gracerlte/write-drop.sh puts it on the phone.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
L="$here/build/mesa/lib"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
[[ -f $L/libheroapp.dylib.upstream ]] || cp "$L/libheroapp.dylib" "$L/libheroapp.dylib.upstream"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.0 -isysroot "$SDK" -O2 -Wall -dynamiclib \
  -o "$L/libheroapp.dylib" "$here/gracerlte/heroapp/heroapp.c" -install_name @rpath/libheroapp.dylib \
  -framework Foundation -framework UIKit -framework CoreGraphics -lobjc -L "$L" -ldrm.2 -Wl,-rpath,/private/var/herolte/lib
codesign -s - -f "$L/libheroapp.dylib"
otool -L "$L/libheroapp.dylib"
shasum -a 256 "$L/libheroapp.dylib"
