# Night of 2026-11-10/11: unattended iterations

Owner's permission (2026-11-11 ~00:15): write BOOT and the drop zone overnight without asking each time. Nothing else on
the phone is written. Every write is read back and verified. Loop: AUTOMATION.md.

## Boot 7 (00:48 → back in TWRP 01:05 by itself), kernel 0400-0411
**The unattended loop works end to end**: herotwrp brought the phone back to TWRP, the bot ran the whole plan.
* Bot: 12 of 12 apps launched (FrontBoard with "unlock device"), each scrolled and closed; home-screen swipes.
* Location Services switched on by the bot: Weather showed "Ankara" (owner).
* Charger: input limit 500 → 1500 mA (read back 0x2d); plugging/unplugging seen (`in=0 dtls=0x8 no cable` → `in=3
  charging`). The battery was at 100 %, so only top-off current (90-195 mA). The watchdog wasn't cleared once at 50 C:
  cut-off raised to 60 C (0413).
* Sandbox extensions now issued (0410): tccd "Failed to issue" count 0 (was every Photos request). Photos opens with "No
  content available" (owner), i.e. the library loads.
* Owner: wallpaper, apps load; Music opens (shows "offline"), Notes, Calendar widget, News load.
* **backboardd crashed** (the "progress view" restart the owner saw): a GPU buffer of ~5 MB failed with
  kIOReturnNoMemory (CREATE_BO err 12) when Safari opened; Mesa then used NULL. 0413 logs which step fails (GPU VA,
  page tables or kernel memory).
* **Weather, App Store, Music streaming cannot work**: their server requests are signed through FairPlay ("Mescal
  Failed ... Failed to fetch hardware info", AMSFairPlayGetHardwareInfo -42184). FairPlay needs Apple hardware identity
  (Secure Enclave); not something to fake. Local features of those apps can work.
* Performance: `duetexpertd` logged one error 981,345 times (damaged Biome stream file), keeping logd at 70-110 % CPU.
  The bot removes that cache once. CoreUI also logs an error + backtrace for screen subtype 1334 on every asset
  lookup (2,100 in Music): to fix with the canvas work.
* Extensions with "invalid sandbox or container: error 2" (Stocks/Reminders/Batteries intents, PhotosFileProvider):
  0412 (container paths) is built for the next boot.

## New tools tonight
* `gracerlte/cycle-collect.sh NAME`: waits for TWRP, pulls the kernel log, copies iOS's unified log store read-only
  (`hfs-read.py getdir`), decodes it with Mandiant's unifiedlog_iterator (`~/notefe-tools/unifiedlogs`, see
  INSTALLED.md) into one file per process (`logs/oslog/NAME-*.txt`), and writes `logs/NAME-summary.txt`.
* `gracerlte/bot` (FrontBoard launches, location switch, Biome cleanup), kernel `kern.notefe_hid` (0409).

## Boot 8 (01:20 → TWRP 01:34), kernel 0400-0413, same canvas/RAM/clocks as boot 7
| | boot 7 | boot 8 |
|---|---|---|
| frame time, mean (hakios-gl samples) | 12.2 ms | **8.9 ms** |
| frames over 16.7 ms | 150 of 674 (22 %) | **41 of 450 (9 %)** |
| backboardd crashes | 4 | **0** |
| "invalid sandbox or container" extensions | 4 kinds | **0** (0412: containers by HOME at exec) |
| other crashes | PassbookWidgets 32, CoreLocation helpers 20, biomed 6, … | PassbookWidgets 24, MailWidget 8 |
* Bot: 12/12 apps; Location already on; one damaged Biome stream file removed, duetexpertd's log storm gone.
* 0413's GPU failure report did not trigger (no buffer failed this run).
* Start-up CPU bursts remain (locationd 306 % at boot, SpringBoard up to 511 %, mediaserverd 313 %).

## Boot 9 (01:39), iPhone 8 Plus canvas: **did not come back**
The phone never returned to TWRP (and isn't visible over USB): it hung or panicked, which also stops the herotwrp
timer. It needs a force restart into TWRP (Power + Volume Down + Home, then Power + Volume Up + Home).
**Cause found (static, to confirm from its log):** the kernel puts the canvas surface at physical 0xa0000000
(SweetFramebuffer.cpp), and our RAM map kept only 8 MiB free there. An iPhone 8 canvas (750x1334x4 = 4 MB) fits; the
8 Plus one (1242x2208x4 = 10.5 MB) runs ~2.5 MB into RAM the kernel was given, i.e. the screen's pixels overwrite kernel
memory. The upstream `--canvas 1242x2208` option has the same problem on the S7 (never tested there).
Fix: `notefe-ram-banks.py` reserves 16 MiB at 0xa0000000 (costs 8 MiB of RAM), and kernel 0414 refuses a canvas
that doesn't fit (falls back to 750x1334 with a log line) instead of corrupting memory.
Nothing else was written after boot 9: the phone still has the boot 9 BOOT image. The known-good image is
`build/boot/notefe-boot-stock-bot.img` (boot 8).

## Built and waiting for the phone (nothing written after boot 9)
* Kernel 0400-0414 (`build/xnu-notefe/kernel.development.herolte`), RAM map with 16 MiB at 0xa0000000:
  `build/boot/notefe-boot-stock-bot.img` (iPhone 8 canvas, bot + herotwrp=720) and
  `build/boot/notefe-boot-stock-bot8p.img` (iPhone 8 Plus canvas). Stock RAM is now 3322 MiB (was 3330).
* Slow frames, measured (boot 8, 450 samples): fast frames 6.8 ms with ~31 draws; slow ones 28.7 ms with ~116 draws, mostly
  CPU time inside Mesa (wait 2.7 ms, copy 1.8 ms); the worst (100-190 ms) right after start or a new screen: first-time
  shader compiles. This Mesa build has its disk shader cache off: rebuilding Mesa with it on
  (`gracerlte/mesa/build-mesa-cache.sh`, in `~/notefe-mesa-build`).

## Morning plan (each boot is the same bot run, so the numbers compare)
1. Force restart into TWRP; I pull boot 9's log (a waiter does it as soon as adb sees TWRP) to confirm the hang cause.
2. Boot 10: kernel 0414 + iPhone 8 Plus canvas (`notefe-boot-stock-bot8p.img`).
3. Boot 11: + shader-cache Mesa (`MESA_SHADER_CACHE_DIR` in gl.env).
4. Boot 12: + big cores 2600 MHz (1075 mV, this chip's ASV table allows it).
5. Boot 13: + `max` RAM (3670 MiB).
6. Later: little cores 1066 → 1586 MHz (new PLL code: riskiest, last).

## Mesa with the shader cache (built 02:19, not on the phone yet)
* `gracerlte/mesa/build-mesa-cache.sh` = upstream build-mesa.sh with `-Dshader-cache=enabled`, run in `~/notefe-mesa-build`
  (no spaces; also needed Homebrew `pkgconf`). Panfrost keys its cache on the ELF build-id, which Mach-O has not:
  `gracerlte/mesa/patch-pan-disk-cache.py` uses the image's LC_UUID instead (a rebuilt Mesa never reads an old cache).
* Output `build/mesa-cache/lib/libOSMesa.8.dylib` (sha256 2ed6391e…); new imports are only libc directory/file calls and
  zlib (`/usr/lib/libz.1.dylib`), all on iOS 16. Upstream's stays in `build/mesa/lib`.
* `build/drop/gl.env` now also has `MESA_SHADER_CACHE_DIR=/private/var/mobile/Library/Caches/com.apple.backboardd.mesa`
  (backboardd runs as mobile). Use: `MESA=cache BOT=1 gracerlte/write-drop.sh` (boot 11 in the plan).

## Boot 10 (2026-11-11 10:09): iPhone 8 canvas + shader-cache Mesa
Owner chose to skip the 8 Plus canvas for now. Boot 9's log (`logs/boot-9.txt`, 1,456 lines) stops during service
start-up with no panic, which fits the canvas-overflow cause.
* BOOT `notefe-boot-stock-bot.img` (2d0b3d08…, kernel 0400-0414, 16 MiB at 0xa0000000), drop zone `MESA=cache BOT=1`.
* Versus boot 8: the Mesa build (shader cache in `/private/var/mobile/Library/Caches/com.apple.backboardd.mesa`) and 8 MiB
  less RAM. 0414 changes nothing on this canvas. The first run of a fresh cache only fills it, so the gain should show
  from the second boot on this image.
* Result (back in TWRP 10:22 by itself): bot 12/12, backboardd crashes 0, crashes PassbookWidgets 12, MailWidget 8,
  pkreporter 4. Charger 1500 mA, charging seen. Frames: 436 logged, mean 11.7 ms, 48 over 16.7 ms (boot 8: 8.9 ms, 41
  of 450). The cache filled: `Caches/com.apple.backboardd.mesa/mesa_shader_cache_db/part0/mesa_cache.db` 109 KB
  (Mesa 25's multi-part database). A cache-filling run compiles everything and also writes it, so it is not the
  comparison run.
* Boot 10b (10:29): same images, no write, just `adb reboot`, to measure with a warm cache.
* Boot 10b result (TWRP 10:42 by itself): bot 12/12, backboardd 0 crashes, same widget crashes. Frames 445, mean 9.8 ms,
  44 over 16.7 ms.

| frame times (ms) | boot 8 (upstream Mesa) | boot 10 (cache filling) | boot 10b (warm cache) |
|---|---|---|---|
| median | 5.9 | 5.9 | 6.0 |
| 90th percentile | 16.1 | 17.6 | 16.5 |
| 99th percentile | 35.2 | 71.4 | 44.7 |
| worst | 100 | 607 | 152 |
| frames over 50 ms | 1 | 8 | 3 |

**Verdict: the disk shader cache brings no measurable gain** (10b is within run-to-run noise of boot 8, slightly worse at
the tail). The slow frames are CPU work in Mesa per draw, not compiles that the cache can skip. Going back to upstream
Mesa (`BOT=1 gracerlte/write-drop.sh` without `MESA=cache`) for the next tests; the cache build stays in `build/mesa-cache`.

# Day of 2026-11-11: owner's go-ahead for autonomous work on the phone ("you're autonomous from now on")

## Boots 11-17 (each ~5 min now: the bot ends the run itself, kernel log only)
| boot | change | result |
|---|---|---|
| 11 | HERO_PROF=1 (upstream's backboardd sampler) | 31 % of busy samples in kernel calls (mach_msg2_trap), 12 % `surface_changed` (hakios-gl hashes up to 4 MB per IOSurface texture per frame, one serial multiply chain) |
| 12 | 0415 GPU job wait on the Mali IRQ (INTID 256-258, from TWRP's /proc/interrupts) instead of 10 us polling; hakios-gl hash in 8 lanes (`gracerlte/hakios-gl`, `build-hakiosgl.sh`) | IRQ works (73,728 jobs, 0 timeouts); surface_changed 11.8 % -> 1.7 %; frames rendered 9,400 -> 11,600 in the same run |
| 13 | 0416 bot asks for recovery when done (`r N` on kern.notefe_hid), herotwrp 420 s; 0417 hw.machine iPhone10,3 (was "iPad8,6" for iOS processes: CF missed `~iphone` resources) | **Control Center layout fixed** (owner); cycle 5 min |
| 14 | 0418 `backlight-control` on the display (OLED path) | **bad**: backboardd stalled, launches failed, assetsd 200 %: reverted in 0419 |
| 15 | 0419 SpringBoard bridge (BKSDisplayBrightnessGetCurrent -> kern.notefe_brightness) + GPU blend dimming in the panel copy (A + B*C, C = constant) | healthy again; dimming works; iOS ignored set requests (no backlight) |
| 16 | notefe_bl=1: AppleARMBacklight child of the display (IODisplayParameters 0-65536), after Scion's S9 port | **Control Center brightness slider works** (owner). CoreBrightness sets `brightness`/`backlight-level` (linear, 65536 = full) itself; the bridge is not needed |
| 17 | 0420: square-root curve (AMOLED gamma: slider half = 181/255, not 127), backlight on by default, bridge off, profiler off | (running) |

Not possible / not faked: Weather data, App Store, Music streaming (FairPlay, Apple hardware identity); cellular (Shannon modem: no
port has calls). Research sources: Scion-Project scion-kernel PRs 101/142 and scion-starlte README (brightness), hackiosx.dev.

## Boots 18-29: kernel call timing, CPU clock, zero-copy display attempt
* Boot 18 (0421, NOTEFE UC: backboardd's IOKit calls timed): GPU submits 69k calls / 16.3 s (GPU work itself);
  HeroGPU SyncBO (cache clean of a shared surface, up to 4 MB by VA) 4k calls / 4.5 s, 1.1 ms each, max 7 ms.
* Boot 19: big cores 2600 MHz (1112.5 mV, ASV): measured 2511 MHz, **no gain** (smooth 62 %, hitches 20 %): frames are not
  bound by CPU speed. Back to 2288.
* New measure (`cycle-summary.sh`): the display's own frame spacing while the bot runs. Boots 8-18 all ~65 % of frames
  one refresh apart, ~16 % hitches (3+ refreshes): the CPU-side fixes made backboardd cheaper, not the pacing.
* Community (2026-11-11): nobody has steady 60 fps (Scion S9 ~10 fps first pacing run; topaz 25-35 fps; the S20
  Exynos 990 port is smooth through Metal->Vulkan, impossible on Midgard: PanVK needs Bifrost+). Scion's display path:
  zero-copy scan-out with the DPP scaler.
* Zero-copy (0422-0430): only VGR0/VGR1 scale on the 8890 (Samsung vpp.h is_vgr; DISP1, powered, clock 900). Test 0424:
  VGR0 scales iOS's surface correctly (owner: status bar right size). 0425: backboardd's surfaces in the 16 MiB at
  0xa0000000, VGR0 flips. **On the phone the panel froze** (boots 23-28; console text or the first frame): the DECON is
  in command mode (GLOBAL_CONTROL 0x100113, HW trigger 0x1010); once window 0 is on VGR0 (CHMAP 5) it sends no more
  frames (line counter stuck at 1), and even G1 flips stop being taken. Window plane alpha (Samsung's wincon) also left
  its update pending. Not solved: likely DECON_F's resource routing for a DISP1 channel (RESOURCE_SEL_0/1 0x18/0x1c,
  DISP_CFG). **0431: off by default** (`notefe_zc=1` to try). Samsung source used: LineageOS
  android_kernel_samsung_universal8890 lineage-18.1, drivers/video/fbdev/exynos/decon_8890 (GPL), in the scratchpad only.
* Boot 29: the everyday setup again (backlight on, zero-copy off).
* **Everyday image on the phone (14:25):** `build/boot/notefe-boot-stock.img` (b7ed58b3…), kernel 0400-0431, boot line
  `gracerlte/cmdline.txt` (no herobot, no herotwrp, herolog removed; backlight on by kernel default, zero-copy off), drop
  zone without the bot (`gracerlte/write-drop.sh`). Back to TWRP: Power+VolDown+Home, then Power+VolUp+Home. For a test
  run again: `BOT=1 gracerlte/write-drop.sh` + `gracerlte/make-boot.sh gracerlte/cmdline-bot.txt bot` + `FAST=1
  gracerlte/cycle-collect.sh NAME`.
* **Daily use, heat (log `logs/daily-1.txt`, ~15 min):** CPU 675 % of 800 % on average, battery -0.9 to -1.1 A, SoC up
  to 56-61 C. Widgets at ~60 % of a core each the whole time despite `herowidgetcap=30` (the throttle lets about twice
  the figure through): CalendarWidgetExtension 59 % (SwiftUI loop), WeatherWidget 59 % and StocksWidget 56 % (no data
  without Apple's servers), Maps widget 46 %; backboardd ~105 % redrawing them. Everyday line now `herowidgetcap=8`
  (BOOT 02f122c1…, phone left in TWRP). Owner: remove the Calendar/Weather/Stocks widgets from the home screen and
  Today view. Note: herolog defaults to `tccd,assetsd` even when not on the line (herolte_gl.c).

## 2026-11-11 (evening): Bluetooth step 1, probe boot (bt-probe-1, kernel 0432)

Community research in COMMUNITY.md. `sysctl kern.notefe_bt=2` from the bot, read only:
* UART1 (0x14c20000) clocks are ON at boot (PERIC1 CG_CTRL_VAL 0x3ffffff, pclk_uart1 1, sclk_uart1 1, Q-state 3); its
  registers read as reset values (ULCON 0, UCON 0x3000, UTRSTAT 6 = TX empty): S-Boot never touched it. Safe to program.
* Clock source: CMU_TOP mux 0x200000 (parent 0 = BUS0_PLL, gate on), div 3 (/4); PERIC1 user mux bit 12 = 1 (TOP's
  clock, not OSCCLK). Rate still to work out from BUS0_PLL before setting a baud divisor.
* Pins: gpe0-0..3 function 0 (inputs, not UART yet); BT_REG_ON gpj1-7 input, low: the BCM4359's Bluetooth half is OFF.
  BT_WAKE gpi2-3 and HOST_WAKE gpa2-3 inputs, low.
* Frames unchanged (smooth 68 %, hitches 17 %). Phone back on the everyday image (40b811c9…, 0400-0432, non-bot drop).
Next (0433): pins to function 2, 115200 8N1 in internal loopback; then BT_REG_ON high, HCI_Reset / Read Local Version.

## 2026-11-14 (night): Bluetooth chip answers (bt-5, kernel 0433)

* UART1 clock: BUS0_PLL 1056 MHz (M 528, P 13, S 0) / 2 / 4 = **132 MHz**; 115200 = UBRDIV 70, UFRACVAL 9.
* Internal loopback: 16 of 16 bytes back, MATCH.
* BT_REG_ON (gpj1-7) high, then HCI over H4 at 115200 with RTS/CTS: HCI_Reset OK, **Read Local Version: HCI 8 (4.2),
  manufacturer 0x000f (Broadcom), LMP subversion 0x6106**; Read Local Name **"BCM4359C0"** (ROM, before the patch).
  The chip is switched off again after the test (level 6).
* Frames this run: smooth 72 %, hitches 14 %.
* bcm4359C0_murata.hcd pulled from VENDOR (read-only mount) to build/bt/ (private, not in git): 59439 bytes, 304 records
  (303 × 0xfc4c Write RAM, 1 × 0xfc4e Launch RAM).
* Bot: quick mode (QUICK=1 write-drop.sh) runs only the feature tests and returns to TWRP; bot.quick and bt.level are
  written on every bot run (the drop zone never deletes files).
Next: kernel 0434 (patch upload, level 7) in quick mode.

## 2026-11-14 (night): Bluetooth firmware running (bt-7b, kernel 0434, quick bot)

* First try: the patch never reached the phone (write-drop keys are relative to /private/var/herolte/; fixed).
* `bt-murata.hcd` loaded into the kernel through kern.notefe_bt_fw (59439 bytes); level 7: Download Minidriver, **304 of
  304 records accepted, 0 odd answers**, Launch RAM, reset. After the patch: rev 0x11ba (was 0x1000), local name
  **"BCM4359C0 Grace Murata 1JJ eLNA [Version: 0183.0442]"**. Took 6.8 s at 115200. Quick bot cycle: 105 s.
* iOS root (os.dmg, mounted read-only on the Mac): BlueTool knows BCM4357B1 "Olympic Apollo-E Murata/USI" among others;
  no /usr/share/firmware/bluetooth folder in the root.
Next: 0435, the iOS transport (guacamole's kernel controls + Skywalk channel) with the bridge in the kernel.

## 2026-11-14 (night): iOS Bluetooth transport registered (bt-8a, kernel 0435, level 8)

* New: kernel 0435 (guacamole 0220-0222's `com.apple.uart.bluetooth` + `com.apple.uart.sk.bluetooth` controls and
  Skywalk channel, with our bridge thread inside the kernel and polling the UART every 1 ms), an `/arm-io/bluetooth` ADT
  node (bluetooth,n88), launchd variant `launchd-bt` (bluetoothd's job from the IPSW), boot line `cmdline-bt.txt`
  (herolog=bluetoothd,BlueTool). Bot level 8: /dev/cu.bluetooth and /dev/uart.bluetooth links, stand-in BlueTool .hcd
  names, patch, transport, wait 90 s.
* Result: patch 304/304 again, then `transport: com.apple.uart.bluetooth (0), com.apple.uart.sk.bluetooth (0), bridge
  thread 0`. Bridge counters after 90 s all 0: nobody connected, as expected (this boot only installed launchd.plist;
  drop package: 28 entries, 0 failed). Back in TWRP after ~200 s.
Next: boot 2 with the same image (bt-8b), where launchd starts bluetoothd.

## 2026-11-14 (night): why bluetoothd did not start (bt-8b)

* Boot 2 with bluetoothd's job in launchd.plist (checked on the phone with hfs-read.py): still no `exec bluetoothd`,
  bridge counters 0. The binary is there (/usr/sbin/bluetoothd, 8.9 MB).
* Cause: hero-run (ios-a5xelte) rewrites `/private/var/db/com.apple.xpc.launchd/disabled.plist` on every boot with
  com.apple.bluetoothd hard-coded, and **launchd does honor that list** (none of its 28 jobs ran: fairplayd, healthd,
  assistantd...). The make-launchd.sh comment saying iOS 16 ignores it holds only for the jobs heronoexec refuses.
* Fix without touching : `gracerlte/hero-run-enabled.patch` + `gracerlte/build-hero-run.sh` →
  build/mesa/hero-run-notefe. New drop file `enabled.list` (always written by write-drop.sh; `LAUNCHD=bt` adds
  com.apple.bluetoothd; `ENABLE="job ..."` for others) keeps jobs off the disabled list. Effective the boot after.
* bt-8c: hero-run logged "com.apple.bluetoothd left enabled", 27 jobs, but the disabled.plist on disk afterwards has
  34 keys, sorted, bluetoothd included: **launchd rewrites the file from its own saved state**, so editing it does not
  re-enable a job. Still no bluetoothd.
* Fix 2: `gracerlte/make-launchd-bt.sh` adds bluetoothd's IPSW job under the label **com.apple.bluetoothd.notefe** (the
  disabled list matches labels; clients use the Mach service names, unchanged). Two boots queued (install, then run).

## 2026-11-15 (night): **Bluetooth powered on in iOS** (bt-8f)

* bt-8e: bluetoothd ran (new label works), BlueTool exited at once: `MGCopyAnswer(WifiVendor)` waits for an AppleOLYHAL
  service, "Manufacturer is -1", "No WiFi", "BlueTool timed out!". bluetoothd also starts before the bot's transport.
* Bot level 8 now (a) writes a cached MobileGestalt answer **WifiVendor = Murata** into CacheExtra (key
  base64(MD5("MGCopyAnswer"+name))[:22] = c7fCSBIbX1mFaRoKT5zTIw, guacamole's mgtool method) and (b) SIGKILLs
  bluetoothd after the transport is up, so launchd's KeepAlive starts it again.
* bt-8f result: BlueTool ran D22's MUR boot script through the kernel bridge (0xfc18/2e/4e/27 answered locally, BD_ADDR
  0xfc01, name "iPhone"), then bluetoothd's own HCI init: **"BlSt PoweredOn", Chip BCM_4357, FrmN
  BCM4357B1_19.1.282.5153_Hercules_OS_MUR, "Scanning started successfully"**, state "On" sent to sharingd, rapportd,
  locationd. Bridge: 3867 bytes to the chip, 8277 to iOS, 895 answered locally, 58 fixed, 0 lost, 0 resyncs.
* Leftovers in bluetoothd's log: "BlueTool timed out running boot script!" (first try, before the restart), "Unable to
  turn on BT_WAKE signal", "Set default Phy failed STATUS 718", privilege 12000 (PRIV_SKYWALK_REGISTER_USER_PIPE, needed
  for A2DP; guacamole 0223) and 1002 (PRIV_GLOBAL_PROC_INFO) denied.
Next: count the chip's events by type (do LE advertising reports arrive?), then Settings > Bluetooth.

## 2026-11-15 (night): **the radio works: Settings > Bluetooth lists nearby devices** (bt-8g, kernel 0436)

* 0436 (advisor's suggestion: count before guessing): per-event counts, per-opcode count of the commands the chip
  refused (answered as success), every LE scan command with the chip's status.
* LE scan parameters/enable (0x200b/0x200c): chip status 0 every time (real, not faked). Events from the chip after 2
  minutes: `0e:393 0f:5 2f:3 le02:44`: **44 LE advertising reports and 3 extended inquiry results** (classic discovery).
* **The user checked the phone: Settings > Bluetooth works and shows their Android TV box.**
* Faked vendor commands so far: fce9 ×113, fce2 ×43, fd4e ×2, fd98, fd47, fdd1 (Apple-specific 0xfcxx/0xfdxx the
  Samsung firmware doesn't have). Watch whether any of them matters for pairing or audio.

## 2026-11-15 (night): camera work begins; the fail-safe watchdog (cam-1, kernel 0437)

* Research (CAMERA.md): the S9 ports (Scion-Project/hakios-starlte CAMERA.md, danstronics/ios-s9plus-exynos camera
  driver APSL + userland MIT) have the front camera in the stock Camera app by bypassing Samsung's ISP: sensor over
  I2C, the MIPI receiver's own DMA to memory, colour on the CPU, a capture device in mediaserverd. The Note FE's kernel
  config has the same CSIS DMA-out (CONFIG_USE_CSI_DMAOUT_FEATURE, CSIS v4.1). Reddit itself is blocked in the Chrome
  extension ("not allowed due to safety restrictions"); found the repos by web search instead.
* Front S5K4E6: CSIS2 0x14100000, I2C on the ISP's pins gpc2-2/3, reset gpc0-4, standby gpc1-1, MCLK gpk0-2; rails
  S2MPB02 LDO5/6/13. Rear (2L1/IMX260) behind the 73C3 companion: later.
* The fail-safe (advisor-reviewed): `notefe_wdt=1` measures, `=2` arms (INFORM3 = recovery, PMU watchdog reset
  unmasked, hardware watchdog kicked every 8 s at priority 92 until herotwrp + 90 s); a hang or halted panic stops the
  kicks and the watchdog resets into TWRP. Samsung debug level is LOW (0x4f4c in TWRP's cmdline): no upload mode.
* cam-1 (measure only): the bootloader leaves the watchdog running (WTCON 0x8021, RSTEN set) but the PMU masks its
  reset (0x408/0x40c = 0xffffffff); RST_STAT 0x20000000; INFORM2 already 0x12345678. Rate **2014 ticks/s, timeout
  32.5 s** (/256 /128). Stopped again.
* Camera level 1: all four camera domains on (status 0x3000f), the four TOP sensor clocks enabled (mux 0x202000, div
  3); camera pins all input. Level 2: **the S2MPB02 answers on HSI2C9** (gpd1-4/5 set to function 2): ID 0, BUCK2
  0x18/0x40, LDO1-17 off at their defaults (LDO5 0x30 = 1.2 V, LDO6 0x30 = 1.8 V, LDO13 0x58 = 2.8 V; Samsung sets
  2.9 V = 0x5c), LDO18 on.
* wdt-1 (armed, the bot stopped the kicks once): **the watchdog reset the phone** (next boot: RST_STAT 0x1000000 =
  bit 24, watchdog), but S-Boot booted iOS again, not TWRP: after a watchdog reset INFORM2/3 read 0. The one-shot
  marker (wdt.tested) stopped a loop; that boot reached TWRP the normal way (201 s).
* 0438: a boot with notefe_wdt that finds RST_STAT bit 24 waits 12 s (log flush) and does the proven SWRESET with
  INFORM3 = recovery. wdt-2: **watchdog reset → kernel → SWRESET → TWRP, 171 s from `adb reboot`, no buttons.**
  The fail-safe for risky boots: `gracerlte/cmdline-cam-armed.txt` (notefe_wdt=2). Not covered yet: a hang before
  herolte_gpu's init (the loader could arm it earlier) and boots without notefe_wdt.

## 2026-11-15 (night): **the front camera's sensor answers** (cam-3f, kernel 0443)

* Stage 3 runs (cam-3 .. cam-3e) found nothing on the bus; fixed one by one, the advisor finding three of them:
  * **S2MPB02 LDO registers were one off** (L1CTRL is 0x1e, LDOn = 0x1d + n; I had counted 0x1f). 0438-0439 had
    switched on LDO6, LDO7 and LDO14 (OIS_VM_2.8V, set to 2.9 V for < 1 s, then restored) instead of LDO5/6/13. Fixed in
    0440 (LDO5 0x22, LDO6 0x23, LDO13 0x2a; checked against the S9+ driver's table).
  * MCLK: SCLK_ISP_SENSOR2 divider 3 (6.5 MHz) → 0 (0440), and **the mux select read 2** (OSCCLK, the only parent, is
    0) → 0 (0443). Both put back after.
  * **Pull fields on pinctrl@136D0000 are 2 bits a pin**, not 4 (notefe_pin's): new nc_pin (0443). The board has its
    own pull-ups on the camera I2C. (The Bluetooth pin code has the same 4-bit assumption; not blocking.)
  * Also tried, not the cause: VDDIO_1.8V_CAM (LDO7, 0441), BUCK1/BB (already on: 0xd8, 0442).
* cam-3f: positive control first (the S2MPB02's own pins bit-banged: 0x59 answers), then the front, powered in
  Samsung's order: **scan finds 0x35; model ID 0x4e60 (S5K4E6), revision 2**, frame count 0xff (not streaming).
  Powered down again, LDOs as found. Bit-banged I2C on gpc2-2 (SDA) / gpc2-3 (SCL), 20 us edges.
Next: the 4E6's mode table (not in the 8890 module driver: the ISP firmware programs the sensor here; look in other
Samsung kernels), then CSIS2 + its DMA for one frame.
* cam-4 (0444, read only): CSIS2 (0x14100000) **version 0x04010000** (v4.1), CMN_CTRL 0x4000, CLK_CTRL 0xf0, DPHY_STATUS
  0xf02, CH0 config 0x80008fc / resol 0x80008000, DMA0 all 0 (ACT_CTRL 0x1c). Clocks: TOP CAM1_CSIS2_414 enable 1 div 1;
  CAM1 gates open (pclk_csis2, aclk_csis2, PHY byte clock), user muxes 0x201000. MIPI PHY control 0x145f1050 = 0; PMU
  isolation 0x714 = 0x718 = 0 (isolated). The six fimc-is SysMMUs read MMU_CTRL 0x3, CFG 0x100000, STATUS 0x1 (v6.2 /
  v6.4): possibly enabled — decide before pointing the DMA at a physical address.
* 4E6 mode tables found (GPL, read for facts): Allwinner sunxi-vin `s5k4e6yx.c` and MediaTek (Meizu m685)
  `s5k4e6mipiraw_Sensor.c`: 2608x1960 RAW10, 2 lanes, ~1008 Mb/s a lane, MCLK 24 MHz, line 2920, frame 2040; also
  1280x720 and 640x480 modes. Buffer for frames: the camera ION range 0xd0800000-0xd7ffffff (outside XNU at the stock
  RAM level, below 4 GB; 0xd8000000 is the bootloader framebuffer).

## 2026-11-15 (night): **first pixels from the front camera in memory** (cam-5, kernel 0445)

* Stage 5 (advisor-planned, each layer reported on its own): SysMMU 0x141e0000 (CSIS2's) 0x3 → 0 for the run (0x3 =
  CTRL_BLOCK_DISABLE stalls the master); PHY isolation 0x714 bit 0 + reset bit 1 of 0x145f1050; CSIS2 per Samsung's
  csi_stream_on (settle 22, 2 lanes, CH0 RAW10 2608x1960, DMA0 2D at 0xd0800000); the 4E6 mode table (121 writes from
  the MediaTek driver, all acknowledged; read back 2608 x 1960, line 2920, frame 2040, PLL 180/6).
* Result: **the sensor streams** (frame counter 0x02 → 0x10 → 0x31 in 1.5 s: ~32 fps), the link locks (DPHY_STATUS
  0xf0/0xc0, FRM_CNT_CH0 1), **the DMA wrote: the first 256 KB window fully changed, 16-bit values like 0x0043 0x0113
  0x004c 0x0040** (black level 64 = 0x40: real RAW10 pixels). DMA0 byte count 115520 → 694240 → 2167296. The windows at
  +6 MB and +9.9 MB untouched: the frame stops partway (INT_SRC0 0x21001105, INT_SRC1 0x10 to decode). Everything
  restored after (SysMMU 0x3).
* cam-5b/6/6b: PLL 166 (26 MHz MCLK, 0446) and settle sweeps (0447-0448): link errors (ECC, CRC, ID, lost FS/FE)
  regardless of settle. **Cause (advisor): CSIS2's lane byte-clock muxes (CMU_CAM1 0x22c-0x238) read 0x200000 =
  select 0 = OSCCLK**, not the PHY's RXBYTECLKHSn (select 1; Linux enables cam1_phy0..3_csis2). (cam-4's line above
  listed "user muxes 0x201000": that was bus/csis2 only; rxbyte0 was 0x200000.)
* 0449, cam-5c: **clean link, whole frames.** No errors; CSIS frame counter 47 vs the sensor's 46 in 1.5 s; DMA0 wrote
  all three windows (+0, +6 MB, up to +0x9bfefc ≈ 2608 x 1960 x 2 bytes). Pixel values ~0x40 (the black level: the
  phone was face down/dark). Settle 22, PLL 166/6, SysMMU 0x141e0000 bypassed for the run.
Next: get a picture out (downscaled frame to the drop zone, pulled with hfs-read.py), then the stream for iOS.
* 0450-0453, the picture out: a crude AE (works: exposure → 2036 lines, gain → 16x) and the frame binned to 1304x980
  8-bit Bayer, handed out by `kern.notefe_cam_pic`; the bot writes `/private/var/herolte/cam.raw8`, pulled with
  `hfs-read.py`, turned into a PNG by `gracerlte/cam-debayer.py` (standard library only). 0450 (ml_io_map pieces +
  ml_io_unmap: io_submap's KMA_PERMANENT freed from kernel_map) and 0451 (one 10 MB ml_io_map_unmappable) **hung the
  boot: the fail-safe watchdog brought it back to TWRP both times (171 s)**; a bisect boot (0452, notefe_cam_skip=2)
  put it on the picture code. 0453: one permanent 1 MB window, and DMA0's frame pointers moved back a slice at a time
  while the sensor streams, so each slice of the frame lands in the window. DMA0 byte count per frame: exactly
  10223360 = 2608 x 1960 x 2.
* cam-5g: the room is dark (raw mean 15.7 = the black level even at 16x / 33 ms): noise only. **cam-tp (0454,
  `notefe_cam_tp=2`: the sensor's colour bars): a perfect picture — white, yellow, cyan, green, magenta, red, blue,
  black** (logs/camera/cam-tp.png). Bayer order GRBG confirmed; layout, row order and binning right. The whole path
  (sensor → MIPI → CSIS2 → DMA → memory → picture) works. A real scene needs daylight: next run in the morning.
* 0455: `notefe_physmap()` (SweetFramebuffer.cpp: IOMemoryDescriptor::withPhysicalAddress, write-combined, kept; the
  S9's hakios.physmap way) maps the whole frame once: the picture is read straight from it (no more slices). Camera
  options moved off the boot line to sysctls `kern.notefe_cam_{tp,skip,pll,settle,mode}`, set by the bot from the drop
  file `cam.opts` (`CAMOPTS="tp=2 mode=1" gracerlte/write-drop.sh`). `gracerlte/cam-run.sh NAME OPTS` = one test boot.
  Modes: 0 full 2608x1960, **1 SMIA 2x2 binning 1304x980 (2555840 bytes a frame)**, 2 1280x720 crop (not run yet).
* cam-m0tp: bars again through the new mapping (2555840 words changed = one full frame). **cam-m1tp: binned 1304x980
  at ~30 fps, clean link, exactly one frame written, colour bars right** (logs/camera/cam-m1tp.png): the stream mode.

## 2026-11-15 (03:40): **/dev/hakios-camera streams the front camera** (cam-dev4, kernel 0456-0457)

* 0456: `/dev/hakios-camera`, the S9 ports' protocol (`hakios.camera.h`: a 120-byte `struct hakios_camera_frame`,
  then MIPI RAW10, GRBG, black 64), made by `kern.notefe_cam=7`. First open powers up the binned mode (1304x980,
  ~30 fps) with DMA0's 8 frame pointers over a 4-slot ring (4 x 2.5 MB from 0xd0800000); read() waits for CSIS2's
  frame counter, packs the finished slot; write() takes HAKIOS_CAMERA_EXPOSURE; kernel AE every 3rd frame otherwise;
  last close powers down. Bot level 7 reads 30 frames, keeps the last as cam.dev; `gracerlte/cam-devframe.py` converts.
* cam-dev1..3 hung (watchdog → TWRP each time); the bot's synced `cam.progress` file (survives the reset) showed open
  OK and the hang inside a read. **Advisor: the mapping covered one full frame (10223360) but the ring is 10485760:
  slot 3 read past the end.** 0457: mapping 0xa00000; the finished slot bcopy'd to kernel memory first (reading the
  uncached ring took 0.3-0.45 s while it wraps every 133 ms); torn-frame counter; slot/active/FRM_CNT in the header.
* cam-dev4: **30 frames, 11 a second through the bot, 0 overwritten while copied, all four slots used, colour bars
  right** (logs/camera/cam-dev4.png), closed and restored. The kernel half of the camera is done.
Open: which DMA pointer a finished frame is in ("the one before the active" works with the test pattern; check it
with a real scene, where a wrong slot would show as a frame from 133 ms earlier); 11 fps is the bot's packing+copy
path, iOS's reader will want NV12 or an mmap later.

## 2026-11-15 (04:15): the userland half started (cam-app1..4)

* `gracerlte/camera/`: the S9 port's capture device `camera_device.c` + `camera_isp.c` (MIT, LICENSE.HakiOS kept; Note FE
  change: its log lines also go to herodrm_log) and `inject.c` (after their inject_media.c: the camera hooks only, no
  address checks since our iOS build differs: +[BWFigCaptureDeviceVendor sharedCaptureDeviceVendor] gives a vendor
  with our device's create function when /dev/hakios-camera exists; the portrait prewarm and video stabilization off).
  `gracerlte/build-camera.sh` → `build/mesa/lib/libnotefecam.dylib` (in the drop zone's lib/); libheroapp dlopens it in
  mediaserverd only. ADT: `/arm-io/isp` with camera-rear/camera-front (mkadt_notefe.py). Bot level 8: makes the
  device, sets still/front/rear-facing-camera = YES in MobileGestalt's CacheExtra (computed answers said 0), launches
  Camera after 20 s.
* Result: in mediaserverd the three hooks are installed, **the vendor is made with our device: "two streams, the back
  camera and the front one"**; Camera.app runs (exec Camera) with MobileGestalt now saying the cameras exist. But both
  streams stop at once with 0 frames and no capture properties are asked: the session fails earlier. Next: the unified
  log (mediaserverd's CMCapture, Camera's AVFoundation) for why.
* cam-app4 unified log: mediaserverd's FigCaptureSourceServer lists capture sources **once, at its start**
  ("csu_getBackings ... Created 0 in-memory sources": /dev/hakios-camera did not exist yet). 0461: the bot restarts
  mediaserverd after making the device (for everyday use: make the device at boot).
* cam-app5: **the capture session runs**: mediaserverd lists the back and front streams, starts them, reads frames
  from the kernel ("frames of 1304x980 from the kernel (the Front Camera)", 38-40 frames in one session, "frame 2:
  exposure 16.7 ms ... green 482 above black" — the test pattern), Camera.app asks for its PrimaryScaler preview
  output; then **mediaserverd aborts (SIGABRT) when that preview stream starts**, three times. Reason in the
  unified log (being read).
* cam-app6: the abort symbolized (libheroapp's uncaught-exception line + a symbol index of the 20H392 shared cache built
  in the scratchpad from systemos.dmg): **VideoToolbox `FigGetAlignmentForIOSurfaceOutputToDisplayService` reads the
  display's `DisplayPipePlaneBaseAlignment` as a dictionary (key PlaneBaseAlignmentLinear)**; SweetFramebuffer
  published a bare number 64. QuartzCore uses the same dictionary key. 0462: published as {PlaneBaseAlignmentLinear: 64}.
* cam-app7: no more abort. Camera.app asked for the Back Camera; the kernel's frames said sensor 2 and were dropped.
  0463: HAKIOS_CAMERA_SENSOR is taken and the frames carry the number asked for (as the S9 does with one camera).
* cam-app8: frames accepted ("frames of 1304x980 from the kernel (the Back Camera)", 46 frames), but 0 pictures given:
  the preview output's VideoOutputConfigurations never arrives; Camera.app gives the stream back right after setting
  the handlers. Reading the unified log for why.
* cam-app8 unified log, the Camera app's side: AVCaptureSession **interrupted with VideoDeviceNotAvailableInBackground**
  at its first start (mediaserverd saw Camera in the foreground only ms later), then every restart failed with
  AVFoundation -11800 / OSStatus **-12780** (kCMBaseObjectError_ParamErr). 0464 (userland): FormatIndex out of range is
  clamped instead of refused — but cam-app9 shows it never was (always format 0), so -12780 comes from elsewhere.
  Still 0 pictures given: the preview's VideoOutputConfigurations is never set because the session stops first.
  Suspect: launching Camera from the bot while the screen is locked/asleep (bg:1). Next: open Camera by hand (or have
  the bot wake and unlock first), then the -12780 source (dsc-re on CMCapture's session start).

## 2026-11-15 (05:35): **the first camera picture reaches Camera.app's preview** (cam-app10..12)

* (Correction to the "background" suspect above: the restarts kept failing after bg:0; it was the graph, not the
  launch.) The S9's inject_media.c has more hooks than I first ported; added to `gracerlte/camera/inject.c`:
  -[FigVideoCaptureConnectionConfiguration videoStabilizationType] → 0 (else the graph asks for a VIS pipeline that
  needs Apple's ISP, gets nil and tears everything down), -[BWAudioSourceNode start:] swallows 'nope' (no capture
  audio), -[BWNodeOutput emitSampleBuffer:] drops NULLs (the silent audio source's), BWGNRNode render passes the
  photo through, still-image quality capped at speed.
* cam-app10/11: **"PrimaryScaler: the first picture given (1504x1128 420f)"** — the preview output got our frames
  (test pattern), then mediaserverd SIGSEGV in -[BWMultiFilterThumbnailNode prepareForCurrentConfigurationToBecomeLive]
  (+0x128, NULL+8: the filter thumbnails' Metal/CoreImage). That method is now a no-op (thumbnails stay empty).
* cam-app12: picture given again, no crash; mediaserverd is then SIGKILLed (exit 0x9, no CRASH line) after ~19 frames:
  probably jetsam (memory) or a hang watchdog. Next: memorystatus/jetsam lines in the unified log, and whether
  pictures keep flowing; then a person opening Camera from the home screen to see the preview.
* libnotefecam is now gated: libheroapp loads it in mediaserverd only with the drop flag `cam.media` = 1
  (`CAMMEDIA=1 gracerlte/write-drop.sh`; gracerlte/cam-run.sh sets it for level 8). Default 0: the everyday setup is as before.

## 2026-11-15 (day, owner's go-ahead to iterate until 14:00): camera memory, Control Center timing

* Owner test boot: `gracerlte/cmdline-daily.txt` (everyday, newest kernel, no bot/watchdog) and `gracerlte/cmdline-use.txt`
  (+ herobot=1) with the new bot **stay mode** (`STAY=1`: quick bot runs its tests, then leaves the phone in iOS).
* **Why mediaserverd dies (cam-app12):** not a watchdog: the kernel's `low swap: killing largest compressed process with
  pid 215 (mediaserverd) and size 1065 MB` (then 816, 790 MB). About 30 fps x 14 s of 1504x1128 420f = ~1 GB: the
  graph's pixel buffer pool made a new IOSurface for every frame and none came back. Fix (libnotefecam): pool
  allocation threshold `HELD + 6` (CVPixelBufferPoolCreatePixelBufferWithAuxAttributes), and a footprint line
  every 60 frames (`frame N: mediaserverd footprint X MB; given a/b/c, refused a/b/c`).
* Bot: `CCTEST=N` (Control Center opened N times: bottom-edge swipe, 4 s, Home; "cc open/close/closed" lines bracket
  the frame times), `CAMWAIT=s` (Camera app time, 15 by default).
* Wallpapers black: every collection on the D22 root has only 375w-812h@3x / 393w-852h / 430w-932h variants; our
  screen class is 375w-667h@2x, so no match. Options: iPhone 8's variants from its iOS 16 IPSW (asked the owner), or
  relabel the X ones.
* **Root cause found (cam-mem1..5):** the pool cap made no difference (footprint 21 MB at the first frame, ~850 MB
  two seconds later, only 10 IOSurfaces). A footprint thread in libnotefecam (task_info every 250 ms, VM regions by
  tag, all threads' stacks sampled with dladdr names) showed tag 3 (malloc large) growing in ~820 MB blocks, and the
  writer, symbolized against the 20H392 cache: `-[BWAudioSourceNode _generateSamples]` →
  `-_createSampleBufferForTimestampedAudioBufferList:audioBufferIndex:` → `bzero`. The silent audio source (our
  `start:` hook keeps it alive without a microphone) makes ~820 MB "silent" buffers. Fix: `_generateSamples` replaced
  with a no-op. (A malloc_logger/__syscall_logger tracer was tried first: it slowed mediaserverd until Camera.app
  could not launch, cam-mem2; removed.)
* Control Center timing (cam-mem1): while open 16-24 fps shown, framebuffer copy 7.4-10 ms a frame (14.7 MB, the
  1440x2560 panel) vs 2.9 ms idle. Background load at the same time: six widget extensions (Calendar, Weather, Stocks,
  WorldClock, Maps, ScreenTime) at ~50-60% CPU each all boot long, dasd ~200%, mobileassetd ~140%.
* **Leak fixed (cam-mem7):** `-[BWAudioSourceNode _generateSamples]` is objc_direct (not swizzlable, "not there"):
  libnotefecam patches its first instruction to `ret` in mediaserverd's copy of the cache (20H392 address 0x1a1ef39e4
  + slide, only if CMCapture and `sub sp, sp, #0x110` are there; vm_protect VM_PROT_COPY). 462 frames, footprint flat
  at 41 MB, no kill.
* **Green preview (owner saw it; cam-uv1 with colour bars):** both mediaserverd and backboardd read every 420f plane's
  bytes per row as **0**. iOS 16's IOSurfaceClient keeps a plane's entry at client +0xd0 + i*0x80 (= lock result +0x68):
  width +0x00, height +0x04, offset +0x0c, **bytesPerRow +0x10**, size +0x14, bytesPerElement +0x18, element w/h
  +0x1a/+0x1b, compression type +0x54. SweetSurface wrote bytesPerRow at +0x08. Kernel **0464** moves it. Affects every
  planar surface on the phone (video, maybe the wallpaper thumbnails too).
* Advisor (performance): the cam-mem1 Control Center numbers were taken during the leak (mediaserverd ~300%); the
  quiet window had 177/0/0/0 gaps. Plan: baseline CC boot with CAM=0, two passes (start, +150 s), 10 back-to-back
  flicks + one slow 1.5 s drag (`CCTEST=10 CCLATE=1`), every frame over 8 ms logged (hakios-gl); then branch.
* **0464 works:** colour bars through the Camera app (owner photo), then a real scene: "inverted, laggy, green" (owner).
  * Inverted: the S9 table marks its front camera turned; the 4E6 already reads out turned (0x0101 = 3): turned = false.
  * Lag (cam-t1): 6.5 fps, mediaserverd ~650%: read 50 ms, "give" 100 ms (every 1504x1128 pixel blended 4 cells and ran
    the float pipeline). New path: each crop cell through the pipeline once, then an integer bilinear scale
    (isp_render_cells / isp_render_nv12_from_cells): give 24 ms, 13.7 fps (cam-fast1; owner: "speed does seem
    better"). The kernel read (~45 ms a frame) is now the larger part.
  * Green: raw from the kernel (logs/camera/raw1 binned, raw0 full 2608x1960): R/G 0.11, B/G 0.10 above black 16
    (8-bit) in both modes; raw0 debayered with gray world looks natural. AWB clamp 4 -> 16. Clipped highlights went
    magenta (green clips, red/blue keep their 3-10x): pixel() pulls R/B toward white where G > 820 (of 959).
  * Owner: "top-left 25% of the sensor" in mode 1: 0x0901 = 0x22 without the odd increments only crops. **0466**
    writes 0x0383 = 1, 0x0387 = 3 (MediaTek slim_video; advisor: a guess, verify geometry against raw0).
* Kernel 0465: `herocap=name:pct,...` (thread every 10 s, proc_set_task_ruse_cpu THROTTLE), for coreduetd (~190%).
* cc-base1 (CAM=0, kernel 0464): late pass 33-36 fps during flicks, Control Center frames 25-45 ms for 1,500-1,900 GL
  calls (CPU-side, ~20 us a call), waiting only 2-3 ms. Background all boot: coreduetd ~190%, 4-5 widget extensions
  ~60% each (test lines lack herowidgetcap=8, default 30 lets ~60% through).
* 12:30-12:45: 0467 (cacheable ring read) camera run: 1350 frames, ~15 fps, WB ~2x. 0466 in the owner's hands: picture
  stretched (height halved only) and colours off (red car blue, yellow pillow grey): **0468 reverts 0466**.
* Wallpapers: `gracerlte/make-wallpapers.py` + `WALLPAPER=1` install 375w-667h@2x copies of the 9 collection wallpapers
  (57 files under /Library/Wallpaper/Collections, a leftover after restores). Owner: the picker's tiles are still
  black. The tiles are not drawn at all (Emoji and Color tiles too, which have no size variants): a thumbnail
  rendering problem (PosterBoard / CollectionsPoster snapshots), not missing files. Next session.
* CPU caps: herowidgetcap=8 brings each widget extension to ~16%; herocap=coreduetd:20 brings coreduetd from ~190% to
  40%. Mean total CPU did not fall (567/610/622% in cc-base1/cc-wcap1/cc-cap1), but the owner was using the phone in
  the last two; cc-cap1 also had missed=127 at 18 fps. Needs a hands-off rerun before herocap goes on the everyday line.
* Owner: the phone gets burning hot. Owner's priorities now: apps (Twitter, Telegram, Spotify), heat/performance,
  wallpapers; the camera is a nice-to-have.
* HANDOFF.md deleted at the owner's request (Claude carries the work). Next, in order: apps (`write-drop.sh app=Foo.ipa`,
  unencrypted IPAs only: cryptid 0, MinimumOSVersion <= 16.7), heat (hands-off idle run with the caps, then BT=8's
  poll, then CPU idle/clock-down), wallpaper picker tiles (snapshots not drawn), camera colour/field of view.
* 12:55 paused for a session restart (owner trying Code Mode). State: kernel 0468 built; images
  `build/boot/notefe-boot-stock-camarmed2.img` (self-returning test, caps) and `-use2.img` (everyday + bot STAY, caps,
  no TWRP timer) made from it. Phone: on the use2/STAY build from 12:34 (kernel 0467), in the owner's hands. To do:
  hands-off heat run (`BOT=1 QUICK=1 BT=2 CAM=0 CCTEST=10 CCLATE=1` + camarmed2), then stage the final STAY drop
  (`BOT=1 QUICK=1 STAY=1 BT=8 LAUNCHD=bt CAM=8 CAMMEDIA=1 CAMOPTS="mode=1" WALLPAPER=1` + use2) and leave it in TWRP.
* **heat-cap1 (13:00, hands-off, kernel 0468, herowidgetcap=8 herocap=coreduetd:20, CAM=0):** idle window (the bot's
  150 s wait) mean total CPU **261%** vs cc-base1's **518%** (no caps): coreduetd 190 -> 41%, each widget 61 -> 16%.
  Control Center late pass 33 fps, missed=0 (cc-cap1's missed=127 was the owner using the phone). Caps kept.
* **Phone left in TWRP (13:02)** with the final build staged: BOOT `notefe-boot-stock-use2.img` (cf3b9143…, kernel
  0468, `cmdline-use2.txt`: herobot=1, herowidgetcap=8, herocap=coreduetd:20, no TWRP timer, no watchdog) + drop
  `BOT=1 QUICK=1 STAY=1 BT=8 LAUNCHD=bt CAM=8 CAMMEDIA=1 CAMOPTS="mode=1" WALLPAPER=1`: on reboot Bluetooth comes up
  (~150 s), the Camera app opens once, then the phone stays in iOS.
* **Heat (13:00-13:12):** the 60 s `HEROLTE POWER: SoC` line is the thermometer (TMUs). With caps at 2288 MHz the SoC
  ran 44-50 C (heat-cap1); battery reg climbed 33.8 -> 41.3 C over the morning's back-to-back boots. Clock switching
  is proven on this unit (screen-off 728 <-> 2288 round trips in many logs). **Ceiling (heat-ceil1, `herohot=1`:
  Mongoose held at 728 MHz):** SoC 37-39 C (~6-7 C cooler, start ~3 C cooler), Control Center late pass 19-21 fps
  (vs 33): a fixed low clock costs too much. Kernel 0469/0470: `herogov=1` load governor in the power thread
  (processor_info CPU_LOAD ticks of cpus 4-7 every 200 ms; down after 2 s under 12% at 2288, up over 50% at 728;
  60 s line with time low and busy min/mean/max). Test run `gov` (cmdline-gov.txt) at 13:12.
* **heat-gov1 (13:12, herogov=1, kernel 0470; owner swiped a few times):** idle-window SoC 39-41 C (heat-cap1 44-45,
  ceiling 37-39), Control Center late pass 33-35 fps (unchanged), cluster low ~half of each minute (10-37 s), 17
  switches in ~2 min, no flapping; busy mean 9-20% at idle. Owner: "it does seem cooler".
* **Phone left in TWRP (13:20)** with BOOT `notefe-boot-stock-use3.img` (a4301d7c…, kernel 0470, `cmdline-use3.txt` =
  use2 + herogov=1) and the STAY drop (BT=8, CAM=8, WALLPAPER=1). Next: TrollStore install path, then a Telegram build
  from source (unencrypted).
* **TrollStore 2.1.1 (13:21):** downloaded (owner approved, INSTALLED.md), all three binaries plain arm64. Installed
  through the drop (`write-drop.sh app=build/trollstore/x/TrollStore.app`: hero-run moves it to /Applications on
  boot) with the use3 STAY drop. Unknown: whether trollstorehelper's root spawn/private entitlements work on this
  kernel (signing off, sweet_amfi stand-in). Owner tests on the phone; then collect the log.
* **Published (13:45):** https://github.com/egemengunel/ios-a5xelte, branch `gracerlte`, in the S7 port's layout
  (patches in xnu/patches, device folder `gracerlte/`, GRACERLTE_PROGRESS.md = this log, docs/gracerlte-*.md). Keep
  working in gracerlte/ here and copy into publish/ios-a5xelte for each update (paths rewritten gracerlte/ -> gracerlte/).
* TrollStore (troll1): hero-run put it in /Applications, `LSRegisterURL -1, registerApplication 0`, LS database
  deleted for a rebuild (the documented first-boot case). Drop rewritten without app= (no re-register each boot),
  rebooted 13:40: the rebuilt database should list it.
* **TrollStore works (13:45, owner):** after the LS rebuild boot it is on the home screen; Apps/Settings tabs, ldid
  install tapped (result not confirmed). Delta 1.6 IPA downloaded on the phone, not installed yet (getting it from
  Safari's download into TrollStore was awkward). Next: confirm "ldid: Installed", install an IPA from Files/Share or
  TrollStore's Install from URL; then an IPA built from source (Telegram) in CI, as the S7 port's ios-apps workflow.
* **Paused for the week (13:50).** Owner may flash an Android ROM meanwhile (SuperFast9, Android 9, built on
  N935FXXU4CSC5; phone bootloader N935FXXU8CVG2). That needs Format Data in TWRP, which erases the iOS install
  (root, drop zone and log all live in USERDATA) and replaces BOOT. To come back: TWRP, then `gracerlte/flash-ios.sh`
  with a current boot image (the everyday one is `build/boot/notefe-boot-stock-use3.img`; flash-ios.sh still names
  notefe-boot-<level>.img, update it first), then the STAY drop and TrollStore (`app=build/trollstore/x/TrollStore.app`).
  Everything needed is on the Mac (build/root, build/boot, backup/). EFS, RADIO, RECOVERY (TWRP) are untouched by both.
