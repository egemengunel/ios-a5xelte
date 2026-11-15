#!/usr/bin/env python3
"""Note FE: iPhone 8-size (375w-667h@2x) copies of the iOS root's collection wallpapers.

The D22 (iPhone X) root has only 375w-812h@3x / 393w-852h / 430w-932h variants; our screen class is 375w-667h@2x, so
the wallpaper picker found no variant and drew black tiles. Each 375w-812h@3x variant is copied under the 667h@2x name
with its files and its Wallpaper.plist (logicalScreenClass, file names) renamed. Output: build/drop/wallpaper/<path on
the phone>, installed by `WALLPAPER=1 gracerlte/write-drop.sh`. Apple's files: build/ only, never pushed.
  usage: make-wallpapers.py MOUNTED_ROOT OUT
"""
import os, plistlib, shutil, sys

root, out = sys.argv[1], sys.argv[2]
coll = os.path.join(root, 'Library/Wallpaper/Collections')
SRC, DST = '375w-812h@3x', '375w-667h@2x'
made = 0
for c in sorted(os.listdir(coll)):
    wdir = os.path.join(coll, c, 'Wallpapers')
    if not os.path.isdir(wdir):
        continue
    for w in sorted(os.listdir(wdir)):
        if SRC not in w:
            continue
        src = os.path.join(wdir, w)
        rel = os.path.relpath(os.path.join(wdir, w.replace(SRC, DST)), root)
        dst = os.path.join(out, rel)
        if os.path.exists(dst):
            shutil.rmtree(dst)
        for d, _, files in os.walk(src):
            for f in files:
                s = os.path.join(d, f)
                r = os.path.relpath(s, src).replace(SRC, DST)
                t = os.path.join(dst, r)
                os.makedirs(os.path.dirname(t), exist_ok=True)
                if f == 'Wallpaper.plist' and d == src:
                    with open(s, 'rb') as fh:
                        p = plistlib.load(fh)
                    def fix(v):
                        if isinstance(v, str):
                            return v.replace(SRC, DST)
                        if isinstance(v, dict):
                            return {k: fix(x) for k, x in v.items()}
                        if isinstance(v, list):
                            return [fix(x) for x in v]
                        return v
                    p = fix(p)
                    with open(t, 'wb') as fh:
                        plistlib.dump(p, fh, fmt=plistlib.FMT_BINARY)
                else:
                    shutil.copy2(s, t)
        made += 1
        print('made', rel)
print(made, 'wallpapers')
