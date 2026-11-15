#!/bin/bash
# One-screen summary of an unattended boot: bot steps, charger, sandbox extensions, crashes, CPU, frame times.
here="$(cd "$(dirname "$0")/.." && pwd)"
n=${1:?name}; L="$here/logs/$n.txt"; O="$here/logs/oslog/$n"
echo "== $n"
echo "-- bot"; grep -a 'NOTEFE BOT' "$L" | sed 's/^.*NOTEFE BOT/BOT/' | cut -c1-160 | head -60
echo "-- charger"; grep -a 'NOTEFE CHG\|SWEET BATTERY:' "$L" | cut -c1-170 | head -12
echo "-- sandbox extensions"; grep -a 'NOTEFE SANDBOX' "$L" | sed -E 's/\[[0-9]+\]//' | cut -c1-150 | sort | uniq -c | head -12
echo "-- tccd sandbox failures"; grep -c 'Failed to issue' "$O-tccd.txt" 2>/dev/null
echo "-- crashes"; grep -aoE 'CRASH [A-Za-z0-9_.-]+' "$L" | sort | uniq -c | sort -rn | head -15
echo "-- uncaught"; grep -a 'uncaught' "$L" | sed -E 's/^.*HEROGPU //; s/\[[0-9]+\]//g' | cut -c1-200 | sort | uniq -c | sort -rn | head -10
echo "-- CPU (TOP 5s, busiest samples)"; grep -a 'TOP 5s' "$L" | awk -F'all ' '{split($2,a,"%"); print a[1]" "$0}' | sort -rn | head -5 | cut -c1-200
echo "-- frame times (hakios-gl, us)"; grep -aoE 'hakios-gl: frame [0-9]+: .*; [0-9]+ us' "$L" | grep -oE '[0-9]+ us$' | awk '{s+=$1; n++; if($1>16700) slow++} END {if(n) printf "frames logged %d, mean %.1f ms, over 16.7 ms: %d\n", n, s/n/1000, slow}'
echo "-- location"; grep -h 'disabled system-wide' "$O-locationd.txt" 2>/dev/null | wc -l | sed 's/^/"disabled system-wide" lines: /'
# Like for like across boots: only the frames logged while the bot ran (its "start" to its "done" line).
echo "-- frame times during the bot run"
awk '/NOTEFE BOT t=0.0 start/ {on=1} on && /NOTEFE BOT t=[0-9.]+ done/ {on=0} on' "$L" | grep -aoE 'hakios-gl: frame [0-9]+: .*; [0-9]+ us' | grep -oE '[0-9]+ us$' | awk '{print $1}' | sort -n | awk '{a[NR]=$1; s+=$1; if ($1 > 16700) slow++} END {if (NR) printf "frames %d, mean %.1f ms, median %.1f, p90 %.1f, p99 %.1f, over 16.7 ms %.0f%%\n", NR, s/NR/1000, a[int(NR*.5)]/1000, a[int(NR*.9)]/1000, a[int(NR*.99)]/1000, 100*slow/NR}'
# What the eye sees: the display's 5 s reports while the bot ran. gaps = frames shown 1/2/3/4+ ticks (16.7 ms) after
# the one before; 1 is smooth, 2 a dropped frame, 3+ a visible hitch.
echo "-- display during the bot run"
awk '/NOTEFE BOT t=0.0 start/ {on=1} on && /NOTEFE BOT t=[0-9.]+ done/ {on=0} on' "$L" | grep -aoE 'A5XELTE FB: frames=[0-9]+ elapsed_ms=[0-9]+ .*avg_copy_us=[0-9]+ .*gaps=[0-9]+/[0-9]+/[0-9]+/[0-9]+' | \
  sed -E 's/.*frames=([0-9]+) elapsed_ms=([0-9]+).*avg_copy_us=([0-9]+).*gaps=([0-9]+)\/([0-9]+)\/([0-9]+)\/([0-9]+)/\1 \2 \3 \4 \5 \6 \7/' | \
  awk '{f+=$1; ms+=$2; c+=$3*$1; g1+=$4; g2+=$5; g3+=$6; g4+=$7} END {g=g1+g2+g3+g4; if (g) printf "%.1f fps shown on average, copy %.1f ms a frame; gaps 1/2/3/4+: %d/%d/%d/%d (smooth %.0f%%, hitches %.0f%%)\n", f*1000/ms, c/f/1000, g1, g2, g3, g4, 100*g1/g, 100*(g3+g4)/g}'
