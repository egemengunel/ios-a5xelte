#!/bin/bash
# Unattended loop, read side (AUTOMATION.md): wait until the phone is back in TWRP (herotwrp), then pull the kernel log,
# copy iOS's unified log store (read-only) and decode the last boot's entries for the processes we follow.
#   gracerlte/cycle-collect.sh NAME [MAX_MINUTES]      -> logs/NAME.txt, logs/oslog/NAME-*.txt, logs/NAME-summary.txt
#   FAST=1 gracerlte/cycle-collect.sh NAME              kernel log only (seconds, not 5-7 min): frame times, profiler, bot
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
name=${1:?name}; max=${2:-30}
for ((i = 0; i < max * 6; i++)); do
    [[ "$(adb get-state 2>/dev/null)" == recovery ]] && break
    sleep 10
done
[[ "$(adb get-state 2>/dev/null)" == recovery ]] || { echo "phone not back in TWRP after $max min"; exit 2; }
echo "back in TWRP at $(date '+%H:%M:%S')"
sleep 8
adb shell 'umount /data 2>/dev/null; true'
"$here/gracerlte/pull-log.sh" "$name" > "$here/logs/$name-digest.txt" 2>&1
if [[ ${FAST:-0} == 1 ]]; then
    "$here/gracerlte/cycle-summary.sh" "$name" > "$here/logs/$name-summary.txt" 2>&1
    cat "$here/logs/$name-summary.txt"
    exit 0
fi
A="$here/logs/oslog/$name.logarchive"
rm -rf "$A"
python3 "$here/gracerlte/hfs-read.py" getdir /private/var/db/diagnostics "$A" | tail -1
python3 "$here/gracerlte/hfs-read.py" getdir /private/var/db/uuidtext "$A" | tail -1
U=~/notefe-tools/unifiedlogs/unifiedlog_iterator-v0.7.0-aarch64-apple-darwin/unifiedlog_iterator
"$U" -m log-archive -i "$A" -o "$here/logs/oslog/$name.jsonl" 2>/dev/null
python3 "$here/gracerlte/oslog-split.py" "$here/logs/oslog/$name.jsonl" "$here/logs/oslog/$name"
rm -f "$here/logs/oslog/$name.jsonl"            # 4 GB; the per-process files are kept
"$here/gracerlte/cycle-summary.sh" "$name" > "$here/logs/$name-summary.txt" 2>&1
cat "$here/logs/$name-summary.txt"
