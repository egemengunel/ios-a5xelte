#!/usr/bin/env python3
"""Split a decoded unified log (unifiedlog_iterator jsonl) into one text file per process for the LAST boot in it.
   oslog-split.py IN.jsonl OUTPREFIX   -> OUTPREFIX-<process>.txt (all processes), OUTPREFIX-errors.txt"""
import json, sys, collections, os
src, prefix = sys.argv[1], sys.argv[2]
last, lt = None, 0
with open(src) as f:
    for line in f:
        i = line.find('"boot_uuid":"'); b = line[i + 13:i + 45]
        j = line.find('"time":')
        try:
            t = float(line[j + 7:line.find(',', j)])
        except ValueError:
            continue
        if t > lt:
            lt, last = t, b
os.makedirs(os.path.dirname(prefix) or '.', exist_ok=True)
files, counts = {}, collections.Counter()
errors = open(prefix + '-errors.txt', 'w')
with open(src) as f:
    for line in f:
        if last not in line:
            continue
        d = json.loads(line)
        p = d['process'].rsplit('/', 1)[-1] or 'kernel'
        counts[p] += 1
        text = f"{d['time'] / 1e9:.3f} {d['log_type']} [{d['subsystem']}:{d['category']}] {d['message'].strip()}\n"
        if p not in files:
            if len(files) > 400:
                continue
            files[p] = open(f'{prefix}-{p}.txt', 'w')
        files[p].write(text)
        if d['log_type'] in ('Error', 'Fault'):
            errors.write(p + ' ' + text)
for fh in files.values():
    fh.close()
errors.close()
with open(prefix + '-counts.txt', 'w') as fh:
    for p, c in counts.most_common():
        fh.write(f'{c:8d} {p}\n')
print('boot', last, sum(counts.values()), 'entries,', len(counts), 'processes')
