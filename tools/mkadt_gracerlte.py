#!/usr/bin/env python3
"""mkadt_herolte.py for the Note FE: the same ADT, with the panel's framebuffer at 0xd8000000 (scan probe 2).
Same arguments as ios-a5xelte/tools/mkadt_herolte.py, e.g.  mkadt_notefe.py OUT.adt --bank2 --bank2-mb 2048 --iphone8
Runs the upstream script unchanged except for its FB_BASE line (asserted to exist exactly once).
--iphone8plus: an iPhone 8 Plus screen (414x736 points @3x = 1242x2208, the panel's 16:9, 1.16x scale to 1440x2560 instead
of 1.92x: sharper text) with a Home button, as --iphone8 has one. Boot args then sweetfb_lw=1242 sweetfb_lh=2208."""
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.join(here, '..', 'ios-a5xelte')
src_path = os.path.join(repo, 'tools', 'mkadt_herolte.py')
src = open(src_path).read()
old = 'FB_BASE, FB_WIDTH, FB_HEIGHT = 0xe2a00000, 1440, 2560'
assert src.count(old) == 1, 'mkadt_herolte.py FB_BASE line changed'
src = src.replace(old, 'FB_BASE, FB_WIDTH, FB_HEIGHT = 0xd8000000, 1440, 2560  # Note FE')
plus = '--iphone8plus' in sys.argv
if plus:
    sys.argv = [a for a in sys.argv if a != '--iphone8plus'] + ['--canvas', '1242x2208']
    hook = "        set_prop(product, 'artwork-scale-factor', mkadt.u32(3))\n"
    assert src.count(hook) == 1, 'mkadt_herolte.py 8 Plus block changed'
    src = src.replace(hook, hook + "        set_prop(child(root, 'buttons'), 'home-button-type', mkadt.u32(1))  # Note FE: 8 Plus has a Home button\n")
# Note FE 0435: the iPhone X's Bluetooth node, as ios-guacamole's mkadt.py (D22AP /arm-io/uart1/bluetooth's properties:
# bluetooth,n88, encoding 3, Apple IDs, coex 2), directly under /arm-io so the platform expert makes it a nub (under uart1
# bluetoothd still found "no bluetooth service in device tree"); the address is /chosen's mac-address-bluetooth0.
hook = "        ('compatible', mkadt.cstr('herolte,bcm4359')),\n    ]))\n"
assert src.count(hook) == 1, 'mkadt_herolte.py wlan node changed'
src = src.replace(hook, hook + '''    arm_io.children.append(mkadt.node('bluetooth', [
        ('device_type', mkadt.cstr('bluetooth')),
        ('compatible', mkadt.cstr('bluetooth,n88')),
        ('transport-speed', mkadt.u32(3000000)),
        ('transport-encoding', mkadt.u32(3)),
        ('vendor-id', mkadt.u32(0x05ac)),
        ('product-id', mkadt.u32(0x12a0)),
        ('coex', mkadt.u32(2)),
        ('local-mac-address', bytes((0x02, 0x48, 0x45, 0x52, 0x4f, 0x02))),
    ]))
    # Note FE 0458: the S9 ports' camera node (xnuloader cam=5): where MobileGestalt looks for cameras
    # (IODeviceTree:/arm-io/isp), so SpringBoard shows Camera.app. No compatible, no device_type: no driver matches it.
    arm_io.children.append(mkadt.node('isp', [
        ('camera-rear', mkadt.u32(1)),
        ('camera-front', mkadt.u32(1)),
    ]))
''')
sys.argv[1:] = [os.path.abspath(a) if a.endswith('.adt') else a for a in sys.argv[1:]]
sys.path.insert(0, os.path.join(repo, 'tools'))
os.chdir(repo)                                  # it reads research/ipsw-x/d22ap.adt relative to the repo
exec(compile(src, src_path, 'exec'), {'__name__': '__main__', '__file__': src_path})
