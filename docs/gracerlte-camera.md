# The Note FE's cameras: facts and plan (2026-11-15)

Sources: the phone's own DTB (`backup/partitions/RECOVERY.img`), LineageOS android_kernel_samsung_universal8890
lineage-18.1 (gracelte defconfig, drivers/media/platform/exynos/fimc-is2, s2mpb02 regulator; GPL, read for facts only,
scratchpad), and the S9 ports' camera work: Scion-Project/hakios-starlte `CAMERA.md` (MIT) and
danstronics/ios-s9plus-exynos `core/drivers/camera/hakios.exynos_camera.c` (APSL 2.0) + `core/userland/src/camera_*.c`
(MIT). No port has a camera on an 8890; the S9 (Exynos 9810) has the front camera in the stock Camera app.

## The plan in one paragraph (the S9's, which works)

Leave Samsung's ISP and its firmware alone. Power the sensor (PMIC LDOs, reset/standby GPIOs, MCLK), program it over
I2C with the register table from the GPL module driver, let the MIPI receiver (CSIS) write RAW10 to memory with its
own DMA (`CONFIG_USE_CSI_DMAOUT_FEATURE=y` on the Note FE too), and do the colour work on the CPU. Then expose frames
to iOS through a capture device inside mediaserverd (the S9's `camera_device.c`/`camera_isp.c`, MIT). Front first: it
is wired straight to the SoC. The rear cameras sit behind Samsung's companion chip (73C3, SPI firmware): stage 2.

## The hardware (from the phone's DTB)

| | Front | Rear (two module variants) |
| --- | --- | --- |
| Sensor | S5K4E6 (5 MP), `fimc-is_sensor_4e6@6A`, position 1, id 1 (a `4e6_c2` variant through the companion also exists) | S5K2L1 `@5A` or Sony IMX260 `@34`, position 0 |
| Path | direct: CSIS2 at 0x14100000 (`fimc_is_sensor@14100000`, csi_ch 2, PHY `phy_cam1_csi@145F1050`) | through the companion (`preprocessor`, SPI ch 1, I2C 0x7a, dma_ch 2), CSIS0 0x14000000 |
| I2C | sensor_i2c_ch 1: pins gpc2-2 SDA / gpc2-3 SCL (function 2 = the ISP's own I2C). **Bit-banged as GPIOs: the 4E6 answers at 0x35, model ID 0x4e60, rev 2** (cam-3f). Board pull-ups; PUD fields are 2 bits a pin | via companion |
| Reset / standby | gpc0-4 / gpc1-1 | gpc1-0 (reset), gpc1-2 (companion reset) |
| MCLK | gpk0-2 function 2 (`fimc_is_mclk2_fn`), CMU_TOP SCLK_ISP_SENSOR2 (mux 0xb20 select [14:12] must be 0 = OSCCLK, found 2; div 0xb24 [7:0] 0 for 26 MHz, found 3; enable 0xb2c) | gpk0-0, SENSOR0 (0xb00..) |
| Supplies | S2MPB02 (0x59 on HSI2C9 = hsi2c@13680000, pins gpd1-4/5 function 2, gate CMU_PERIC0 0x800 bit 13): LDO5 VDDD_1.2V_VT (reg **0x22**, 0.6 V + 12.5 mV/step: 0x30), LDO6 VDDIO_1.8V_VT (**0x23**, 25 mV: 0x30), LDO13 VDDA_2.9V_VT (**0x2a**, 25 mV: 0x5c); LDOn at 0x1d + n; enable = bit 7. BUCK1 1.3 V and BB 3.5 V already on (0xd8) | S2MPB02 buck2 VDDD_CORE_0.8V_COMP, LDO1-4/7-12 (CAM/COMP rails) |
| Power order (BSP) | standby low, reset low, VDDA 2.9, VDDIO 1.8, VDDD 1.2, 1 ms, reset high, 40 us, MCLK pin function 2 | |

Power domains (PMU): pd-cam0 0x105c4020 (parent of isp1), pd-cam1 0x105c40a0, pd-isp0 0x105c4140, pd-isp1
0x105c4160 (CONFIGURATION, STATUS +4). CMU_CAM0 0x144D0000, CMU_CAM0_LOCAL 0x140F0000, CMU_CAM1_LOCAL 0x141F0000.
CSIS v4.1 (`csi2/fimc-is-hw-csi-v4_0.c`): per-channel DMA0..3 inside each CSIS (CTRL, FMT, SKIP, ADDR1-8). The Linux
driver hands it `dvaddr` (SysMMU device addresses); like the S9, physical addresses only work while the SysMMU is
off (check its state). No test-pattern generator in v4_0's register list. Reserved memory: `/reserved-memory/camera`
(check against RAM.md before use). The S9's 0xD8000000 is our bootloader framebuffer: never use it.

Also on the board: OIS (Rumba S4, 0x48 on the ISP I2C ch 2), AF (0x18), the flash (S2MPB02 FLED), the front EEPROM
`front_eeprom@51` on hsi2c@136A0000, the iris camera S5K5E6 (`fimc-is-secure@10` on hsi2c@14E00000, secure world).
Left alone: iris + IR LED, OIS, AF, flash.

## State (2026-11-15, 05:00)

**Front camera: frames in memory, colour bars verified** (kernel 0432-0454; `CAM=5` with `gracerlte/cmdline-cam-armed.txt`,
`gracerlte/cmdline-cam-tp.txt` for the test pattern; picture: `python3 gracerlte/hfs-read.py get /private/var/herolte/cam.raw8
X.raw8 && python3 gracerlte/cam-debayer.py X.raw8 X.png`). Settings that work: S2MPB02 LDO13/6/5 (+LDO7), MCLK mux 0 div 0
(26 MHz), bit-banged I2C 0x35, the MediaTek 4E6 table with PLL 0x0306 = 166, CSIS2 settle 22, 2 lanes, RAW10, **the
four lane byte-clock muxes (CMU_CAM1 0x22c-0x238) to select 1**, PHY isolation 0x714 + reset bit 1, SysMMU 0x141e0000
to 0 for the run, DMA0 2D 16-bit at 0xd0800000 (10223360 bytes a frame), ~30 fps. Bayer GRBG, black level 64.

### iOS side (2026-11-15, 05:40)

`/dev/hakios-camera` (kernel 0456-0457, 0463; made by `kern.notefe_cam=7`) streams 1304x980 RAW10 in the S9 ports'
protocol. `gracerlte/camera/` = their capture device (MIT) + `inject.c`, built into `build/mesa/lib/libnotefecam.dylib`
by `gracerlte/build-camera.sh` and loaded in mediaserverd by libheroapp. ADT `/arm-io/isp` added; MobileGestalt camera
keys set by the bot (level 8). Working: mediaserverd makes our device (back + front streams), reads frames from the
kernel. Not yet: Camera.app's session stops before its preview output is configured (background interruption, then
-12780); 0 pictures reach the screen. For everyday use the device must exist before mediaserverd starts (boot).
Fixed on the way: the display's `DisplayPipePlaneBaseAlignment` must be a dictionary (0462).

### iOS side (2026-11-15, 12:45): **live preview in the Camera app**

Kernel 0464-0468 + libnotefecam (gracerlte/camera). Working: the Camera app shows the front camera live, ~15 fps,
mediaserverd stable at ~41 MB (1350 frames in one run). What it took:
* mediaserverd was jetsam-killed ("low swap: killing largest compressed process") by `-[BWAudioSourceNode
  _generateSamples]` zero-filling ~820 MB "silent" audio buffers: objc_direct, so libnotefecam patches its first
  instruction to `ret` (20H392 address 0x1a1ef39e4 + slide, checked).
* Green screen: IOSurface plane bytes-per-row is at +0x10 of each plane entry in iOS 16, SweetSurface wrote +0x08 (0464).
  Affects every planar surface on the phone.
* Speed: the crop's cells go through the colour pipeline once, then an integer scale (6.5 -> 13.9 fps); 0467 reads the
  ring through a cacheable mapping (~15 fps). Still ~40 ms a frame in the kernel's packing + 3-5 cores in mediaserverd:
  next, overlap the read with processing (a reader thread) and pack in userland or on more cores.
* Front picture not turned (the 4E6 reads out turned, 0x0101 = 3).

Open:
* **Colour**: raw R/G and B/G ~0.1 above black in both modes (logs/camera/raw0, raw1): white balance up to 16x
  (clamp raised), highlights pulled to white. Owner's side-by-side (red car blue, yellow pillow grey, teal shirt blue):
  not a plain R/B swap. Next: read back 0x0206-0x0216, raws at two gains, a whole frame through level 7 with site means
  on a 4x4 grid.
* **Field of view**: mode 1 (0x0901 = 0x22 alone) is the top-left 1304x980 crop of the full picture. 0466 (0x0383 = 1,
  0x0387 = 3, MediaTek slim_video) halved only the height: stretched (owner); reverted in 0468. Next: binning registers
  as kern.notefe_cam_* options with a readback line, one CAMOPTS boot per variant, compared against raw0 on the Mac.

## Stages (`kern.notefe_cam=N`, bot `cam.level`, each logged)

1. Read only: PMU domain status, CMU sensor clocks, PERIC0 gate, pins gpc0/gpc1/gpc2/gpk0/gpd1. No CAM-block reads.
2. S2MPB02 over HSI2C9: ID and LDO5/6/13 control registers read (the PMIC is not written).
3. Front sensor power-up in the BSP's order, model ID over I2C (0x0000), power-down. First write to the PMIC.
4. CAM domain on, CSIS2 version, the SysMMU's state (only with the domain's status on).
5. One sensor frame through CSIS2's DMA into reserved memory; the bot writes it to the drop zone, pulled with
   hfs-read.py, debayered on the Mac.
6. Stream + /dev device + capture device in mediaserverd (port the S9's userland).
7. Rear: the companion chip (73C3 firmware over SPI from the phone's own /vendor), then the same path.

Before booting anything that can hang the boot: the fail-safe that always returns to TWRP (hardware watchdog armed
early + Samsung's reboot reason set to recovery), see NIGHT-LOG.md.
