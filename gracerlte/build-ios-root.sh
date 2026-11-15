#!/bin/bash
# Build the iOS 16.7.16 root image locally on this Mac: the "Stage the root volume" and "Raw image, compressed and
# split" steps of ios-a5xelte/.github/workflows/ios-root.yml, without a private GitHub repo.
#
#   gracerlte/fetch-ipsw.sh            (first; no sudo)
#   sudo gracerlte/build-ios-root.sh   (asks nothing else; about 20-40 min)
#
# Needs sudo because the iOS files keep their real owners (root, mobile=501) and the raw image is read with dd.
# It only writes inside build/: a 20 GiB sparse HFSX image, then build/root/root.img.gz.partNN + SHA256SUMS.
# Peak disk use is about 30 GB. The IPSW disk images are kept (delete build/ipsw/*.dmg afterwards to save ~8 GB).
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run with sudo: sudo $0" >&2; exit 2; }
here="$(cd "$(dirname "$0")/.." && pwd)"
R="$here"
B="$here/build"
SIZE_MB=${SIZE_MB:-20480}
user=${SUDO_USER:-$(stat -f %Su "$here")}
for f in os systemos appos; do [[ -f "$B/ipsw/$f.dmg" ]] || { echo "missing $B/ipsw/$f.dmg: run gracerlte/fetch-ipsw.sh" >&2; exit 1; }; done
mkdir -p "$B/root"; cd "$B/root"
[[ ! -e root.sparseimage ]] || { echo "build/root/root.sparseimage exists from an earlier run; delete it first" >&2; exit 1; }

mounts=()
cleanup() { for m in "${mounts[@]:-}"; do [[ -n $m ]] && hdiutil detach -force "$m" >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
attach() { hdiutil attach -nobrowse -readonly -owners on "$1" | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1; }

os=$(attach "$B/ipsw/os.dmg"); mounts+=("$os")
sys=$(attach "$B/ipsw/systemos.dmg"); mounts+=("$sys")
app=$(attach "$B/ipsw/appos.dmg"); mounts+=("$app")
echo "OS=$os SystemOS=$sys AppOS=$app"

hdiutil create -size "${SIZE_MB}m" -type SPARSE -layout NONE -fs "Case-sensitive Journaled HFS+" -volname IOSROOT root
root=$(hdiutil attach -nobrowse -owners on root.sparseimage | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1)
mounts=("$root" "${mounts[@]}")
echo "root=$root"
env STAGE_ALL_APPS=1 STAGE_FULL=1 bash "$R/tools/a5xelte-stage-ios-root.sh" "$os" "$sys" "$app" "$root"
build=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$B/ipsw/BuildManifest.plist")
bash "$R/tools/herolte-tune-ios-root.sh" "$root" "$build"
cleanup; mounts=()

dev=$(hdiutil attach -nomount -nobrowse root.sparseimage | awk 'NR==1 {print $1}')
mounts=("$dev")
echo "raw device $dev -> root.img.gz"
dd if="/dev/r${dev#/dev/}" bs=4m | gzip -1 > root.img.gz
hdiutil detach "$dev"; mounts=()
rm -f root.sparseimage
split -b 1900m -d -a 2 root.img.gz root.img.gz.part
rm root.img.gz
shasum -a 256 root.img.gz.part* | tee SHA256SUMS
chown -R "$user" "$B/root"
echo "Done: $B/root/root.img.gz.part*"
