#!/bin/bash
# Read-only, in TWRP: this chip's own CPU/GPU frequency and voltage tables from Samsung's Linux kernel (cpufreq/ASV).
# The S7 port's voltages (2288 MHz at 993.75 mV, 2600 MHz at 1075 mV) are the maintainer's phone's; every chip has
# its own ASV group. Results: phone-info/cpu-tables.txt
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/phone-info/cpu-tables.txt"
[[ "$(adb get-state 2>/dev/null)" == recovery ]] || { echo "phone not in TWRP over adb" >&2; exit 1; }
adb shell '
show() { for f in "$@"; do [ -r "$f" ] && { echo "## $f"; cat "$f" 2>/dev/null; echo; }; done; }
show /sys/devices/system/cpu/cpufreq/mp-cpufreq/cluster0_volt_table /sys/devices/system/cpu/cpufreq/mp-cpufreq/cluster1_volt_table \
     /sys/devices/system/cpu/cpufreq/mp-cpufreq/cluster0_freq_table /sys/devices/system/cpu/cpufreq/mp-cpufreq/cluster1_freq_table \
     /sys/devices/system/cpu/cpufreq/mp-cpufreq/cluster0_max_freq /sys/devices/system/cpu/cpufreq/mp-cpufreq/cluster1_max_freq
for c in 0 4; do d=/sys/devices/system/cpu/cpu$c/cpufreq; show $d/scaling_available_frequencies $d/cpuinfo_max_freq $d/cpuinfo_min_freq $d/scaling_cur_freq $d/scaling_governor; done
show /sys/devices/14ac0000.mali/volt_table /sys/devices/14ac0000.mali/dvfs_table /sys/devices/14ac0000.mali/clock /sys/devices/14ac0000.mali/asv_table
ls /sys/devices/system/cpu/cpufreq/ /sys/power/ 2>/dev/null | tr "\n" " "; echo
for r in /sys/class/regulator/regulator.*; do n=$(cat $r/name 2>/dev/null); case "$n" in vdd_mngs|vdd_apollo|vdd_g3d|vdd_int|vdd_mif) echo "$n $(cat $r/microvolts 2>/dev/null) uV state=$(cat $r/state 2>/dev/null)";; esac; done
dmesg 2>/dev/null | grep -iE "asv|ect |cal-if|dvfs.*(table|volt)|mngs|apollo" | head -60
' > "$out" 2>&1
wc -l "$out"; sed -n 1,60p "$out"
