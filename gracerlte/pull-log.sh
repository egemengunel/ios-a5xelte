#!/bin/bash
# Read-only: pull the kernel's persistent log (last 4 MiB of USERDATA) from TWRP and print a short digest.
#   gracerlte/pull-log.sh [name]        -> logs/<name>.txt   (default: boot-YYYYmmdd-HHMM)
# The log can hold names of nearby Wi-Fi networks and app messages: keep logs/ private.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$here/logs"
name=${1:-boot-$(date +%Y%m%d-%H%M)}
out="$here/logs/$name.txt"
[[ "$(adb get-state 2>/dev/null)" == recovery ]] || { echo "phone not in TWRP over adb" >&2; exit 1; }
python3 "$here/tools/herolte-log-pull.py" adb "$out" || exit 1
echo "saved $out ($(wc -l < "$out") lines)"
echo "--- digest"
grep -aE 'NOTEFE CPU|HEROLTE CPU: (Mongoose|MNGS_PLL)|HEROLTE (TOUCH|WIFI|FB2|GPU): |HEROLTE PMIC|ram banks|RAM bank|hakios-ram|Mongoose to|TMU|heat' "$out" | awk '!seen[substr($0,1,60)]++' | head -40
echo "--- panics"
grep -aiE 'panic\(|panic:|assertion failed|tt_entry_free' "$out" | head -10
echo "--- crashes (count by process)"
grep -aoE 'CRASH [A-Za-z0-9_.-]+' "$out" | sort | uniq -c | sort -rn | head -25
