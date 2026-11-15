# What the other ports did, and what we can take (2026-11-11)

Repos read (shallow clones in the session scratchpad, not copied here):

| Repo | Phone | Why it matters to us |
| --- | --- | --- |
| [dipa-studio/ios-sweet](https://github.com/dipa-studio/ios-sweet) | Redmi Note 10 Pro | The original; our `ios-a5xelte` base descends from it |
| [DenialOfGravity/ios-redfin](https://github.com/DenialOfGravity/ios-redfin) | Pixel 5 (SD765G) | Cellular: `ws-n-*` branches |
| [coreycusick/ios-guacamole `sweet-bluetooth-audio`](https://github.com/coreycusick/ios-guacamole/tree/sweet-bluetooth-audio) | OnePlus 7 Pro (SD855) | Bluetooth up to A2DP with AirPods/Beats |
| [hesm4tt/ios-cubs](https://github.com/hesm4tt/ios-cubs) | Pixel 11 | iOS 16.5 source dump (overlay + tools), nothing Exynos-specific |
| [danstronics/ios-s9plus-exynos](https://github.com/danstronics/ios-s9plus-exynos) | Galaxy S9 (Exynos 9810) | **An Exynos UART + Broadcom HCI driver** (`core/drivers/bluetooth/hakios.bcm4361_bt.c`, APSL 2.0) |

## Bluetooth: the best next feature for us

How iOS 16's stack reaches an iPhone X's UART Bluetooth (guacamole's reverse engineering, `research/bluetooth/transport.md`
there): BlueTool and bluetoothd don't open a tty. They open a **kernel control socket** `com.apple.uart.bluetooth`
(bluetoothd's H4BC transport: `com.apple.uart.sk.bluetooth`), set termios through socket options, and bluetoothd then
asks for a **Skywalk channel** and moves H4 bytes through its rings. A2DP audio also needs a Skywalk user-pipe nexus,
which needs `PRIV_SKYWALK_REGISTER_USER_PIPE` (no entitlements on our kernels). Guacamole's kernel patches 0220-0223 do
all of this and touch no hardware. They port as they are.

Guacamole's chip is a Qualcomm WCN3998, so their bridge has to fake every Broadcom vendor command (0xFCxx) that
BlueTool's D22 boot script sends. **Ours is a Broadcom BCM4359, the family iOS's stack was written for.** The vendor
commands mean something to our chip. We filter only the firmware download and baud change, and pass the rest.

The hardware side is simpler than on the S9 (no I2C GPIO expander). From the phone's own DTB:

| | Note FE |
| --- | --- |
| UART | UART1 `0x14c20000` (pinctrl "btdefault"), IRQ SPI 0x1b0, 256-byte FIFO, pins gpe0-0..3 function 2 (RX, TX, RTS, CTS) |
| BT_REG_ON | gpj1-7, a plain SoC GPIO (PERIC1 pins `0x14cc0000` + 0x60) |
| BT_WAKE | gpi2-3 (`0x10e60000` + 0x20) |
| HOST_WAKE | gpa2-3 (ALIVE `0x10580000` + 0x40) |
| Clocks | CMU_TOP SCLK_PERIC1_UART1 (mux 0x354, div 0x4b4, enable 0x960); CMU_PERIC1 `0x14c80000` gates 0x800 bit 13 / 0x860 bit 0, Q-state 0x2424 |
| Firmware | `bcm4359C0_murata.hcd` in VENDOR (our module is Murata, as for Wi-Fi) |

The S9 driver already covers every protocol step on an Exynos UART: 115200 8N1 with RTS/CTS, HCI_Reset, Download
Minidriver 0xFC2E, the .hcd records one by one, Launch_RAM, then 0xFC18 to 4 Mbaud. It needs new register addresses,
not new logic. Our plan, with no busy-polling userland bridge (guacamole's ran at 99% CPU, and heat is already our
problem):

1. **0432 (built): read-only probe.** `sysctl kern.notefe_bt=2` logs the UART1 clocks, the four pins and (only when both
   clocks read as on) the UART registers. The bot runs it at the start of each run. Writes nothing.
2. UART1 up in loopback (clocks on, pins function 2, 115200); no chip involved.
3. BT_REG_ON high, then HCI_Reset and Read Local Version (Broadcom = manufacturer 0x000F); then the .hcd patch.
4. Guacamole 0220-0223 in our kernel, with the bridge **inside the kernel** and the UART on its interrupt (our GIC
   routing from 0415). BlueTool's 0xFC download and baud commands are answered locally.
5. bluetoothd back in launchd (it was removed because it kept retrying), Settings > Bluetooth, then A2DP. Guacamole's
   0226-0229 IOAudio2 stand-ins are the route-selection work after that.

Risks: wrong pin writes could disturb Wi-Fi (separate WL_REG_ON, so low); Wi-Fi/BT coexistence is not configured
anywhere yet; A2DP adds CPU (SBC encode in bluetoothd).

## Cellular: what "the common part" really is

Redfin's cellular is two layers:

* **Modem-specific (Qualcomm only):** `phone/wifi/cell.c`, a QMI client over QRTR (DMS, UIM, NAS: card status, signal,
  operating mode, SIM PIN). The iPhone X we emulate (iPhone10,3) has a **Qualcomm** baseband, so in branch `ws-n-abp`
  they even run Apple's real CommCenter. They add an AppleBasebandPCI stand-in, patch `abm::shouldBoot()` to
  "fake boot", and pipe CommCenter's QMUX frames to the real modem. That works only because both ends speak QMI.
* **iOS-side, modem-agnostic (what the S20 dev reuses):** `SweetCT.m` is an in-process CommCenter stand-in behind
  CoreTelephonyClient's XPC proxies (answers getSubscriptionInfo, getActiveContexts, ...). `SweetCell.m` drives the
  status-bar signal from a status file. SweetPIN gives the SIM PIN alert. Any modem can feed these, through a small
  daemon that writes the status.

The Note FE's modem is a Samsung **Shannon** (CP) on shared memory + mailbox, driven by Samsung's `cbd` (boot) and
`rild` (Samsung IPC). We can't run CommCenter, because it speaks QMI and Shannon doesn't. The S20 dev (Exynos 990, also
Shannon) faces the same problem. An honest staged path:

1. **CP boot from XNU** (the hard part, no one has shown it): Samsung's `modem_if`/`cbd` boot sequence from the
   LineageOS 8890 kernel (shared memory region, MCU_IPC mailbox, PMU CP reset/power registers, firmware from `RADIO`, NV
   data from `EFS`). EFS holds the IMEI and calibration data: **read only, backed up first**, never written.
2. Samsung IPC: enough of the protocol (libsamsung-ipc, ShannonRE) to read SIM status and signal.
3. Redfin's SweetCell/SweetCT with that status: bars and carrier in the status bar, Settings > Cellular.
4. Data (PDP context and a `pdp_ip0` interface), then SMS, then voice (voice also needs the audio DSP path).

This is weeks of work with a real chance of failing at step 1. Bluetooth first.

## Weather, App Store, Stocks: everyone hit the same wall

Guacamole's NOTES ("Known limit"): `AMSFairPlayGetHardwareInfo ... -42184` → `failed to generate mescal signature`,
and the requests are never sent. The S9+ repo had App Store/FairPlay injection experiments and **removed them after its own
legal review**. No port gets Weather or App Store data, and we still won't fake FairPlay or an Apple identity.
Things that do work elsewhere and are worth trying here: **News** (no Mescal), Safari, YouTube's non-DRM videos, and
third-party apps with their own back ends (sideloaded).

## Smaller ideas worth stealing

* Redfin `SweetControl.app`: an on-phone settings menu for kernel sysctls (our brightness/widget-cap knobs without a reboot).
* Redfin `SweetHUD`: an FPS overlay from a kernel frame counter (we have the counters already).
* Guacamole NOTES 499: their home-screen lag was **CPU hogs** (`vmd` 107% with no CoreTelephony, a busy-looping bridge).
  Same lesson as our widgets. Our daily-1 log has no `vmd` or CommCenter hog (wifid and locationd stay under 10%).

## Update 2026-11-14: UniXNU and HackiOS

* **[unixnu.com/devices](https://unixnu.com/devices/)** lists ~170 device records. UniXNU is its own framework: Mu-Silicium
  UEFI, then DarwinBoot, then XNU 10063 running **iPadOS 17.7** (the official Xiaomi Pad 6S Pro tree also builds 26/27
  profiles), with Metal on Adreno. Almost every device is Snapdragon.
* Exynos entries, all behind us:
  * [DokuroMitsukai/UniXNU-hero2lte](https://github.com/DokuroMitsukai/UniXNU-hero2lte), **Galaxy S7 Edge, Exynos 8890
    (our SoC).** Only the UEFI stage boots (display, keys, timer); the XNU handoff isn't validated. Its EFS/CPEFS backup
    note is worth following before any modem work.
  * [KosugiYukina/UniXNU-d1x](https://github.com/KosugiYukina/UniXNU-d1x), Note10 5G (Exynos 9825): boots, SpringBoard
    runs, no UI yet. **S Pen listed as "not started".**
  * starlte (S9, Exynos 9810): links to HakiOS/danstronics, already covered above.
  * Nothing there to take for our kernel; their UEFI route doesn't fit our S-Boot + shim chain.
* **[hackiosx.dev](https://hackiosx.dev)** (HackiOS) still lists Bluetooth, calls and complete Metal as open problems on
  every port. The Note 9 (Exynos 9810) S Pen on iOS from r/hackios isn't published yet ("revealed on GitHub later").

### S Pen on the Note FE: feasible, and nobody has published one

From our own DTB: Wacom **W9018** (`wacom,w9010` driver, ic_type 0x233a, firmware `epen/W9018_GRACE.bin`) at I2C
**0x56 on hsi2c@13660000**. It has its own IRQ, PDCT (pen detect) and FWE GPIOs and a 3.3 V enable on gpd0-1, a
0x3100 × 0x1b73 coordinate range and 4096 pressure levels. Samsung's `wacom_i2c` reads a fixed coordinate packet on each IRQ.
That's the same shape as our sec_ts touch path (0211 + sweet_hid_touch). Plan: power + read-only I2C query of the chip →
pen as a finger in iOS → pressure/hover as a stylus digitizer HID. Simpler than Bluetooth, and unique to the Note line.

### Update 2026-11-14: Shannon modem on the S20 (Exynos 990)

osas_lolpopz on r/hackios: the Galaxy S20's Samsung modem (proprietary firmware, the same Shannon family as ours)
**connects to a carrier** under iOS 16.5. So step 1 of our cellular plan (CP boot from XNU, Samsung IPC) is no longer
unproven. Code not released yet ("wait for this to release"). Their earlier post says they reuse redfin's iOS-side
"common part". When it's published: compare their CP boot (shared memory, mailbox, firmware load from RADIO) with the
8890's `modem_if`, and read EFS strictly read-only.
