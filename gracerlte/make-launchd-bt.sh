#!/bin/bash
# build/drop/launchd-bt/launchd.plist (write-drop.sh LAUNCHD=bt): the phone's launchd.plist (logs/launchd/
# launchd.plist.phone, from make-launchd.sh) plus bluetoothd's job from the IPSW (logs/launchd/launchd.plist.ipsw).
# The job gets the label com.apple.bluetoothd.notefe: launchd keeps its own copy of the disabled list (it rewrites
# /private/var/db/com.apple.xpc.launchd/disabled.plist, so hero-run's list alone doesn't re-enable a job), and that
# list matches by label. Clients find bluetoothd by its Mach service names, which stay the same.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$here/build/drop/launchd-bt"
python3 - "$here/logs/launchd/launchd.plist.phone" "$here/logs/launchd/launchd.plist.ipsw" \
  "$here/build/drop/launchd-bt/launchd.plist" <<'PY'
import plistlib, sys
phone, ipsw, out = sys.argv[1:]
raw = open(phone, 'rb').read()
fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
p = plistlib.loads(raw)
k = '/System/Library/LaunchDaemons/com.apple.bluetoothd.plist'
job = dict(plistlib.load(open(ipsw, 'rb'))['LaunchDaemons'][k])
job['Label'] = 'com.apple.bluetoothd.notefe'
p['LaunchDaemons'][k] = job
open(out, 'wb').write(plistlib.dumps(p, fmt=fmt, sort_keys=False))
print('bluetoothd job added as', job['Label'])
PY
plutil -lint "$here/build/drop/launchd-bt/launchd.plist"
