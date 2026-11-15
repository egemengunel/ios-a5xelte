# Roadmap: from "it boots" to a usable iOS 16 on the Note FE

Written 2026-11-10 after boot 3/4, from the session's kernel log (`logs/boot-3.txt`), static reverse engineering of the
iOS 16.7.16 binaries (`gracerlte/dsc-re.py`, `gracerlte/macho-re.py`, REA), the S7 port's own notes (`HEROLTE_PROGRESS.md`,
`NOTES.md`), the active forks of the port, and Samsung's GPL kernel source for this board.

Each item says what we **observed**, what we **infer**, and the **next step**. One variable per boot where it affects
speed or stability; logging changes can ride along.

## Where things stand (boot 3/4)

| Area | State | Evidence |
|---|---|---|
| Boot, display, touch, Wi-Fi, sound | Working | earlier boots |
| Phone app | **Opens now** (vmd removed from launchd.plist) | owner |
| launchd retry loop | **Gone**: 0 refused-job spawns (was ~640 per session) | `SPAWN FAILED` counts |
| Photos | Still black: `assetsd requires TCCPhotosService access` (36 crashes) | log |
| Music, Music widget | `strlen(NULL)`: `[MPMediaLibrary databasePath]` is nil | symbolized, below |
| Messages | Jumps to 0 inside CoreImage's OpenGL path | symbolized, below |
| Charging | Gauge saw +90 mA at boot, then 0, then discharge | `SWEET BATTERY` lines |
| CPU at idle | Mostly 12-30 % of 800 %. Bursts: CalendarWidgetExtension ~60 % for minutes, AegirPoster retried 187x | `TOP 5s` lines |
| Restart from iOS | Hangs after "CPU halted" (needs a force restart) | end of log |

Speed "about the same" fits the numbers. After the retry loop was removed, the CPU is mostly idle: the lag is in
drawing (CPU copies and GPU work per frame), not in background load.

## Update after boot 5 (2026-11-11)
* Most apps open now (CoreImage GL refusal in libheroapp). See FIRST-BOOT.md "Boot 5 results".
* One root cause now explains four failures: Music, Music widget, Podcasts and a Settings page all need
  `[MPMediaLibrary defaultMediaLibrary].databasePath`, which is nil. Photos is assetsd refused by tccd. Both look like
  "entitled process, but tccd/medialibraryd can't read its entitlements": the kernel serves DER entitlements
  (`CS_OPS_DER_ENTITLEMENTS_BLOB`, used by libxpc and tccd) only in narrow cases. Boot 6 logs exactly that (0407, 0408).
* Charging: the 0406 address was wrong (0x66, must be 0x69); fixed for boot 6.
* **Location**: the prompts work. Wi-Fi-based location needs locationd + wifid scan results + Apple's location server
  over the internet (no GPS driver). Worth a test: Settings → Privacy → Location Services on. If it stays off, locationd
  goes in a herolog boot.
* Home: homed is removed from launchd.plist (it was in the port's refused list). Re-adding it is a one-line test.

## Update 2026-11-11 (day)
Done: Control Center layout (hw.machine iPhone10,3, 0417), brightness slider (AppleARMBacklight + GPU dimming,
0419/0420), GPU job wait on the IRQ (0415), faster IOSurface checksum (gracerlte/hakios-gl), 5-minute test cycle (bot
returns to TWRP itself, 0416). Measured: frame pacing ~65 % smooth / ~16 % hitches, unchanged by CPU-side fixes or
2600 MHz. Zero-copy display through VGR0 works for one frame but the command-mode DECON then stops (NIGHT-LOG.md);
next for it: DECON_F resource routing (RESOURCE_SEL), or panel brightness over DSI so a direct path needs no copy.
Not possible: FairPlay services (Weather data, App Store), Apple ID by spoofing, cellular (Shannon).

## 1. Photos: what we found (reverse engineering)

* `assetsd` (standalone binary) at `0x100016280`: `[[PLPrivacy sharedInstance] photosAccessAllowedWithScope:7]`. If it
  is not allowed it raises the `NSInternalInconsistencyException` we see. (Disassembly and selector references:
  `__objc_selrefs` 0x10002F5A0 = `photosAccessAllowedWithScope:`, class ref `PLPrivacy` from PhotoLibraryServicesCore.)
* `-[PLPrivacy _resolvePreflightStatusForScope:]` (0x19b18898c in the shared cache) calls libTCC's
  **`tcc_authorization_preflight`** (tccd over XPC) and `TCCAccessRestricted`. A test-only override
  (`PhotoKitTestEnvironment testAccessRequest:`) exists but is gated on `os_variant_has_internal_diagnostics`, so it is unusable.
* Our `TCC.db` rows **are on the phone** after boot 3 (read back from TWRP: kTCCServicePhotos for com.apple.assetsd,
  its path, and com.apple.mobileslideshow; auth_value 2). So the database is right and **tccd itself answers "no"**.
* tccd checks the client with `csops_audittoken(CS_OPS_STATUS)`, `SecTaskCreateWithAuditToken`,
  `SecTaskCopySigningIdentifier` and `xpc_copy_entitlement_for_token`; one of its messages is "Requesting process is
  invalid or is missing an needed entitlement." Inference: tccd rejects assetsd's identity (code-signing status,
  signing identifier or platform flag as this kernel reports them), not the database.
* **Next (in boot 5):** kernel 0405 makes tccd's and assetsd's own `os_log` lines appear in our log, so we will read
  tccd's exact reason, then fix that one thing (likely in the kernel's code-signing answers, `sweet_amfi.c`).

Music likely shares this cause: Music needs `kTCCServiceMediaLibrary`, and the `databasePath` that is nil comes from the
media library's data provider, which is only set up when access is allowed. Music is in boot 5's log list too.

## 2. Plan, in order

### Phase A: see what iOS sees (boot 5, built now)
* **0405 `herolog`**: chosen programs start with `OS_ACTIVITY_DT_MODE=YES`, and their stderr (launchd sends it to
  /dev/null) is copied into the kernel log as `|name| ...`. Boot line: `herolog=tccd,assetsd,Music,MobileSlideShow`.
  It turns every "app X doesn't work" into a readable reason. Change the list per boot to chase another app.
* **libheroapp (Note FE build)**: uncaught exceptions now also log their return addresses, unslid, so
  `gracerlte/dsc-re.py fn` names the throwing function.

### Phase B: basic apps
1. **Photos / Music**: fix whatever tccd reports (Phase A). If it is the signing identity: report a proper identifier and
   `CS_PLATFORM_BINARY | CS_VALID` for root-filesystem binaries via csops.
2. **Messages / Settings icons**: CoreImage on iOS 16 has no CPU renderer. With "software" requested, or without Metal,
   `-[CIContext initWithOptions:]` falls through to `+internalGLContextWithOptions:` (disassembly at 0x1949a3100), which
   builds a GL context over an EAGLContext that doesn't exist. **Done in libheroapp:** that method now returns nil, so
   CoreImage reports "no context" instead of crashing (MobileIcons should then draw without its compositor). To verify.
3. **Extensions with "invalid sandbox or container: error 2"** (Reminders/News/Screen Time intents, PhotosFileProvider):
   containermanagerd doesn't create app-extension data containers here. Next: herolog `containermanagerd` and read why.
4. **Mail**: "daemon connection invalidated" (maild). herolog `maild` once Photos is done.
5. **AegirPoster** is refused by the kernel on purpose (upstream), but launchd retries it 187x per session. Remove its
   launch path (PosterBoard extension list) instead, to save the retries.
6. **CalendarWidgetExtension** re-evaluates its SwiftUI graph for minutes after boot (upstream's sampling showed this).
   Upstream caps "Widge" processes at 30 %. Remove the Calendar widget from the Today view as a workaround.

### Phase C: charging and USB
* **Charging (0406, boot 5)**: the MAX77854 charger has a watchdog. Android's driver turns it on (`CHG_CNFG_00`
  bit 4; TWRP showed 0x15) and clears it at every poll (`CHG_CNFG_06` WDTCLR). Under iOS nobody cleared it, so the
  charger stopped about 80 s after boot. 0406 clears it every 30 s, as Android does. It is the only register written,
  only while the hottest SoC sensor is under 50 C (we can't read the battery's own thermistor), and if the kernel stops,
  the watchdog ends charging by itself. `herochgwdt=0` makes it read-only. iOS now gets "charging/full/cable" from the
  charger, not guessed from the gauge. The log line is `NOTEFE CHG:`.
  The gauge's `fg_resistor` is 2 on this board (DTB). The mAh numbers are off by that factor; cosmetic, fix later.
* **USB (later, bigger)**: the sister project ios-sweet (Redmi Note 10 Pro) has DWC3 device mode with CDC-ECM
  networking (its patches 0072-0077: live log over USB, SSH). The Exynos 8890's USB 3.0 DRD is also a DWC3, but the PHY
  (Samsung USBDRD PHY) and clocks need Exynos code from Samsung's kernel. The payoff is large: logs and file transfer
  without TWRP round trips. Steps: read-only probe of the DWC3 ID register (only once the clock gate is known to be on),
  then PHY bring-up, then reuse ios-sweet's gadget code.

### Phase D: display quality and speed
* **iPhone 8 Plus canvas (boot 6)**: `CANVAS=8plus gracerlte/make-boot.sh gracerlte/cmdline.txt 8plus`. iOS draws 1242x2208
  @3x (scaled 1.16x to the panel instead of 1.92x: sharper, less blurry text) with a Home button. Cost: 2.7x the pixels
  per frame. Expect smoother-looking text and slower animations; compare by eye.
* **RAM**: `max` images (3678 MiB vs 3330 stock) are built; try them after the 8 Plus test (one variable per boot).
* **Zero-copy scan-out** (the S9 port's `fb_zc`): today every frame is drawn, then copied to the panel's buffer at
  `0xd8000000`. Pointing the display engine (IDMA `VG_BASE_ADDR_Y`) at the drawn surface removes a full-frame copy per
  frame, and a VG channel can scale in hardware. Upstream has the register map (HEROLTE_PROGRESS.md, "Ideas del S9").
  This is the largest speed item left.
* **Clocks**: little cores to 1586 MHz (from 1066; needs a mux switch while on a Mongoose core, voltages in
  `phone-info/cpu-tables.txt`), big cores 2600 MHz (`cmdline-2600.txt`).
* **Safari JIT** `herojit=1` test.
* **Brightness**: S6E3HA5 AOR/gamma over DSI from a backboardd hook (Samsung's `s6e3hf4_s6e3ha5_wqhd_lcd_ctrl.c`).

### Phase E: modem (honest assessment)
The Note FE's modem is a Samsung Shannon 359 (CP). Android loads its firmware from the `RADIO` partition through
Samsung's `modem_if` driver (shared memory + mailbox) and talks to it through RIL (`cbd`, `rild`, Samsung IPC). iOS
expects an Apple/Qualcomm baseband behind CommCenter with its own protocols. Calls/SMS would need: CP boot (kernel),
an IPC transport (kernel), and a CommCenter replacement or a translation of Apple's telephony XPC API. That is far
bigger than everything above combined. Update 2026-11-11: the Pixel 5 port (ios-redfin) reads SIM/signal from its
Qualcomm modem and even runs Apple's CommCenter, which works only because iPhone X's CommCenter speaks QMI like that
modem. Their iOS-side pieces (SweetCT, SweetCell, SweetPIN) don't depend on the modem and are reusable once we can read
the Shannon's status. Staged plan in COMMUNITY.md; step 1 (CP boot from XNU) is unproven anywhere.

### Phase F: Bluetooth
**Next feature (2026-11-11).** UART1 0x14c20000, BT_REG_ON gpj1-7, firmware bcm4359C0_murata.hcd. iOS's transport
(kernel control socket + Skywalk channel) is reverse engineered and patched by ios-guacamole (0220-0223, A2DP works);
the Exynos UART + Broadcom download is done by the S9+ port. Our chip is the Broadcom family iOS expects. Five steps in
COMMUNITY.md; step 1 is 0432 (read-only probe, `sysctl kern.notefe_bt=2`, run by the bot).

## 3. Community notes
* Upstream `wardevsa/ios-a5xelte` (`herolte`): no new commits since 2026-11-07 (a43e3e5, which we have).
* `rafitadev/ios-a5xelte` branch `gracelte`: a **Galaxy Note 7** port (the Note FE's twin) that independently found the
  same scan-out address `0xd8000000`. Merged upstream through 0331; nothing beyond what we have.
* `AnyInJupiter` fork: "0332: power line with gauge and clocks" (logging only).
* HackiOS (hackiosx.dev, r/hackios): POCO X5 Pro with Photos working, but no charging, cellular or Bluetooth; the S7
  is still listed at "setup screen" there (out of date). The S9+ port (danstronics) shows charger state, GLES via
  Panfrost, Metal-to-Vulkan as WIP. No public Exynos 8890 USB, modem or charging work anywhere: 0406 would be the first
  charging fix for this SoC.

## 4. Tools added
* `gracerlte/dsc-re.py`: strings, pointers, xrefs, disassembly with stub/island names, symbol search in the shared cache.
* `gracerlte/macho-re.py`: the same for one standalone binary (assetsd, tccd).
* `gracerlte/build-heroapp.sh` + `gracerlte/heroapp/heroapp.c`: Note FE libheroapp.
* REA (`morluto/rea`): signatures and entitlements (`inspect_signature`). Ghidra 12.1.4 for its decompiler: see INSTALLED.md.
