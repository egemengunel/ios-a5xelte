#!/bin/bash
# Ask for the Wi-Fi network iOS should join (WPA2) and write build/drop/wifi/network.txt (line 1 name, line 2 password).
# Run it yourself in Terminal so the password is typed only by you. The file stays on this Mac (mode 600) until
# write-drop.sh copies it to the phone. The kernel never logs the password.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
f="$here/build/drop/wifi/network.txt"
mkdir -p "$(dirname "$f")"
read -r -p "Wi-Fi name (SSID, 2.4 or 5 GHz, WPA2): " ssid
read -r -s -p "Wi-Fi password (hidden): " pass; echo
[[ -n $ssid && ${#pass} -ge 8 ]] || { echo "Need a name and a WPA2 password of 8+ characters." >&2; exit 1; }
umask 077
printf '%s\n%s\n' "$ssid" "$pass" > "$f"
chmod 600 "$f"
echo "Saved for \"$ssid\" in build/drop/wifi/network.txt"
