#!/usr/bin/env python3
"""A frame saved from /dev/hakios-camera (struct hakios_camera_frame + MIPI RAW10, the S9 ports' protocol) -> the
   8-bit Bayer file cam-debayer.py reads (8-byte header, every other 2x2 cell). cam-devframe.py IN OUT.raw8"""
import sys, struct
d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'RWFRAME1', d[:8]
hb, w, h, stride, fmt, bayer, black = struct.unpack('<7I', d[8:36])
seq, = struct.unpack('<Q', d[40:48]) if hb >= 48 else (0,)
print('header %d bytes: %dx%d stride %d format %d bayer %d black %d sequence %d' % (hb, w, h, stride, fmt, bayer, black, seq))
px = d[hb:]
rows = []
for y in range(h):
    if (y & 3) >= 2:
        continue
    line = px[y * stride:(y + 1) * stride]
    out = bytearray()
    for x in range(0, w, 4):
        o = x * 5 // 4
        out += bytes((line[o], line[o + 1]))       # every other 2x2 cell: pixels x, x+1 of each 4
    rows.append(bytes(out))
open(sys.argv[2], 'wb').write(struct.pack('<II', w // 2, h // 2) + b''.join(rows))
print('wrote', sys.argv[2], w // 2, 'x', h // 2)
