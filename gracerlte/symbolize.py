#!/usr/bin/env python3
"""Symbolize the port's console crash reports (CRASH name pc/lr/bt lines) against the iOS 16.7.16 shared cache.

  gracerlte/symbolize.py LOG DSC_DIR [process ...]

DSC_DIR holds dyld_shared_cache_arm64* and the symindex.bin built by ios-a5xelte/tools/herolte-dsc-sym.py DSC_DIR build.
Each distinct crash (by process and pc) is shown once with its count; addresses are unslid with the report's slide.
"""
import collections, os, re, subprocess, sys

log, dsc = sys.argv[1], sys.argv[2]
only = set(sys.argv[3:])
sym = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ios-a5xelte', 'tools', 'herolte-dsc-sym.py')
head = re.compile(r'CRASH (\S+)\[(\d+)\] sig (\d+) .*slide (0x[0-9a-f]+)')
crashes, cur = collections.OrderedDict(), None
for line in open(log, errors='replace'):
    m = head.search(line)
    if m:
        cur = {'name': m.group(1), 'sig': m.group(3), 'slide': int(m.group(4), 16), 'pc': 0, 'lr': 0, 'bt': [], 'reason': ''}
        continue
    if not cur or not line.startswith('CRASH ' + cur['name'] + ' '):
        continue
    rest = line.split(' ', 2)[2].strip()
    if rest.startswith('pc '):
        f = rest.split()
        cur['pc'], cur['lr'] = int(f[1], 16), int(f[3], 16)
    elif rest.startswith('bt '):
        cur['bt'] = [int(x, 16) for x in rest.split()[1:]]
    elif rest.startswith('reason'):
        cur['reason'] = rest
        key = (cur['name'], cur['pc'] - cur['slide'])
        if not only or cur['name'] in only:
            crashes.setdefault(key, [cur, 0])[1] += 1
        cur = None

for (name, _), (c, n) in crashes.items():
    addrs = [a - c['slide'] for a in [c['pc'], c['lr']] + c['bt'] if a > c['slide']]
    out = subprocess.run([sys.executable, sym, dsc] + [hex(a) for a in addrs], capture_output=True, text=True).stdout.strip()
    print(f"=== {name} x{n} sig {c['sig']} {c['reason']}")
    for lab, l in zip(['pc', 'lr'] + ['bt'] * len(c['bt']), out.splitlines()):
        print(f'  {lab:2} {l}')
