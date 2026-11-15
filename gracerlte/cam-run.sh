#!/bin/bash
# One camera test boot, the phone in TWRP: gracerlte/cam-run.sh NAME [CAMOPTS] [LEVEL] [CMDLINE-TAG]
# Writes the drop (quick bot, CAM=LEVEL, CAMOPTS), the armed boot image if it changed, reboots, waits for TWRP, collects
# logs/NAME.txt, prints the camera/fail-safe lines, pulls the picture to logs/camera/NAME.raw8 and makes NAME.png.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; cd "$here"
name=$1; opts=${2:-}; level=${3:-5}; tag=${4:-camarmed}
adb shell 'umount /data 2>/dev/null; true'
CAMMEDIA=$([[ $level == 8 ]] && echo 1 || echo 0) BOT=1 QUICK=1 CAM=$level CAMOPTS="$opts" gracerlte/write-drop.sh 2>&1 | grep -E 'package|camera'
gracerlte/swap-boot.sh "build/boot/notefe-boot-stock-$tag.img" 2>&1 | tail -1
adb reboot; t0=$(date +%s); sleep 30
for i in $(seq 1 180); do adb devices | grep -q 'recovery$' && { echo "back after $(( $(date +%s)-t0 )) s"; break; }; sleep 5; done
FAST=1 gracerlte/cycle-collect.sh "$name" >/dev/null 2>&1
grep -a -E 'NOTEFE CAM: (frame|picture|ae step 5)|BOT .*camera|NOTEFE SAFE: the last' "logs/$name.txt" | cut -c1-240
mkdir -p logs/camera
if python3 gracerlte/hfs-read.py get /private/var/herolte/cam.raw8 "logs/camera/$name.raw8" >/dev/null 2>&1; then
    python3 gracerlte/cam-debayer.py "logs/camera/$name.raw8" "logs/camera/$name.png"
fi
