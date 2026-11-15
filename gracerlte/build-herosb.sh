#!/bin/bash
# Build the Note FE libherosb.dylib (gracerlte/herosb/herosb.c = upstream gpu/eagl/src/herosb.c + the brightness bridge)
# like upstream build-eagl.sh, into build/mesa/lib (upstream's kept once as libherosb.dylib.upstream).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
L="$here/build/mesa/lib"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
[[ -f $L/libherosb.dylib.upstream ]] || cp "$L/libherosb.dylib" "$L/libherosb.dylib.upstream"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.0 -isysroot "$SDK" -O2 -Wall -dynamiclib \
  -o "$L/libherosb.dylib" "$here/gracerlte/herosb/herosb.c" -install_name @rpath/libherosb.dylib \
  -framework CoreFoundation -lobjc -L "$L" -ldrm.2 -Wl,-rpath,/private/var/herolte/lib
codesign -s - -f "$L/libherosb.dylib"
shasum -a 256 "$L/libherosb.dylib"
