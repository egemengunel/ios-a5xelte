#!/usr/bin/env python3
"""Small static reverse-engineering helper for the iOS 16.7.16 dyld shared cache (read-only, local).

Run with the project venv (capstone):  build/venv/bin/python gracerlte/dsc-re.py DSC_DIR COMMAND ...

  str  TEXT                 C strings containing TEXT: unslid address + image
  ptr  ADDR                 8-byte words in the cache equal to ADDR (CFString records, selector refs, ...)
  xref ADDR IMAGE_SUBSTR    code in that image that loads ADDR (ADRP+ADD / ADRP+LDR pairs)
  dis  ADDR [COUNT]         disassembly, BL/B targets named from DSC_DIR/symindex.bin
  fn   ADDR                 the symbol containing ADDR
  img  SUBSTR               images whose path contains SUBSTR, with load address and text size
  sym  REGEX                symbols matching REGEX

DSC_DIR needs symindex.bin (ios-a5xelte/tools/herolte-dsc-sym.py DSC_DIR build).
"""
import bisect, importlib.util, os, pickle, re, struct, sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('dscsym', os.path.join(here, '..', 'ios-a5xelte', 'tools', 'herolte-dsc-sym.py'))
dscsym = importlib.util.module_from_spec(spec); spec.loader.exec_module(dscsym)

d, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
c = dscsym.Cache(d)
idx = pickle.load(open(os.path.join(d, 'symindex.bin'), 'rb'))
imgs, syms = idx['imgs'], idx['syms']
vals = [v for v, _ in syms]
loads = [l for l, _, _ in imgs]


def image_of(a):
    i = bisect.bisect_right(loads, a) - 1
    if i >= 0 and a < imgs[i][0] + imgs[i][1]:
        return imgs[i][2]
    return '?'


def name_of(a):
    j = bisect.bisect_right(vals, a) - 1
    if j < 0:
        return hex(a)
    v, n = syms[j]
    return f'{n}+{a - v:#x}' if a != v else n


def stub_target(a):
    """Name a branch target that is a stub: adrp x16 / ldr x16, [x16, #off] / br x16 -> the GOT's pointer."""
    b = c.read(a, 12)
    if not b:
        return None
    w1, w2, w3 = struct.unpack('<3I', b)
    if (w1 & 0x9f00001f) != 0x90000010:
        return None
    imm0 = ((w1 >> 29) & 3) | (((w1 >> 5) & 0x7ffff) << 2)
    if imm0 & (1 << 20):
        imm0 -= 1 << 21
    if (w2 & 0xffc003ff) == 0x91000210 and w3 == 0xd61f0200:          # adrp/add/br x16: direct island
        return 'island->' + name_of((a & ~0xfff) + (imm0 << 12) + ((w2 >> 10) & 0xfff))
    if (w2 & 0xffc003ff) != 0xf9400210:
        return None
    imm = ((w1 >> 29) & 3) | (((w1 >> 5) & 0x7ffff) << 2)
    if imm & (1 << 20):
        imm -= 1 << 21
    got = (a & ~0xfff) + (imm << 12) + ((w2 >> 10) & 0xfff) * 8
    v = c.read(got, 8)
    if not v:
        return None
    ptr = struct.unpack('<Q', v)[0] & 0xFFFFFFFFF
    if ptr < 0x180000000:
        ptr += 0x180000000
    return 'stub->' + name_of(ptr)


def segments(load):
    hdr = c.read(load, 32)
    ncmds, sz = struct.unpack_from('<II', hdr, 16)
    cmds = c.read(load + 32, sz)
    off, out = 0, []
    for _ in range(ncmds):
        cm, size = struct.unpack_from('<II', cmds, off)
        if cm == 0x19:
            nsect = struct.unpack_from('<I', cmds, off + 64)[0]
            for s in range(nsect):
                so = off + 72 + 80 * s
                sect = cmds[so:so + 16].split(b'\0')[0].decode()
                seg = cmds[so + 16:so + 32].split(b'\0')[0].decode()
                addr, ssize = struct.unpack_from('<QQ', cmds, so + 32)
                out.append((seg, sect, addr, ssize))
        off += size
    return out


def find_image(sub):
    m = [(l, t, p) for l, t, p in imgs if sub in p]
    if not m:
        sys.exit(f'no image matching {sub}')
    exact = [x for x in m if os.path.basename(x[2]) == sub]
    return (exact or m)[0]


if cmd == 'str':
    needle = args[0].encode()
    for addr, size, m, foff in c.maps:
        start = foff
        while True:
            k = m.find(needle, start, foff + size)
            if k < 0:
                break
            s = m.rfind(b'\0', foff, k) + 1
            e = m.find(b'\0', k)
            va = addr + (s - foff)
            print(f'{va:#x}  {os.path.basename(image_of(va))}  {m[s:e][:160].decode("utf-8", "replace")!r}')
            start = e + 1
elif cmd == 'ptr':
    target = int(args[0], 16)
    lo36 = target & 0xFFFFFFFFF
    for addr, size, m, foff in c.maps:
        data = m[foff:foff + size]
        pat = struct.pack('<I', lo36 & 0xffffffff)
        k = 0
        while True:
            k = data.find(pat, k)
            if k < 0:
                break
            if k % 8 == 0:
                w = struct.unpack_from('<Q', data, k)[0]
                if (w & 0xFFFFFFFFF) == lo36:
                    va = addr + k
                    print(f'{va:#x}  {os.path.basename(image_of(va))}  word {w:#x}')
            k += 4
elif cmd == 'xref':
    target = int(args[0], 16)
    load, tsize, path = find_image(args[1])
    for seg, sect, addr, ssize in segments(load):
        if sect not in ('__text', '__auth_stubs', '__stubs') or seg != '__TEXT':
            continue
        code = c.read(addr, ssize)
        n = ssize // 4
        words = struct.unpack_from(f'<{n}I', code)
        page = target & ~0xfff
        for i, w in enumerate(words):
            if (w & 0x9f000000) != 0x90000000:
                continue
            pc = addr + 4 * i
            imm = ((w >> 29) & 3) | (((w >> 5) & 0x7ffff) << 2)
            if imm & (1 << 20):
                imm -= 1 << 21
            if (pc & ~0xfff) + (imm << 12) != page:
                continue
            rd = w & 31
            for j in range(i + 1, min(i + 8, n)):
                w2 = words[j]
                lo = None
                if (w2 & 0xffc00000) == 0x91000000 and ((w2 >> 5) & 31) == rd:      # ADD imm
                    lo = (w2 >> 10) & 0xfff
                elif (w2 & 0xffc00000) == 0xf9400000 and ((w2 >> 5) & 31) == rd:    # LDR x, [x, #imm*8]
                    lo = ((w2 >> 10) & 0xfff) * 8
                if lo is not None and page + lo == target:
                    print(f'{pc:#x}  {name_of(pc)}')
                    break
elif cmd == 'dis':
    import capstone
    a = int(args[0], 16)
    count = int(args[1]) if len(args) > 1 else 40
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    code = c.read(a, 4 * count)
    for ins in md.disasm(code, a):
        note = ''
        if ins.mnemonic in ('bl', 'b') and ins.op_str.startswith('#'):
            t = int(ins.op_str[1:], 16)
            note = '  ; ' + (stub_target(t) or name_of(t))
        elif ins.mnemonic == 'adrp':
            pass
        print(f'{ins.address:#x}  {ins.mnemonic:8} {ins.op_str}{note}')
elif cmd == 'fn':
    for x in args:
        a = int(x, 16)
        print(f'{a:#x}  {os.path.basename(image_of(a))}  {name_of(a)}')
elif cmd == 'img':
    for l, t, p in imgs:
        if args[0] in p:
            print(f'{l:#x} {t:#x} {p}')
elif cmd == 'sym':
    r = re.compile(args[0])
    for v, n in syms:
        if r.search(n):
            print(f'{v:#x}  {n}')
else:
    sys.exit(__doc__)
