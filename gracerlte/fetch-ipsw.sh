#!/bin/bash
# Fetch only the needed members of Apple's iPhone X (iPhone10,3) iOS 16.7.16 IPSW into build/ipsw/
# (same as the "Fetch IPSW members" step of ios-a5xelte/.github/workflows/ios-root.yml, run locally).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
R="$here"
out="$here/build/ipsw"
mkdir -p "$out"
cd "$here/build"
url=$(curl -sf "https://api.ipsw.me/v4/device/iPhone10,3?type=ipsw" | python3 -c "
import json, sys
fw = [f for f in json.load(sys.stdin)['firmwares'] if f['version'] == '16.7.16']
print(fw[0]['url'])")
echo "IPSW: $url"
[ -f ipsw/BuildManifest.plist ] || python3 "$R/tools/remotezip.py" "$url" BuildManifest.plist ipsw
python3 - ipsw/BuildManifest.plist > members.txt <<'PY'
import plistlib, sys
m = plistlib.load(open(sys.argv[1], 'rb'))
ident = next(i for i in m['BuildIdentities']
             if i['Info']['DeviceClass'].lower() == 'd22ap' and 'Erase' in i['Info'].get('Variant', ''))
want = {'DeviceTree': 'devicetree', 'Cryptex1,SystemOS': 'systemos', 'Cryptex1,AppOS': 'appos', 'OS': 'os'}
for key, name in want.items():
    print(name, ident['Manifest'][key]['Info']['Path'])
PY
while read -r name member; do
    dest="ipsw/$name.${member##*.}"
    if [ -f "$dest" ]; then echo "have $dest"; continue; fi
    python3 "$R/tools/remotezip.py" "$url" "$member" ipsw
    mv "ipsw/$member" "$dest"
    ls -la "$dest"
done < members.txt
echo DONE
