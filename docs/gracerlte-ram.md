# RAM on the Note FE

**Goal:** give iOS as much of the Note FE's 4 GB as the hardware allows.
**Realistic ceiling: about 3.6 GiB (3678 MiB).** The rest belongs to TrustZone, the bootloader and the display, and Android doesn't get it either (Android on this phone shows about 3.6 GB total).

## Where the 4 GB goes

| Physical range | Size | What | iOS? |
|---|---|---|---|
| `0x880000000–0x900000000` | 2048 MiB | DRAM bank 2, no reservations | ✅ boot bank (already in the S7 port) |
| `0x80000000–0x94000000` | 320 MiB | S-Boot load area, payload, ESS, Wi-Fi rings, GPU pool, 2nd panel buffer, S-Boot logs | ❌ port + bootloader |
| `0x94000000–0xa0000000` | 192 MiB | free | ✅ stock |
| `0xa0000000–0xa0800000` | 8 MiB | ECT + default surface | ❌ |
| `0xa0800000–0xb1000000` | 264 MiB | free | ✅ stock |
| `0xb1000000–0xb1200000` | 2 MiB | TIMA | ❌ secure |
| `0xb1200000–0xcd000000` | 446 MiB | crypto + video ION (reusable) | ✅ stock |
| `0xcd000000–0xcd800000` | 8 MiB | gpu_crc | ❌ secure |
| `0xcd800000–0xd0800000` | 48 MiB | gpu_buffer (reusable) | ✅ stock |
| `0xd0800000–0xdec00000` | **228 MiB** | **camera ION** (not secure, not no-map) | 🆕 level `camera` |
| `0xdec00000–0xe2a00000` | 62 MiB | free | ✅ stock |
| `0xe2a00000–0xe3a00000` | 16 MiB | panel scanout buffer (S-Boot) | ❌ |
| `0xe3a00000–0xf0000000` | 198 MiB | free | ✅ stock |
| `0xf0000000–0xf8800000` | **136 MiB** | **modem_if** (CP memory; never booted under iOS) | 🧪 level `max` |
| `0xf8800000–0xfc000000` | 56 MiB | free | ✅ stock |
| `0xfc000000–0xfdc00000` | 28 MiB | secure_camera | ❌ secure |

Bank 1 on the Note FE ends at `0xfdc00000` (the S7's goes 8 MiB further). Sources: `exynos8890-rmem.dtsi` and `exynos8890-gracelte_common.dtsi` in LineageOS `android_kernel_samsung_universal8890` (`lineage-18.1`). The Note FE's reserved-memory map is the same as the S7's.

## Confirmed on the phone (2026-11-10)

The live device tree's memory and reserved-memory nodes (`phone-info/dt-memory.txt`) are **identical** to the built-in map.
Every area S-Boot names on the command line falls inside `0x80000000–0x94000000`, which the port already avoids, except
`s3cfb.bootloaderfb=0xd8000000`. That address is inside the camera area, so the `camera` and `max` levels keep 16 MiB
there out (`0xd8000000–0xd9000000`) until the probe test shows where the panel really scans out.

## Levels (`gracerlte/notefe-ram-banks.py --cmdline phone-info/cmdline.txt`)

| Level | Total for iOS | Boot image | Risk |
|---|---|---|---|
| `stock` | 3314 MiB | `build/boot/xnu-boot-stock.img` | Same as the S7 port (ADT byte-identical to `herolte-adt-ram-banks.py` output) |
| `camera` | 3526 MiB | `build/boot/xnu-boot-camera.img` | Low: plain RAM unless Android's camera driver runs |
| `max` | **3662 MiB** | `build/boot/xnu-boot-max.img` | Untested: if TrustZone guards the modem area anyway, the kernel panics on first use. A log entry, no damage |

ADTs: `build/adt/notefe-{stock,camera,max}.adt`. Payloads: `build/payload/payload-*.bin`. If the probe shows the panel
really is at `0xe2a00000`, drop `s3cfb.bootloaderfb` from the cut list for +16 MiB (3542 / 3678).

The kernel needs no change: patch 0326 takes up to 16 banks, and these use 6–8. Only the device tree (ADT) differs.

## Test order

1. **Bring-up with `stock`.** Get the phone to the home screen first, so RAM isn't a variable.
2. **`camera`.** Use the phone for a while: open many apps, then Safari with many tabs. Pull the log and look for `panic`, `tt_entry_free` or `vm_page` assertions.
3. **`max`.** Same test. If it panics early, go back to `camera`.
4. Check the live map with `gracerlte/collect-phone-info.sh` (in TWRP). It reads the phone's own device tree and `/proc/cmdline`, then reruns every level against them (`phone-info/ram-*.txt`). If the phone's S-Boot names other areas on the command line, they are cut out automatically. **Rebuild the ADTs from the live device tree before flashing:**

```bash
python3 gracerlte/notefe-ram-banks.py build/adt/herolte.adt build/adt/notefe-max.adt --level max \
  --fdt phone-info/live.dtb --cmdline phone-info/cmdline.txt
```

## Beyond 3.6 GiB (not done, research)

The only big area left is the 320 MiB at `0x80000000–0x94000000`. After the loader has copied XNU into bank 2, the S-Boot load area and the appended payload (`0x800bc000`, about 20 MiB) are dead memory. Reclaiming them means checking what the kernel still reads there after boot (the ADT and boot args, `0x8f…` Wi-Fi/GPU/log blocks). At most about 80–100 MiB more, for real loader/kernel work.
