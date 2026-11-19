# iOS/XNU on the Samsung Galaxy A05s (`a05s`)

Port of [ios-rain](../PORTING-rain.md) (Redmi 10C, SM6225 `rain`) to the
**Samsung Galaxy A05s (SM-A057M, SM6225 "khaje")**. Same SoC family as
rain/topaz; the differences are listed below.

Repo: `smiluredev/ios-a05s`, branch `rain`. Kernel builds: GitHub Actions
`xnu.yml`; local boot-image build: `build-a05s/boot-probe.sh`.

## Hardware (from the A05s device tree + Android `/proc/iomem`)

| Item | A05s | rain | Status |
| --- | --- | --- | --- |
| SoC | SM6225 khaje, `msm-id 0x206`, board-id `0x10022` | same | works |
| CPU | 4× A53 (0x0–0x3) + 4× A73 (0x100–0x103) | same | works (Gold 0x100, 2400 MHz) |
| GIC | `0xf200000` / `0xf300000`, stride 0x20000 | same | works |
| PMIC/RPM | PM6125, `qcom,rpm-smd` | same | not used yet |
| Splash FB | `0x5c000000`, `0xf00000` | same | works |
| Panel | 1080×2400, `hx83112f_txd_fhd_90hz_video`, 90 Hz video **with DSC** | 720×1650 | console works; DSC path untested |
| Touch | Himax `hx83112f` TDDI, SPI0 `spi@4a80000` CS2, CPHA=1, 10 MHz, reset GPIO 86, IRQ GPIO 80 | Novatek NT36525B, same bus/GPIOs | not started |
| RAM | ~6 GB: `0x40000000+0x3cc00000`, `0x80000000+0x80000000`, `0x1_00000000+0xc0000000` | 4 GB, different banks | ADT `a05s-ios-2g.adt` (2 GiB at 0x80000000) |
| Storage | **UFS** `ufshc@4804000` (`ufs_mem` in iomem); `sdhci@4744000` is absent, `4784000` is the SD slot | UFS `0x4804000` | **works** (rain `sweet_ufs.c` unchanged) |
| Audio | WCD937x + Bolero + SoundWire, AW87390 expected | same codec | not started |
| Wi-Fi/BT | WCN (wlan / bt_wcn3990 nodes) | WCN3950 | not started |
| Battery | `sm5602@71` (I²C) | SH366101 | not started |
| USB | `dwc3@4e00000` | same | not started |

fastboot: the phone exposes **`fastbootd`** (userspace); `fastboot boot` is not
implemented. Flashing `boot` from fastbootd works; the bootloader is unlocked
(`unlocked: yes`, `slot-count: 0`, non-A/B).

## Boot log

| # | Date | Image | Result |
| --- | --- | --- | --- |
| 1 | 2026-11-18 | shim only, 1080×2400 (commit `3aa5aff`) | **Milestone 0.** Samsung ABL accepted the v4 boot image and ran the shim on Gold CPU `0x100`. `MMFR0 tg16=1`, `MIDR 411FD090`, GICD/GICR + 4 Gold ready (0x101–0x103), `CPUFREQ 2400 MHz`, `SPEED silver=0x7B9DA gold=0x1D4C34`. `DDR MiB 0x400+0x3CC, 0x1000+0xC00, 0x8000+0x8000` (~6 GB). `PANEL hx83112f_txd_fhd_90hz_video`. Console readable, correct 4320-byte stride. Last line `LOADER no SWEETXNU payload` (expected). |
| 2 | 2026-11-18 | XNU from run `44419768019` (commit `3cbfdf2`, rain patch series, no 0999) + `build-a05s/a05s-ios-2g.adt`; `cpus=1 rd=ufsroot0 sweettouch=0 sweetchg=0 sweetfb_noshadow=1`, no `ufsrw/rootrw` | **Milestone 1.** XNU runs to root mount: `BSD root: ufsroot0` (the UFS driver read the A05s LUN0 GPT and found `userdata`), then HFS+ rejects the Android filesystem, `cannot mount root, errno = 19` (expected). CPU/GIC/timer/display/UFS all validated. |

## iOS root image (2026-11-18)

`sudo bash build-a05s/build-iosroot.sh` built `research/ipsw/ios16-root.img`
(16 GiB HFS+, 12 GiB used, SHA-256 starts `a2f566ff…`; raw .img, `img2simg`
is not installed here). Root is iOS **16.5 / 20F66**; the tweak script read
that from the image's `SystemVersion.plist`.

Verification (`build-a05s/check-iosroot.sh`): 528 LaunchDaemons, 0
`_PanicOnCrash`, 7 `_PanicOnCrasX`, no CommCenter, `purplebuddy`/`springboard`
prefs present, 44 dyld-cache files, `launchd` present. `virtualaudio` disabled
(no RedwoodAudio yet). Observations, not blockers:
- no `mobileactivationd` system container in this 16.5 root, so the data-ark
  seed was skipped (`activation()` warned); the Activated state comes from
  `/chosen` security-status.
- `America/Sao_Paulo` is not in this root's zoneinfo; localtime stays US/Pacific
  until changed in Settings.

Boot image for the first userland boot:
`MODE=ios bash build-a05s/boot-probe.sh xnu-kernel.zip A05S-ios1`
(17.7 MB, v4, cmdline has `cpus=4 ufsrw=1 rootrw=1 launchd_unsecure_cache=1`).

| 3 | 2026-11-18 | `boot` = `MODE=ios` image (`cpus=4 ufsrw=1 rootrw=1 launchd_unsecure_cache=1`); `fastboot -S 256M flash userdata research/ipsw/ios16-root.img` (47/47 sparse chunks, 479.9 s; partition 116.6 GB), then `fastboot reboot` | **iOS userland starts.** The Apple logo is drawn on the 1080x2400 panel (display path works with the panel's DSC as left by ABL). First boot in progress; the lock screen is the next expected step. The fastboot "avb footer" warning is harmless (the client miscomputes the sparse image size; every write returned OKAY). |

| 4 | 2026-11-18 | same boot, left running (~11 min) | **Milestone 2: iOS 16.5 lock screen on the A05s.** The first boot completed (data volume created); the lock screen is drawn on the 1080x2400 panel through the topaz display path. Touch is off (`sweettouch=0`, no Himax driver), GPU is off (no `gpu=1`/userland), so the UI is CPU-rendered and not interactive yet. |

| 5 | 2026-11-18 | `a05s-touch1.img` = CI kernel with `0997` + `MODE=ios ... raintouch=1 a05stouch=1 sweetusb=3` | **Touch probe runs, but no touch.** Log: `A05S TOUCH: se0 fw=0x102 ifdis=0 hwtx=0x20102964 hwrx=0x20204800 gpi=0 cpha=0x1 demux=0x2 mclk=0x21`; `himax event-stack read e=0 00 00 00 00 00 00 00`. The A05s SE0 is in FIFO mode (`ifdis=0`), not GPI-DMA, and the rain `rain_spi` FIFO path wrote `SE_CMD` before the TX FIFO. `0998` preloads the FIFO and adds a 1 s poll heartbeat; pending rebuild/test. |

## Current state / next

- `userdata` now holds the iOS 16.5 HFS+ root and the first boot completed.
  The root is 16 GiB inside a 116.6 GB partition; it needs `hfs-grow` (GPU
  userland) later to use the rest.
- **Touch (Himax hx83112f), test #1.** `0997` adds the A05s branch to the
  rain `sweet_touch.c`: `raintouch=1 a05stouch=1`, SE0 CS2/CPHA=1/9.6 MHz,
  reset GPIO 86, event stack `0x30`, 56-byte HX83112F report. The kernel
  booted to the lock screen and the probe ran, but the event stack read was
  all-zero. The log showed `gpi=0 ifdis=0`: the A05s SE0 is in **FIFO mode**,
  and the rain `rain_spi` FIFO path wrote `SE_CMD` before the TX FIFO, so the
  Himax never saw the `F3 30 00` read command. `0998-a05s-himax-fifo-fix.patch`
  preloads the TX FIFO and prints a 1 s `poll n= sum=` heartbeat; rebuild and
  boot with the same args. If the heartbeat stays zero, the next checks are
  the CS2 pin/DEMUX, the GPIO 86 reset/power rail and the IC flash FW.
- GPU (Adreno 610 / Mesa freedreno userland + A05s zap firmware) is the other
  big win: the CPU renderer is slow.
- Live log: `build-a05s/a05s-A05S-dbg1.img` (`sweetusb=3 sweetfps=1`) is ready
  for the next debug boot; 16.5 root is already initialized, so it should
  reach the lock screen faster.
- The iOS root is built from `rootfs/` (IPSW members):
  `OS` = `096-04088-077` (UDIF/lzfse, opened directly by the local
  `apfs-fuse` fork), `Cryptex1,SystemOS` = `096-04666-078` (raw APFS),
  `Cryptex1,AppOS` = `096-03536-083` (raw APFS). `build-a05s/build-iosroot.sh`
  creates the symlinks and runs `tools/mkiosroot.sh` + `tools/sweet-root-tweaks.py`.
- `/product` in the ADT comes from `research/ipsw-x/d22ap.adt` (extracted from
  this IPSW's `DeviceTree.d22ap.im4p`).
- Kernel artifact used for #2 predates `0999`; rebuilding with the current
  `xnu/patches` is recommended for the record (the 0999 UFSHCI sanity check is
  harmless on the real UFS).
- Touch patch `0997` is in the same series; its first kernel build and boot
  test are the next milestone.

## Not started / open

- **Display**: the panel uses DSC. The topaz `0061`/`0114` path is 1080×2400
  and matches, but no DSC programming exists. The console (splash FB) works;
  the AppleCLCD/iOS scanout path is untested. `sweetfb_noshadow=1` is still used
  for the first boots.
- **Touch**: `0997` (probe) + `0998` (FIFO TX preload + heartbeat) are in the
  A05s series; the FIFO fix is not booted yet. If the event stack still reads
  all-zero/0xFF, the next step is the Himax flash download (vendor
  `hx83112f_TXD_FW.bin`) or checking that the IC's power rail is on.
- **GPU** (Adreno 610), **audio** (APR/Elite on ADSP), **Wi-Fi** (WCN),
  **battery** (SM5602), **USB live log**: all rain code should mostly port, but
  none has been run on the A05s yet.
- The kernel is stored in `boot`; the stock backup is
  `/media/MiguelTheDRMR/HDMig/a05s_stock_extract/base_images/boot.img`
  (same build as the phone: the fetched `vendor_boot` matched the stock
  `A057MUBUGDZH1` image). Restore with
  `fastboot flash boot .../boot.img`.
- Uncommitted `build-rain/work/**` changes are a stray global
  `sed s/rain/a05s/` that also corrupted identifiers (`da05s`, `da05sing`).
  Revert with `git checkout -- build-rain/work` before regenerating patches.
