# First boot: iOS 16.7.16 on the Galaxy Note FE

**2026-11-10, 15:47 reboot → home screen about 5–6 minutes later.** Boot image `notefe-boot-stock.img`
(3330 MiB RAM, big cores at 2288 MHz, GPU 650 MHz, iPhone 8 canvas 750×1334), kernel with patch 0400.

Boot sequence seen: Samsung "Galaxy Note Fan Edition" logo → kernel console **"XNU MMU ON"** with three stage
colours (drawn at `0xd8000000`) → Apple logo → home screen.

## What works (owner's test, first session)

| Area | Result |
|---|---|
| Display | Full panel, drawn by the GPU. "Pretty smooth", occasional hiccups when scrolling |
| Touch | Works everywhere tried |
| Buttons | Volume up/down work. Power locks and wakes (with an odd transition). Home works |
| Wi-Fi | Connected to the home network by itself; Settings also lists other networks |
| Internet | Safari loads google.com and other sites. Pages are slow to respond (no JIT, see below) |
| Sound | Lock sound and keyboard clicks play |
| Battery | Percentage shows. Not charging while iOS runs |
| Brightness | Slider moves, but the panel does not change (no brightness code in the port; see ROADMAP.md) |
| Settings | Opens; About shows "iPhone X", iOS 16.7.16 |
| Calendar, Notes | Open and work |
| Mail | Opens (needs an account) |

## What doesn't (and why, where known)

| Symptom | Likely cause | Status |
|---|---|---|
| Phone app hangs on launch | No modem; the port removes CommCenter, which the Phone app waits for | Expected |
| Messages opens then crashes | Same family (needs telephony/IDS daemons) | To confirm in the log |
| Photos: black screen | `assetsd` / `mediaserverd` crash on this port (maintainer's notes, boot-0323) | Known upstream |
| Music crashes | `MPMediaLibrary` NULL crash (same notes, seen in MusicWidgets) | Known upstream |
| Weather: "No weather data", cities don't load | No location; weather service also needs Apple-signed requests | Expected |
| YouTube in Safari: "error licensing this video" | Protected-video (FairPlay) path, no Secure Enclave | Expected |
| Control Center / Today view look wrong | Black blurs: no Metal, CoreAnimation's blur passes aren't drawn | Known upstream, paused there |
| Adding a wallpaper fails | Poster/wallpaper extensions crash (CollectionsPoster) | Known upstream |
| Settings → iPhone Storage doesn't load | Not investigated | Open |
| Clock shows about 5 AM | Time zone not set (UTC-ish); no network time yet | Cosmetic, to fix |
| App launches feel slow; Safari slow to respond | See "Performance" | In progress |

## Performance: where the time probably goes

1. **Small cores may be slow.** The port raises only the four big (Mongoose) cores, from the bootloader's 728 MHz to
   2288 MHz. Nothing sets the four Cortex-A53 cores, so they run at whatever S-Boot left. Kernel patch 0401 logs their
   clock and voltage (read only) so we can decide whether to raise them (Samsung's maximum is 1586 MHz).
2. **Big cores at 2288 of a possible 2600 MHz.** `herocpu_mhz=2600` is supported (1075 mV). The right voltage for
   *this* chip must be checked first (Samsung's per-chip table, readable in TWRP).
3. **No JIT in Safari.** The port refuses JIT memory (`herojit=0`) because WebKit's CSS JIT crashed on the S7. That is
   why pages respond slowly. `herojit=1` is a test for later.
4. **RAM** is not the limit today (maintainer: no jetsam kills at 2–3 GB), but more RAM keeps more apps alive:
   `camera` 3542 MiB and `max` 3678 MiB images are built.
5. **Heat:** the cores drop to 728 MHz at 80 °C (SoC sensors) and return below 70 °C. If hiccups come in bursts when
   the phone is warm, this is why. The log shows it.

## Diagnosis from the first boot's logs (2026-11-10, `logs/boot-first.txt`, `logs/ips/`)

Tools: `gracerlte/pull-log.sh` (kernel log), `gracerlte/hfs-read.py` (read-only file access to the iOS disk from TWRP; the
upstream `herolte-hfs-read.py` reads `sda18`, which is **VENDOR** on the Note FE), `gracerlte/symbolize.py` with a symbol
index of the 16.7.16 shared cache.

**Undervolting (fixed in kernel patch 0402).** This chip's Samsung ASV table (`phone-info/cpu-tables.txt`) asks for
1025 mV at 2288 MHz and 712.5 mV for the GPU at 650 MHz. The S7 port set 993.75 mV and 700 mV (the maintainer's chip).
The first boot ran 31 mV and 12.5 mV under spec. `healthd` aborted with "pthread_t was corrupted", which fits.

| App | Root cause found | Fix idea |
|---|---|---|
| **Phone** | Main thread blocked in `VMVoicemailManager fetchAccounts`: a synchronous XPC call to `vmd`, which `heronoexec=vmd` refuses to start (log: `SPAWN FAILED … vmd`, again and again) | hero-run puts `vmd` in launchd's disabled list, **effective from the second boot**: the call should then fail at once instead of hanging. To verify |
| **Photos** | Main thread blocked in `MCCopyCheckpointValue` (libMobileCheckpoint → `checkpointd`), from `+[PLImageFormat _syncFormats]`. `checkpointd` starts but never answers. Separately, `assetsd` (the photo library daemon) aborts with an uncaught exception, 40 times | Kernel patch 0403 logs `assetsd`'s exception text. Then fix whatever it names |
| **Music** | `strlen(NULL)` in `-[MPMediaLibrary _MediaLibrary_coreLibrary]` (MediaPlayer). `MediaLibrary.sqlitedb` exists; some path or identifier is NULL | Needs disassembly of that method (REA + Ghidra) |
| **Messages** | Crash in CoreImage `+[CIContext internalContextWithEAGLContext:]`, from MobileIcons' icon compositor: a GPU (EAGL) CoreImage context through the port's GL bridge | libheroapp already forces "CoreImage in software" for apps, but this path bypasses it. Fix in libheroapp (`gpu/eagl/src/heroapp.c`) |
| **Settings** (some pages) | Swift trap inside PodcastsUI (a settings pane bundle) | Open |
| Widgets/extensions (Notes, Weather, Stocks, Screen Time intents; PhotosFileProvider) | `NSInternalInconsistencyException: plugin has invalid sandbox or container: error 2` | Container manager for app extensions. Open |
| `mediaserverd` | Uncaught exception, 20 times (sound still works through the port's plug-in) | 0403 logs it |

Memory (JetsamEvent): about 1.1 GB free, one per-process-limit kill (`pkreporter`). RAM is not the bottleneck.

## Boot 2 (2026-11-10 16:31): stability boot

`notefe-boot-stock.img` (sha256 `9a5c98b4…da41`), kernel `b46fb4fc…1ab1` with 0400 (panel) + 0401 (A53 clock log) +
0402 (this chip's voltages) + 0403 (assetsd/mediaserverd exception texts). Same RAM (3330 MiB) and clocks (2288/650 MHz)
as boot 1, so differences come from the voltages and from launchd's disabled list (vmd) taking effect.

### Boot 2 results (owner's test + `logs/boot-2.txt`)

- Voltages applied: `Mongoose at 2288 MHz: vdd_mngs 0x3c -> 0x74` (1025 mV), `vdd_g3d -> 0x42` (712.5 mV); measured 2183 MHz.
  SoC 39–46 °C. `mediaserverd` and `healthd` crashes gone (20 and 4 in boot 1, 0 now).
- **A53 cluster: 1066 MHz at 800 mV** (`APOLLO_PLL M 123 P 3 S 0`), as S-Boot left it. Samsung's maximum 1586 MHz at 1012.5 mV.
- **Photos root cause:** `assetsd: uncaught NSInternalInconsistencyException: assetsd requires TCCPhotosService access`
  (42×, 172 crashes in all: a relaunch loop that costs CPU and probably the "slightly laggier" feel). assetsd's signature
  has `com.apple.private.tcc.allow = [kTCCServicePhotos]`, but `TCC.db` has no Photos row. Fix: kernel 0404 + `gracerlte/make-tcc.sh`.
- Apps now (owner): Calendar widget shows the date (new). Opens: Calendar, Reminders, Clock, Calculator, Files, Fitness,
  Books (content loading), FaceTime/Mail (sign-in), Health (stuck on onboarding "Continue"), Weather (titles, no data),
  Settings. Music and Messages open, then crash after a second. Black screen: Photos, Phone, Notes, News, TV, Podcasts,
  Wallet, Find My, Home. Maps grey. Stocks spinner. App Store loads without content.

- **Refused jobs keep respawning:** `bluetoothd`, `searchd`, `homed`, `aggregated`, `vmd`, `analyticsd`, `cloudd`,
  `ReportCrash` each failed to spawn ~80 times in boot 2 (~640 launches). hero-run writes launchd's `disabled.plist`
  (28 jobs), but iOS 16 launchd ignores it (`disabled.migrated` next to it). This wastes CPU and keeps Phone waiting on
  `vmd`. Fix: kernel 0404 + `gracerlte/make-launchd.sh` (launchd.plist without those 9 jobs; original kept in
  `logs/launchd/launchd.plist.phone`). Effective from the boot after the drop is written.

### Boot 3 (2026-11-10 17:07)
Drop package 1794319644 (verified) with TCC.db + launchd.plist; BOOT `notefe-boot-stock.img` sha256 `17065fd9…a27c`,
kernel `f9fbf919…ab3d` (0400–0404).

### Boot 3 plan
Kernel 0400–0404, same stock RAM/clocks; drop package now with `TCC.db` (Photos grants) and the slimmed `launchd.plist`.
Expect: Photos/assetsd fixed in boot 3; refused-job spawn loop and Phone hang gone from boot 4.

### Boot 3/4 results (owner + `logs/boot-3.txt`, the last session's log)
- **Phone opens** (vmd's job gone). **0 refused-job spawns** (was ~640). Apple News opened. Speed about the same.
- Photos still black: assetsd still `requires TCCPhotosService access` (36 crashes) although our TCC.db rows are on the
  phone (read back, `logs/tcc-after/`). Reverse engineering (ROADMAP.md §1): assetsd → `PLPrivacy` →
  `tcc_authorization_preflight` → tccd says no. tccd's reason is unknown: kernel 0405 puts its log in ours.
- Music: `[MPMediaLibrary databasePath]` nil → `strlen(NULL)`. Messages: CoreImage's GL fallback jumps to 0 (libheroapp fix).
- Battery: `+90 mA` at boot with a cable, then 0 and discharge: the charger's watchdog (kernel 0406).
- CPU mostly idle (12-30 % of 800 %); CalendarWidgetExtension ~60 % for minutes; AegirPoster refused 187x.
- Restart from iOS hangs after "CPU halted" (force restart needed).

### Boot 5 plan (built 2026-11-10 evening)
Kernel 0400–0406, `notefe-boot-stock.img` (same RAM, clocks and iPhone 8 canvas: only logging and charging change),
boot line without `heronoexec` (redundant now) and with `herolog=tccd,assetsd,Music,MobileSlideShow`. Drop package
with the Note FE libheroapp (CoreImage GL refused, exception addresses).
Test: plug the charger in iOS and leave it 5+ minutes (does the percentage rise?); open Photos, Music, Messages once each;
then TWRP → `gracerlte/pull-log.sh boot-5`.

Written 2026-11-10 23:52: drop package 1794343905 (verified, with the Note FE libheroapp
`5b8a4250…`), BOOT `notefe-boot-stock.img` `e89a3cbd…` verified, kernel `a7dfeda7…` (0400–0406); rebooted 23:52:01.

### Boot 5 results (owner + `logs/boot-5.txt`)
**Big step: most apps now open.** The libheroapp change (CoreImage's OpenGL context refused) is in every app and
extension (`GL context refused` in 30+ processes). The crash it removed was in MobileIcons' icon compositor, which nearly
every app's UI touches.
- Open and usable now: Messages, Notes (saves notes; asks for iCloud), Apple TV (plays), Wallet, Maps (no map: no
  location), Weather/Find My (ask for location), Stocks ("unavailable" instead of spinning), Books, Contacts, Translate,
  Files, Shortcuts, Watch, Freeform, Voice Memos, Calculator, App Store (opens; "cannot connect").
- Location permission prompts appear (new): TCC prompts work; Location Services itself is off/unavailable.
- Still failing: Photos (assetsd: TCC, 40 crashes), Music + Music widget + **Podcasts + a Settings page** (all four:
  `[MPMediaLibrary defaultMediaLibrary].databasePath` nil; Podcasts/Settings trap in PodcastsUI at a Swift force unwrap of
  it), Home (homed is removed from launchd.plist), Health (Continue does nothing), Measure/Magnifier (camera, AR: expected).
- **Charging not fixed: my mistake in 0406.** The charger is slave **0x69** (Samsung `drivers/mfd/max77854.c`
  I2C_ADDR_CHG 0xD2>>1), not 0x66 (the top/PMIC slave). Every read returned 0xff, so iOS showed "charging" all the time,
  and the watchdog clear went to 0x66 register 0xbd, which reads 0xff (unused); no effect seen. Fixed: 0x69, and nothing is
  written when the registers read all 0xff.
- **0405 logged nothing**: libsystem_trace honours OS_ACTIVITY_DT_MODE only if `amfi_check_dyld_policy_self` returns bit
  8 (libsystem_trace 0x19c9cc400), and our kernel's answer for tccd was "no policy". Fixed by 0407.
- Reverse engineering: tccd and libxpc read a client's entitlements with `csops(CS_OPS_DER_ENTITLEMENTS_BLOB)`
  (libxpc 0x1d1bf1dfc: op 0x10). The kernel answers that only with `CS_VALID` on the process and the DER blob kept, and the
  port's `OSEntitlements_get_transmuted` always fails. Leading theory for every "entitled but refused" case (assetsd,
  probably Music): 0408 logs exactly what tccd gets.

### Boot 6 (built 2026-11-11)
Kernel 0400-0408: 0406 fixed (charger 0x69), 0407 (log bit), 0408 (tccd's csops queries logged). Boot line
`herolog=tccd,assetsd,Music,medialibraryd`. Same RAM/canvas/clocks.

### Boot 7+ (queued, one variable each)
1. iPhone 8 Plus canvas: `notefe-boot-stock-8plus.img`. 2. `max` RAM. 3. 2600 MHz. See ROADMAP.md.

## Next steps

- [ ] Pull this boot's kernel log from TWRP: `gracerlte/pull-log.sh` (touch/Wi-Fi/GPU bring-up, crash reports, CPU lines)
- [ ] Read this chip's own voltage tables in TWRP: `gracerlte/read-cpu-tables.sh`
- [ ] Boot the 0401 kernel with `max` RAM; read `NOTEFE CPU:` lines for the A53 clock
- [ ] `herocpu_mhz=2600` image; then (if the A53s are slow) a patch to raise them
- [ ] Later: `herojit=1` test, iPhone 8 Plus canvas, time zone
