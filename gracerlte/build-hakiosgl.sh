#!/bin/bash
# Build the Note FE libhakiosgl.dylib (HakiOS's EAGL bridge, MIT: gracerlte/hakios-gl = upstream gpu/hakios-gl + Note FE
# changes, see eagl.c "Note FE") the way upstream gpu/eagl/build-eagl.sh does, against the drop zone's libOSMesa, and
# put it in build/mesa/lib (the upstream build is kept once as libhakiosgl.dylib.upstream). write-drop.sh installs it
# on the phone as lib/libheroeagl.dylib.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
L="$here/build/mesa/lib"
HG="$here/gracerlte/hakios-gl"
EAGL="$here/gpu/eagl"
MESA_INC=${MESA_INC:-$HOME/notefe-mesa-build/mesa/include}
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=(xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.0 -isysroot "$SDK")
OBJ=$(mktemp -d)
trap 'rm -rf "$OBJ"' EXIT
[[ -f $L/libhakiosgl.dylib.upstream ]] || cp "$L/libhakiosgl.dylib" "$L/libhakiosgl.dylib.upstream"

CF=(-O2 -g -fvisibility=hidden -Wall -Wno-deprecated-declarations -Wno-unused-function "-I$EAGL/src" "-I$MESA_INC")
for f in hero_log hero_backboardd hero_prof; do
  "${CC[@]}" "${CF[@]}" -c "$EAGL/src/$f.c" -o "$OBJ/$f.o"
done
nm -gU "$L/libOSMesa.8.dylib" | awk '$3 ~ /^_gl/ { print substr($3, 2) }' > "$OBJ/exported-gl.txt"
python3 "$HG/mkeagl.py" "$HG/src/eagl_slots.txt" "$MESA_INC/../src/mapi/glapi/registry/gl.xml" \
  "$OBJ/exported-gl.txt" "$HG/src/eagl.c" > "$OBJ/eagl_gen.h"
"${CC[@]}" -O2 -g -w -I"$OBJ" -I"$HG/src" -I"$HG/include" -c "$HG/src/eagl.c" -o "$OBJ/hg_eagl.o"
"${CC[@]}" -O2 -g -Wall -I"$HG/src" -c "$HG/src/gl_hero.c" -o "$OBJ/hg_gl_hero.o"
"${CC[@]}" -O2 -g -Wall -c "$HG/src/ca_hooks.c" -o "$OBJ/hg_ca_hooks.o"
"${CC[@]}" -dynamiclib -o "$L/libhakiosgl.dylib" "$OBJ"/{hg_eagl,hg_gl_hero,hg_ca_hooks,hero_log,hero_backboardd,hero_prof}.o \
  -install_name @rpath/libhakiosgl.dylib \
  -framework CoreFoundation -framework IOKit -framework IOSurface -lobjc \
  -L "$L" -lOSMesa.8 -Wl,-rpath,/private/var/herolte/lib -Wl,-undefined,error
codesign -s - -f "$L/libhakiosgl.dylib"
otool -L "$L/libhakiosgl.dylib" | head -8
shasum -a 256 "$L/libhakiosgl.dylib"
