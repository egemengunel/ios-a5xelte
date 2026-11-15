#!/usr/bin/env python3
"""RAM banks for the Galaxy Note FE (SM-N935F): /chosen/hakios-ram-banks in the herolte ADT (kernel patch 0326).

  notefe-ram-banks.py IN.adt OUT.adt [--level stock|camera|max] [--fdt live.dtb] [--cmdline cmdline.txt]
  notefe-ram-banks.py --show [--level ...] [--fdt ...] [--cmdline ...] [--board herolte|gracerlte]

Bank 0 is always the boot bank of IN.adt (all 2 GiB of DRAM bank 2, from mkadt_herolte.py --bank2). The extra banks
are the pieces of DRAM bank 1 that are free under the chosen policy:

  stock   what ios-a5xelte's herolte-adt-ram-banks.py uses on the S7 (Samsung's 'reusable' ION areas count as RAM):
          about 3.3 GiB in all.
  camera  + the camera ION area (0xd0800000, 228 MiB). It is neither 'secure' nor 'no-map'; Linux maps it, and only
          Android's camera driver ever puts firmware there. iOS has no camera driver here.            ~3.5 GiB
  max     + modem_if (0xf0000000, 136 MiB). The CP is booted by Android's cbd and the region is protected by an SMC
          only then; S-Boot doesn't start the modem. UNTESTED: if TrustZone guards it anyway, the kernel faults
          when it first touches it (a panic in the log, no damage).                                     ~3.6 GiB

Never used, at any level: 'secure' areas that are not 'reusable' (gpu_crc, secure_camera), TIMA, the S-Boot/kernel
area 0x80000000-0x94000000 (loader, payload, ESS, Wi-Fi rings, GPU pool, second panel buffer, S-Boot's log areas),
the ECT + default surface at 0xa0000000, the panel at 0xe2a00000, and every area S-Boot names on Linux's command line.

--fdt: the phone's live device tree (/sys/firmware/fdt, saved by collect-phone-info.sh). Without it, the built-in
map from LineageOS's universal8890 kernel (exynos8890-rmem.dtsi + <board>_common.dtsi) is used.
--cmdline: the phone's /proc/cmdline from TWRP. Areas named there (ess_setup=, sec_tima_log=, ...) are cut out.
"""
import argparse, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'ios-a5xelte', 'tools'))

MiB = 1 << 20
GRAN = 0x4000                       # 16 KiB, what patch 0326 asserts

# --- built-in map (LineageOS android_kernel_samsung_universal8890, lineage-18.1) -------------------------------------
BANK1 = {'herolte': (0x80000000, 0x7E400000), 'gracerlte': (0x80000000, 0x7DC00000)}
RMEM = [  # name, base, size, flags
    ('tima_region',   0xB1000000, 0x0200000, {'removed-dma-pool'}),
    ('crypto',        0xC0000000, 0x0800000, {'reusable'}),
    ('video_fw',      0xC0800000, 0x0400000, {'secure', 'reusable'}),
    ('video_nfw',     0xC0C00000, 0x0400000, {'reusable'}),
    ('video_stream',  0xC1000000, 0x1400000, {'secure', 'reusable'}),
    ('video_frame',   0xC2400000, 0x6400000, {'secure', 'reusable'}),
    ('video_scaler',  0xC8800000, 0x4800000, {'secure', 'reusable'}),
    ('gpu_crc',       0xCD000000, 0x0800000, {'secure'}),
    ('gpu_buffer',    0xCD800000, 0x3000000, {'secure', 'reusable'}),
    ('camera',        0xD0800000, 0xE400000, {'recyclable'}),
    ('secure_camera', 0xFC000000, 0x1C00000, {'secure'}),
    ('modem_if',      0xF0000000, 0x8800000, set()),
]
# What this port itself (and S-Boot) keeps in bank 1, from ios-a5xelte (xnu_boot.c, patches 0307/0311/0322,
# herolte-adt-ram-banks.py).
PORT_USED = [
    ('S-Boot load area, payload, ESS, Wi-Fi rings, GPU pool, panel buffer 2, S-Boot logs', 0x80000000, 0x14000000),
    ('ECT + default surface (16 MiB: an 8 Plus canvas, 1242x2208x4, is 10.5 MB)',             0xA0000000, 0x1000000),
]
# The panel scanout buffer: S-Boot's, and the kernel's first flip target (patch 0322; HG_FB_PA).
PANEL = {'herolte': 0xE2A00000, 'gracerlte': 0xD8000000}  # Note FE: scan probe 2 + kernel patch 0400
# Areas the S7's S-Boot puts on Linux's command line rather than in the DTB (TWRP /proc/cmdline).
CMDLINE_KEYS = ('ess_setup', 'sec_tima_log', 'sec_avc_log', 'sec_tsp_log', 'auto_summary_log', 'sec_debug.base',
                'sec_log', 'sec_dbg', 'reserve_ramoops', 'ramoops', 'last_kmsg', 'sec_summary', 'kaslr_region',
                's3cfb.bootloaderfb')
CMDLINE_DEFAULT_SIZE = 0x400000     # when only an address is given: 4 MiB, generous
# Note FE: s3cfb.bootloaderfb=0xd8000000 (inside the camera area). A 1440x2560 ARGB panel is 14.1 MiB: keep 16 MiB.
CMDLINE_SIZE = {'s3cfb.bootloaderfb': 0x1000000}


def parse_fdt(blob):
    """Minimal FDT reader -> (memory banks, [(name, base, size, flags)])."""
    magic, totalsize, off_struct, off_strings = struct.unpack_from('>IIII', blob, 0)
    assert magic == 0xD00DFEED, 'not a flattened device tree'
    strings = blob[off_strings:]
    pos, stack, nodes = off_struct, [], []
    while True:
        tok, = struct.unpack_from('>I', blob, pos); pos += 4
        if tok == 1:
            end = blob.index(b'\0', pos); name = blob[pos:end].decode(); pos = (end + 4) & ~3
            node = {'name': name, 'props': {}, 'path': '/'.join(n['name'] for n in stack) + '/' + name}
            stack.append(node); nodes.append(node)
        elif tok == 2:
            stack.pop()
        elif tok == 3:
            ln, noff = struct.unpack_from('>II', blob, pos); pos += 8
            pname = strings[noff:strings.index(b'\0', noff)].decode()
            stack[-1]['props'][pname] = blob[pos:pos + ln]; pos = (pos + ln + 3) & ~3
        elif tok == 4:
            continue
        elif tok == 9:
            break
        else:
            raise ValueError(f'bad FDT token {tok}')

    def cells(node, key, default):
        v = node['props'].get(key)
        return struct.unpack('>I', v)[0] if v else default

    def regs(node, ac, sc):
        v = node['props'].get('reg', b'')
        words = struct.unpack(f'>{len(v) // 4}I', v)
        out, step = [], ac + sc
        for i in range(0, len(words) - step + 1, step):
            a = 0
            for w in words[i:i + ac]: a = (a << 32) | w
            s = 0
            for w in words[i + ac:i + step]: s = (s << 32) | w
            out.append((a, s))
        return out

    root = nodes[0]
    rac, rsc = cells(root, '#address-cells', 2), cells(root, '#size-cells', 1)
    mem = []
    for n in nodes:
        if n['path'].count('/') == 1 and n['props'].get('device_type', b'').rstrip(b'\0') == b'memory':
            mem += regs(n, rac, rsc)
    res = []
    rm = next((n for n in nodes if n['path'].endswith('/reserved-memory') and n['path'].count('/') == 1), None)
    if rm:
        ac, sc = cells(rm, '#address-cells', rac), cells(rm, '#size-cells', rsc)
        for n in nodes:
            if n['path'].startswith(rm['path'] + '/') and n['path'].count('/') == 2:
                flags = {k for k in ('secure', 'reusable', 'no-map', 'recyclable') if k in n['props']}
                comp = n['props'].get('compatible', b'').split(b'\0')[0].decode(errors='replace')
                if 'removed-dma-pool' in comp: flags.add('removed-dma-pool')
                for b, s in regs(n, ac, sc):
                    res.append((n['name'].split('@')[0], b, s, flags))
    # Hand-made (memreserve) entries in the header.
    off_rsv, = struct.unpack_from('>I', blob, 16)
    p = off_rsv
    while True:
        b, s = struct.unpack_from('>QQ', blob, p); p += 16
        if not s: break
        res.append(('/memreserve/', b, s, {'no-map'}))
    return mem, res


def parse_cmdline(text):
    out = []
    for word in text.split():
        if '=' not in word: continue
        key, val = word.split('=', 1)
        if not any(key.startswith(k) for k in CMDLINE_KEYS): continue
        m = re.fullmatch(r'(?:(0x[0-9a-fA-F]+|\d+[KkMm]?)@)?(0x[0-9a-fA-F]+)', val)
        if not m: continue
        size = m.group(1)
        if size is None: sz = CMDLINE_SIZE.get(key, CMDLINE_DEFAULT_SIZE)
        elif size.lower().startswith('0x'): sz = int(size, 16)
        else: sz = int(size[:-1]) * (1024 if size[-1] in 'Kk' else MiB) if size[-1] in 'KkMm' else int(size)
        out.append((key, int(m.group(2), 16), sz))
    return out


def allowed(name, flags, level):
    if 'removed-dma-pool' in flags or 'no-map' in flags: return False
    if 'reusable' in flags: return True
    if 'secure' in flags: return False
    if name == 'camera': return level in ('camera', 'max')
    if name.startswith('modem_if'): return level == 'max'
    return False


def subtract(ranges, cut):
    cb, ce = cut
    out = []
    for b, e in ranges:
        if ce <= b or cb >= e: out.append((b, e)); continue
        if b < cb: out.append((b, cb))
        if ce < e: out.append((ce, e))
    return out


def plan(bank1, reserved, cmdline_areas, level, panel):
    free = [bank1]
    why = []
    for name, b, s, flags in reserved:
        if not allowed(name, flags, level):
            free = subtract(free, (b & ~(GRAN - 1), (b + s + GRAN - 1) & ~(GRAN - 1)))
            why.append((b, s, f'{name} ({",".join(sorted(flags)) or "plain"})'))
    for name, b, s in PORT_USED + [('panel scanout buffer (S-Boot, kernel HG_FB_PA)', panel, 0x1000000)]:
        free = subtract(free, (b, b + s)); why.append((b, s, name))
    for name, b, s in cmdline_areas:
        free = subtract(free, (b & ~(GRAN - 1), (b + s + GRAN - 1) & ~(GRAN - 1)))
        why.append((b, s, f'cmdline {name}'))
    free = [(b, e) for b, e in free if e - b >= 4 * MiB]
    return free, sorted(why)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('inp', nargs='?'); ap.add_argument('out', nargs='?')
    ap.add_argument('--level', choices=('stock', 'camera', 'max'), default='camera')
    ap.add_argument('--board', choices=tuple(BANK1), default='gracerlte')
    ap.add_argument('--fdt'); ap.add_argument('--cmdline')
    ap.add_argument('--show', action='store_true')
    a = ap.parse_args()

    if a.fdt:
        mem, reserved = parse_fdt(open(a.fdt, 'rb').read())
        bank1 = next(((b, b + s) for b, s in mem if b == 0x80000000), None)
        assert bank1, f'no memory bank at 0x80000000 in {a.fdt}: {mem}'
        if not any(b == 0x880000000 and s >= 0x80000000 for b, s in mem):
            sys.exit(f'bank 2 is not 2 GiB at 0x880000000 in {a.fdt}: {[(hex(b), hex(s)) for b, s in mem]}')
        src = a.fdt
    else:
        b, s = BANK1[a.board]; bank1 = (b, b + s); reserved = RMEM; src = f'built-in {a.board} map'
    cmd = parse_cmdline(open(a.cmdline).read()) if a.cmdline else []
    if not a.cmdline:
        # The S7's values, until the Note FE's own /proc/cmdline is read.
        cmd = [('ess_setup', 0x91200000, CMDLINE_DEFAULT_SIZE), ('sec_tima_log', 0x92e02000, 0x200000),
               ('sec_avc_log', 0x93004000, 0x40000), ('auto_summary_log', 0x93088000, 0x10000)]

    free, why = plan(bank1, reserved, cmd, a.level, PANEL[a.board])
    extra = sum(e - b for b, e in free)
    if a.show or not a.out:
        print(f'source: {src}; cmdline: {a.cmdline or "S7 defaults (read the Note FE one in TWRP!)"}; level {a.level}')
        print(f'bank 1: {bank1[0]:#x}-{bank1[1]:#x} ({(bank1[1] - bank1[0]) // MiB} MiB)')
        print('kept out:')
        for b, s, n in why: print(f'  {b:#011x} +{s // MiB if s >= MiB else s / MiB:>6} MiB  {n}')
        print('extra banks:')
        for b, e in free: print(f'  ({b:#x}, {e:#x}),   # {(e - b) // MiB} MiB')
        print(f'extra {extra // MiB} MiB + boot bank 2048 MiB = {(extra // MiB) + 2048} MiB')
        if not a.out: return

    import adt  # ios-a5xelte/tools/adt.py
    root, _ = adt.parse(open(a.inp, 'rb').read())
    chosen = next(c for c in root.children if c.name == 'chosen')
    base, = struct.unpack('<Q', chosen.prop('dram-base'))
    size, = struct.unpack('<Q', chosen.prop('dram-size'))
    assert base == 0x880000000, f'IN.adt must come from mkadt_herolte.py --bank2 (dram-base {base:#x})'
    banks = [(base, size)] + [(b, e - b) for b, e in free]
    assert len(banks) <= 16, 'HAKIOS_RAM_BANK_MAX is 16'
    for b, n in banks:
        assert b % GRAN == 0 and n % GRAN == 0, hex(b)
    chosen.props = [p for p in chosen.props if p[0] != 'hakios-ram-banks']
    chosen.props.append(('hakios-ram-banks', 0, b''.join(struct.pack('<QQ', b, n) for b, n in banks)))
    open(a.out, 'wb').write(adt.serialize(root))
    print(f'{a.out}: {len(banks)} banks, boot {size // MiB} MiB + extra {extra // MiB} MiB = {(size + extra) // MiB} MiB')


if __name__ == '__main__':
    main()
