# iOS 16 on the Galaxy Note FE (SM-N935F): install plan

Based on the Galaxy S7 port: <https://github.com/wardevsa/ios-a5xelte/tree/herolte>
(guide: `docs/herolte-howto.md`, branch state as of 7 Nov 2026). Read that guide alongside this plan.
This plan only adds the Note FE–specific checks and changes.

**Goal:** iPhone X iOS 16.7.16 running on the Note FE, with GPU, Wi-Fi and sound, as a demo device.
iOS 17 or newer is not possible: the Exynos 8890 has no pointer authentication (PAC).

---

## Why the Note FE should work

| Part | S7 (supported) | Note FE | Verdict |
|---|---|---|---|
| SoC / GPU | Exynos 8890 / Mali-T880 MP12 | same | ✅ |
| Storage | UFS at `155a0000.ufs` | same controller | ✅ Tools find `by-name/USERDATA`, not a fixed `sdaN` |
| Touch (`sec_ts`) | I²C `0x48` on `hsi2c@14E10000`, IRQ `gpa1-0`, regulators `tsp_io`/`tsp_avdd`, 28×16 grid | **identical** | ✅ |
| Alternative touch chip | STM FTS `0x49` | Atmel mXT `0x4a` | ⚠️ Only a problem if your unit has the Atmel chip (stage 0 checks this) |
| Buttons | Power, Vol ±, Home on gpio-keys | same four keys | ✅ |
| Audio codec | Cirrus CS47L91 | same | ✅ |
| Wi-Fi | BCM4359 | BCM4359 family | ✅ Probably works with your own firmware files |
| Panel | S6E3HF4 / S6E3HA3 | **S6E3HA5**, same 1440×2560 | ⚠️ The bootloader turns the panel on before iOS starts, so it probably works. Watch for a black or garbled screen |
| Charger / MUIC | MAX77854 | different charger IC | ⚠️ The battery % may be wrong. Not critical |
| S Pen, iris, USB-C | – | Note only | ❌ Won't work. Ignore |

(Source: `exynos8890-herolte_common.dtsi` vs `exynos8890-gracelte_common.dtsi`
in `LineageOS/android_kernel_samsung_universal8890`, branch `lineage-18.1`.)

---

## What you need

- The Note FE, charged above 60 %, plus a USB-C cable
- TWRP for `gracerlte` (you probably have it already)
- Mac: `adb` (`brew install android-platform-tools`), Python 3, an aarch64 bare-metal GCC
  (`brew install --cask gcc-aarch64-embedded`, or Arm GNU Toolchain `aarch64-none-elf`)
- A GitHub account: **one public fork** (kernel + Mesa builds) and **one private repo** (iOS root image).
  The private repo is required: Apple's files must never go into a public repo.
- About 25 GB free on the Mac (the root image is about 20 GiB unpacked)

---

## Stage 0: Inspect the phone (read only, about 20 min)

Nothing is written in this stage. Boot TWRP (**Power + Volume Down + Home**, then Power + Volume Up + Home), plug in, and run:

```bash
adb shell getprop ro.boot.bootloader          # expect N935F...
adb shell ls -l /dev/block/platform/155a0000.ufs/by-name/
adb shell blockdev --getsize64 /dev/block/platform/155a0000.ufs/by-name/BOOT
adb shell blockdev --getsize64 /dev/block/platform/155a0000.ufs/by-name/USERDATA
```

Write down:
- [ ] the partition **numbers** of `BOOT` and `USERDATA` (the S7 uses `sda5` and `sda18`, but yours may differ)
- [ ] the BOOT size in bytes (the S7 uses `41943040`, which is 40 MiB). Use **your** number in stage 4
- [ ] USERDATA is larger than 21 GiB (it should be about 50 GB on a 64 GB phone)

**Which touch chip do you have?** Boot Android once and run this over adb (needs root):

```bash
adb shell su -c 'ls /sys/bus/i2c/devices/ ; cat /sys/bus/i2c/devices/*/name' | grep -iE 'sec_ts|mxt|atmel|fts'
```

- `sec_ts`: ✅ supported, carry on.
- `atmel` / `mxt`: ❌ needs a new touch driver. Stop and reassess.

**Where is the Wi-Fi firmware?**

```bash
adb shell su -c 'ls /vendor/etc/wifi /system/etc/wifi 2>/dev/null'
```

Look for `bcmdhd_sta.bin*`, `bcmdhd_clm.blob` and `nvram.txt*`. Note which `_c0`/`_plus` variant you have.

**Gate:** carry on only if you have the `sec_ts` touch chip and found the BOOT and USERDATA partitions.

---

## Stage 1: Back everything up (about 30 min)

In TWRP:
1. **Backup** → tick Boot, System, Data, **EFS** (plus Vendor, if it's listed) → back up to internal storage.
2. Copy it off the phone: `adb pull /sdcard/TWRP ~/NoteFE-backup/`
3. Save a raw copy of BOOT (use the BOOT path from stage 0):
   ```bash
   adb shell dd if=/dev/block/platform/155a0000.ufs/by-name/BOOT of=/tmp/boot-stock.img
   adb pull /tmp/boot-stock.img ~/NoteFE-backup/
   ```
4. Copy the Wi-Fi files you found in stage 0 into `~/NoteFE-backup/wifi/`.
5. Optional safety net: download stock N935F firmware for Odin (for example with Samfirm or Frija).

USERDATA gets wiped in stage 5, which also deletes the TWRP backup stored on the phone (internal storage lives on USERDATA). **Don't skip step 2.**

---

## Stage 2: Builds on GitHub (mostly waiting, 1–3 h)

Follow guide steps 1–3 as written:

1. **Kernel:** fork `wardevsa/ios-a5xelte`, enable Actions, run **xnu** (`MACHINE_CONFIG=HEROLTE`).
   Download `xnu-kernel-macos-15-intel`, which contains `kernel.development.herolte`.
2. **iOS root:** push the `herolte` branch to a **private** repo as `ios-root-build` and run **ios-root**.
   Download `root.img.gz.part00..02`, `d22ap.adt` and `SHA256SUMS`. Put `d22ap.adt` in `research/ipsw-x/`.
3. **GPU userland:** run **mesa-ios** and download the `mesa-ios` artifact.

You use the S7 (`HEROLTE`) kernel unchanged at first. The SoC, touch and keys match, so try it as is before changing anything.

---

## Stage 3: Loader and device tree (on the Mac, about 15 min)

```bash
cd shim/herolte && CROSS=aarch64-none-elf- sh build.sh && cd ../..
python3 tools/mkadt_herolte.py herolte.adt --bank2 --bank2-mb 2048 --iphone8
```

Start with **2 GiB RAM** (skip `herolte-adt-ram-banks.py`). The extra-RAM step uses the S7's memory layout, and the Note FE's reserved regions may differ. Add it once everything else works.

Build the payload with the guide's `CMDLINE` (unchanged, under 608 characters, keep `-noprogress`):

```bash
python3 tools/mkpayload.py kernel.development.herolte herolte.adt payload.bin --cmdline "$CMDLINE"
```

---

## Stage 4: BOOT image (about 5 min)

```bash
python3 tools/herolte-pack-boot.py pack ~/NoteFE-backup/boot-stock.img \
  shim/herolte/out/xnu_boot.Image xnu-boot.img \
  --append payload.bin --partition-size <YOUR BOOT SIZE FROM STAGE 0>
```

This keeps your phone's own Samsung header and Note FE DTBs. First run `herolte-pack-boot.py` in its inspect mode (see `--help`) on `boot-stock.img`, and check that it parses your boot image cleanly. If it doesn't, your custom ROM's boot image may use a different format. In that case, take `boot.img` from the stock N935F firmware instead.

---

## Stage 5: Drop zone and flashing (about 1 h, mostly copying)

1. Build `drop/` as in guide step 5. The Wi-Fi files come from **your** backup (`~/NoteFE-backup/wifi/`, renamed to `fw.bin`, `clm.blob` and `nvram.txt`). `network.txt` holds your Wi-Fi name on line 1 and the password on line 2. **Never commit it.**
2. In TWRP, **unmount Data** (Mount menu).
3. Write the iOS root (resumable, checks every chunk):
   ```bash
   python3 tools/herolte-flash-root.py adb root.img.gz.part00 root.img.gz.part01 root.img.gz.part02 --state flash.state
   ```
4. Write the drop package (the guide's long `herolte-drop.py adb ...` command).
5. Write BOOT and verify it **before** rebooting:
   ```bash
   adb push xnu-boot.img /tmp/boot.img
   adb shell "dd if=/tmp/boot.img of=/dev/block/platform/155a0000.ufs/by-name/BOOT bs=1048576 conv=fsync"
   adb shell "head -c $(stat -f %z xnu-boot.img) /dev/block/platform/155a0000.ufs/by-name/BOOT | sha256sum"; shasum -a 256 xnu-boot.img
   ```
   (`stat -f %z` is the macOS form. The guide's `stat -c %s` is for Linux.) The two hashes must match.
6. `adb reboot`. The first boot takes several minutes.

---

## Stage 6: First boot, what you might see and what to do

| What you see | Likely cause | What to do |
|---|---|---|
| Apple logo, then lock screen | 🎉 It works | Wi-Fi should join about 1 min after the home screen |
| Home screen, but touch is dead | Touch power/reset or the chip ID check differs | Pull the log (below) and look for `sec_ts` / touch lines |
| Black or garbled screen, phone seems alive | Panel / DECON difference (S6E3HA5) | Pull the log, then try `sweetfb_gpu=0` |
| Boot loop or no logo | Early kernel or memory-map problem | Pull the log. If it's empty, go back to Android (below) |
| Battery % wrong or stuck | Different charger IC | Ignore for now |

Pull the log (TWRP: Power + Volume Down, then Power + Volume Up + Home):

```bash
python3 tools/herolte-log-pull.py adb boot.txt
```

The log can contain names of nearby Wi-Fi networks. Read it before sharing. If you get stuck, open an issue on the repo with the log and a photo of the screen, and say it's an **SM-N935F**. A first Note FE report is useful to the maintainer.

---

## Going back to Android (about 10 min)

1. Enter TWRP (Power + Volume Down + Home, then Power + Volume Up + Home).
2. Write the old boot image back:
   ```bash
   adb push ~/NoteFE-backup/boot-stock.img /tmp/
   adb shell "dd if=/tmp/boot-stock.img of=/dev/block/platform/155a0000.ufs/by-name/BOOT bs=1048576 conv=fsync"
   ```
3. **Wipe → Format Data** (type `yes`). This is required, because USERDATA now holds Apple's HFSX file system.
4. Push your TWRP backup back to the phone and **Restore** it, or flash your ROM zip again.
5. Reboot.

**If TWRP won't even start:** Download Mode lives in the bootloader, which this process never touches. Use **Power + Volume Down + Home** for Download Mode, then flash TWRP or stock N935F firmware with Odin.

The port never writes to the bootloader, SYSTEM, EFS, modem or other partitions. It only writes to **BOOT** and **USERDATA**.

---

## Checklist

- [ ] Stage 0: touch chip is `sec_ts`, partitions noted, BOOT size noted
- [ ] Stage 1: TWRP backup + `boot-stock.img` + Wi-Fi files copied to the Mac
- [ ] Stage 2: kernel, root image and Mesa artifacts downloaded
- [ ] Stage 3: `herolte.adt` + `payload.bin` built (2 GiB RAM first)
- [ ] Stage 4: `xnu-boot.img` built with your own BOOT size
- [ ] Stage 5: root, drop package and BOOT written, hashes match
- [ ] Stage 6: first boot, log pulled
- [ ] Later: extra RAM banks (`herolte-adt-ram-banks.py`), sideloaded open-source apps
