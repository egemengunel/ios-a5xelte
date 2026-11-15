#!/bin/bash
# Build the HEROLTE XNU kernel locally, as ios-a5xelte/.github/workflows/xnu.yml does on GitHub, plus the Note FE
# patch gracerlte/kernel/0400-notefe-panel-at-d8000000.patch. Uses build/dxb (blacktop/darwin-xnu-build @ the
# workflow's pinned commit, already set up with every patch).
#
#   gracerlte/build-kernel.sh
#
# First run: darwin-xnu-build downloads Apple's Kernel Debug Kit 13.5 (22G74) from Dortania's KdkSupportPkg
# mirror and installs it with `sudo installer` into /Library/Developer/KDKs: it asks for your Mac password once.
# Output: build/xnu-notefe/kernel.development.herolte (+ build log build/xnu-notefe/build.log).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
W="$HOME/notefe-xnu-build"          # no spaces: Apple's makefiles break on "Note FE iOS 16 Experiment" (build/dxb links here)
out="$here/build/xnu-notefe"
mkdir -p "$out"
[[ -f "$W/patches/0400-notefe-panel-at-d8000000.patch" ]] || { echo "build/dxb not set up" >&2; exit 1; }
export PATH="$here/build/bin:/opt/homebrew/bin:$PATH"     # xcodes stub (Xcode is installed), Homebrew tools
export MACOS_VERSION=13.5 KERNEL_CONFIG=DEVELOPMENT MACHINE_CONFIG=HEROLTE MAKEFLAGS=-k
cd "$W"
# Always a clean build: darwin-xnu-build skips patches on an already patched tree and never relinks an existing kernel.
# The source clones are reset to their tags instead of downloaded again (xnu alone takes ~10 min to clone here).
for repo in xnu AvailabilityVersions bootstrap_cmds dtrace; do
    if [[ -d $repo/.git ]]; then
        git -C "$repo" reset -q --hard && git -C "$repo" clean -qfdx
    else
        rm -rf "$repo"
    fi
done
rm -rf build fakeroot venv
cp "$here"/xnu/patches/04*.patch patches/
[[ -f "$out/kernel.development.herolte" ]] && mv "$out/kernel.development.herolte" "$out/kernel.development.herolte.prev"
start=$(date +%s)
/opt/homebrew/bin/bash build.sh 2>&1 | tee "$out/build.log"
k="$W/fakeroot/System/Library/Kernels/kernel.development.herolte"
if [[ -f $k ]]; then
    cp "$k" "$out/"
    (cd "$out" && shasum -a 256 kernel.development.herolte | tee SHA256SUMS)
    grep -cE 'Skipping patch' "$out/build.log" | sed 's/^/patches skipped (check build.log if not 0 for ours): /'
    grep -E 'Skipping patch.*(0[0-9]{3}-)' "$out/build.log" || echo "all ios-a5xelte/notefe patches applied"
    echo "Done in $(( ($(date +%s) - start) / 60 )) min: $out/kernel.development.herolte"
else
    echo "Kernel not built; first errors:"; grep -nE ':[0-9]+:[0-9]+: (fatal )?error:|^ld: ' "$out/build.log" | grep -v 'ld: warning' | head -20
    exit 1
fi
