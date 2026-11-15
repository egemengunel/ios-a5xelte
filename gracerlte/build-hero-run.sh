#!/bin/bash
# hero-run (the autorun) with the Note FE patches, without touching ios-a5xelte/:
#   gracerlte/hero-run-enabled.patch  DROP_DIR enabled.list keeps jobs (bluetoothd) off launchd's disabled list.
# Same compile line as ios-a5xelte/gpu/eagl/build-eagl.sh. Output build/mesa/hero-run-notefe (write-drop.sh prefers it).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/gpu/eagl/test"; M="$here/build/mesa"; W="$here/build/herorun"
rm -rf "$W"; mkdir -p "$W"
cp "$src/hero-run.c" "$W/hero-run.c"
(cd "$W" && patch -s -p1 < "$here/gracerlte/hero-run-enabled.patch")
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.0 -isysroot "$SDK" -O2 -Wall \
  -o "$M/hero-run-notefe" "$W/hero-run.c" -L "$M/lib" -ldrm.2 -lobjc -framework Foundation \
  -Wl,-rpath,/private/var/herolte/lib
codesign -s - -f --entitlements "$src/hero-run.entitlements" "$M/hero-run-notefe"
ls -la "$M/hero-run-notefe"
