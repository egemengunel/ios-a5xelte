#!/usr/bin/env python3
"""Front camera picture from the bot (kern.notefe_cam_pic, drop zone cam.raw8): 1304x980 Bayer, 8 bits -> PNG, one
   pixel per 2x2 cell (652x490). Standard library only.
   cam-debayer.py IN.raw8 OUT.png [ORDER]   ORDER of the 2x2 cell: grbg (default), rggb, bggr, gbrg.
   Black level 16 (64 >> 2) off, grey-world balance, scaled to the 99.5th percentile, gamma 2.2. Prints the raw mean
   and range first: a mean near 16 is a dark scene, not a broken picture."""
import sys, zlib, struct
src, dst = sys.argv[1], sys.argv[2]
order = (sys.argv[3] if len(sys.argv) > 3 else 'grbg').lower()
W, H = 1304, 980
a = open(src, 'rb').read()
if len(a) != W * H:                     # 0455: an 8-byte header (width, height, little-endian)
    W, H = struct.unpack('<II', a[:8])
    a = a[8:]
assert len(a) == W * H, (len(a), W, H)
print('raw: mean %.1f min %d max %d' % (sum(a) / len(a), min(a), max(a)))
cells = []
sums = [0.0, 0.0, 0.0]
for y in range(0, H, 2):
    r0, r1 = a[y * W:(y + 1) * W], a[(y + 1) * W:(y + 2) * W]
    row = []
    for x in range(0, W, 2):
        v = {}
        q = [r0[x], r0[x + 1], r1[x], r1[x + 1]]
        gs = []
        for c, val in zip(order, q):
            val = max(val - 16, 0)
            if c == 'g':
                gs.append(val)
            else:
                v[c] = val
        px = (v['r'], (gs[0] + gs[1]) / 2, v['b'])
        for i in range(3):
            sums[i] += px[i]
        row.append(px)
    cells.append(row)
n = len(cells) * len(cells[0])
mean = [s / n + 1e-3 for s in sums]
gain = [sum(mean) / 3 / m for m in mean]
vals = sorted(max(p[i] * gain[i] for i in range(3)) for row in cells for p in row)
top = vals[int(len(vals) * 0.995)] or 1
out = bytearray()
for row in cells:
    out.append(0)
    for p in row:
        for i in range(3):
            out.append(int(255 * min(1.0, p[i] * gain[i] / top) ** (1 / 2.2)))
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
w, h = len(cells[0]), len(cells)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + \
      chunk(b'IDAT', zlib.compress(bytes(out), 9)) + chunk(b'IEND', b'')
open(dst, 'wb').write(png)
print('wrote %s %dx%d; channel means r g b %.1f %.1f %.1f; scale top %.1f' % (dst, w, h, *mean, top))
