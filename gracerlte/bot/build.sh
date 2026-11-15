#!/bin/bash
# Build gracerlte/bot -> build/mesa/notefe-bot (the drop zone's "test" when gracerlte/write-drop.sh gets BOT=1).
set -euo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
out="$here/build/mesa/notefe-bot"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.0 -isysroot "$SDK" -O2 -Wall -fobjc-arc \
  -o "$out" "$here/gracerlte/bot/bot.m" -framework Foundation -L "$here/build/mesa/lib" -ldrm.2 -Wl,-rpath,/private/var/herolte/lib
codesign -s - -f --entitlements "$here/gracerlte/bot/bot.entitlements" "$out"
shasum -a 256 "$out"
