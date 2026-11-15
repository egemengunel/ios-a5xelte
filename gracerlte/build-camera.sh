#!/bin/bash
# libnotefecam.dylib (gracerlte/camera: the S9 ports' capture device camera_device.c + camera_isp.c, MIT, and inject.c)
# -> build/mesa/lib/libnotefecam.dylib; write-drop.sh puts it in the drop zone's lib/, libheroapp loads it in mediaserverd.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; S="$here/gracerlte/camera"; L="$here/build/mesa/lib"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.0 -isysroot "$SDK" -O2 -fblocks -Wall -Wno-unused-function \
  -Wno-deprecated-declarations -dynamiclib -o "$L/libnotefecam.dylib" "$S/inject.c" "$S/camera_device.c" "$S/camera_isp.c" \
  -install_name @rpath/libnotefecam.dylib -framework CoreFoundation -framework CoreMedia -framework CoreVideo \
  -framework IOSurface -lobjc
codesign -s - -f "$L/libnotefecam.dylib"
ls -la "$L/libnotefecam.dylib"
