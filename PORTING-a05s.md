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

## Current state / next

- **Blocker:** `userdata` still holds Android. Next: build the iOS 16.5
  (iPhone X, 20F66) HFS+ root and flash it to `userdata` (destructive).
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

## Not started / open

- **Display**: the panel uses DSC. The topaz `0061`/`0114` path is 1080×2400
  and matches, but no DSC programming exists. The console (splash FB) works;
  the AppleCLCD/iOS scanout path is untested. `sweetfb_noshadow=1` is still used
  for the first boots.
- **Touch**: Himax `hxcommon` over SPI (CS2, CPHA=1). Reuse the rain GPI-DMA
  SPI infrastructure, replace the Novatek protocol and firmware (extract from
  the A05s vendor image).
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
