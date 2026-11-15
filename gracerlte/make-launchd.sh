#!/bin/bash
# Build build/drop/launchd/launchd.plist: the phone's own /System/Library/xpc/launchd.plist (read from the iOS disk in
# TWRP, read-only) without the jobs heronoexec refuses. On iOS 16, launchd ignores hero-run's disabled.plist
# (disabled.migrated), so it spawns those again every ten seconds (about 80 failed spawns each per session) and their
# clients wait for ever (Phone waits on vmd). Without the job, a client gets "no such service" at once.
#   gracerlte/make-launchd.sh [label ...]       (default: the heronoexec set below)
#   OUT=build/drop/launchd-bt gracerlte/make-launchd.sh LABELS...   a variant (write-drop.sh LAUNCHD=bt picks it)
# Then gracerlte/write-drop.sh puts it in place (kernel patch 0404); effective from the boot after.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
L="${OUT:-$here/build/drop/launchd}"; mkdir -p "$L" "$here/logs/launchd"
python3 "$here/gracerlte/hfs-read.py" get /System/Library/xpc/launchd.plist "$here/logs/launchd/launchd.plist.phone" >/dev/null
labels=("$@")
(( ${#labels[@]} )) || labels=(com.apple.voicemail.vmd com.apple.bluetoothd com.apple.searchd com.apple.homed
    com.apple.aggregated com.apple.analyticsd com.apple.cloudd com.apple.ReportCrash com.apple.driverkitd)
python3 - "$here/logs/launchd/launchd.plist.phone" "$L/launchd.plist" "${labels[@]}" <<'PY'
import plistlib, sys
src, dst, labels = sys.argv[1], sys.argv[2], set(sys.argv[3:])
raw = open(src, 'rb').read()
fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
p = plistlib.loads(raw)
removed = []
for section, jobs in p.items():
    if not isinstance(jobs, dict):
        continue
    for key in list(jobs):
        job = jobs[key]
        label = job.get('Label') if isinstance(job, dict) else None
        if label in labels or key in labels:
            removed.append(f'{section}: {label or key}')
            del jobs[key]
missing = labels - {r.split(': ', 1)[1] for r in removed}
open(dst, 'wb').write(plistlib.dumps(p, fmt=fmt, sort_keys=False))
print(f'{"binary" if fmt == plistlib.FMT_BINARY else "XML"} plist, {len(removed)} jobs removed:')
for r in removed:
    print('  -', r)
if missing:
    print('not found (left alone):', ', '.join(sorted(missing)))
PY
plutil -lint "$L/launchd.plist"
ls -l "$here/logs/launchd/launchd.plist.phone" "$L/launchd.plist"
