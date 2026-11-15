#!/usr/bin/env python3
"""Read-only helper for one thin arm64 Mach-O (a standalone iOS binary): strings, xrefs, disassembly.
  build/venv/bin/python gracerlte/macho-re.py FILE str TEXT | xref ADDR | dis ADDR [N] | ptr ADDR | imports
CFString literals: 'str' also prints the __cfstring record that points at the C string."""
import struct, sys, capstone
f, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
data = open(f, 'rb').read()
ncmds = struct.unpack_from('<I', data, 16)[0]
off, sects = 32, []
for _ in range(ncmds):
    cm, size = struct.unpack_from('<II', data, off)
    if cm == 0x19:
        nsect = struct.unpack_from('<I', data, off + 64)[0]
        for s in range(nsect):
            so = off + 72 + 80 * s
            sect = data[so:so+16].split(b'\0')[0].decode(); seg = data[so+16:so+32].split(b'\0')[0].decode()
            addr, ssize, foff = struct.unpack_from('<QQI', data, so + 32)
            sects.append((seg, sect, addr, ssize, foff))
    off += size
def va2off(va):
    for seg, sect, a, s, fo in sects:
        if a <= va < a + s: return fo + va - a
def off2va(o):
    for seg, sect, a, s, fo in sects:
        if fo <= o < fo + s and fo: return a + o - fo
def sect_of(va):
    for seg, sect, a, s, fo in sects:
        if a <= va < a + s: return f'{seg},{sect}'
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
def ptrs(target):
    for seg, sect, a, s, fo in sects:
        if seg == '__TEXT' or not fo: continue
        for k in range(0, s - 7, 8):
            w = struct.unpack_from('<Q', data, fo + k)[0]
            if (w & 0xFFFFFFFFF) == (target & 0xFFFFFFFFF): yield a + k
def xrefs(target):
    for seg, sect, a, s, fo in sects:
        if sect != '__text': continue
        n = s // 4; words = struct.unpack_from(f'<{n}I', data, fo); page = target & ~0xfff
        for i, w in enumerate(words):
            pc = a + 4 * i
            if (w & 0xfc000000) in (0x94000000, 0x14000000):
                imm = w & 0x3ffffff
                if imm & (1 << 25): imm -= 1 << 26
                if pc + 4 * imm == target: yield pc
                continue
            if (w & 0x9f000000) != 0x90000000: continue
            imm = ((w >> 29) & 3) | (((w >> 5) & 0x7ffff) << 2)
            if imm & (1 << 20): imm -= 1 << 21
            if (pc & ~0xfff) + (imm << 12) != page: continue
            rd = w & 31
            for j in range(i + 1, min(i + 8, n)):
                w2 = words[j]
                if (w2 & 0xffc00000) == 0x91000000 and ((w2 >> 5) & 31) == rd and page + ((w2 >> 10) & 0xfff) == target: yield pc; break
                if (w2 & 0xffc00000) == 0xf9400000 and ((w2 >> 5) & 31) == rd and page + ((w2 >> 10) & 0xfff) * 8 == target: yield pc; break
if cmd == 'str':
    k = 0
    while (k := data.find(args[0].encode(), k)) >= 0:
        s = data.rfind(b'\0', 0, k) + 1; e = data.find(b'\0', k); va = off2va(s)
        print(f'{va:#x} {sect_of(va)} {data[s:e][:150]!r}')
        for p in ptrs(va): print(f'   pointed to from {p:#x} {sect_of(p)}  (cfstring record at {p-16:#x} if __cfstring)')
        k = e
elif cmd == 'xref':
    for x in xrefs(int(args[0], 16)): print(hex(x))
elif cmd == 'ptr':
    for p in ptrs(int(args[0], 16)): print(hex(p), sect_of(p))
elif cmd == 'dis':
    a = int(args[0], 16); n = int(args[1]) if len(args) > 1 else 40
    for ins in md.disasm(data[va2off(a):va2off(a) + 4 * n], a): print(f'{ins.address:#x}  {ins.mnemonic:8} {ins.op_str}')
elif cmd == 'sects':
    for s in sects: print(s[0], s[1], hex(s[2]), hex(s[3]))
