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

| 5 | 2026-11-18 | `a05s-touch1.img` = CI kernel with `0997` + `MODE=ios ... raintouch=1 a05stouch=1 sweetusb=3` | **Touch probe runs, but no touch.** Log: `A05S TOUCH: se0 fw=0x102 ifdis=0 hwtx=0x20102964 hwrx=0x20204800 gpi=0 cpha=0x1 demux=0x2 mclk=0x21`; `himax event-stack read e=0 00 00 00 00 00 00 00`. The A05s SE0 is in FIFO mode (`ifdis=0`), not GPI-DMA. Root cause found in the vendor source: `himax_platform.c` sets `spi->mode = SPI_MODE_3` (CPOL=1), but we had CPOL=0; the GENI CPOL is bit 2 (write 4, not 1). A FIFO TX-preload attempt (0998 draft) made the SE hang, so it was reverted. |
| 6 | 2026-11-19 | `a05s-touch2.img` = `0998` FIFO-preload draft | Boot hung in `rain_spi` after the `se0` print: GENI rejects TX written before `SE_CMD`. Preload reverted. |
| 7 | 2026-11-19 | `a05s-touch3.img` = `0998` CPOL=4 | `cpha=0x1 cpol=0x4 demux=0x2 mclk=0x21`, event stack still zero and no heartbeat: a later `rain_spi` read spun for 200 s. `0999` cuts that spin to 5000 iterations and prints the heartbeat even on error. |
| 8 | 2026-11-19 | `a05s-touch4.img` = `0999` diagnostics | **Transport proven, chip silent.** `pins=0x84 0x84 0x84 0x84` (all four SE0 pins muxed), internal FIFO loopback `e=0 11 22 33 44 55 66 77 88`, `se0 ... cpol=0x4`, but the event stack and every poll read `00`: MISO is not driven. Vendor `himax_common.h` defines **`HX_ZERO_FLASH`**, so the HX83112F has no boot flash: the vendor downloads the firmware on every boot (`himax_boot_upgrade` sets `g_boot_upgrade_flag = true`). A pin reset alone leaves the ROM bootloader, which does not serve the event stack. `research/fw-a05s/hx83112f_TXD_FW.bin` is the image to download. |
| 9 | 2026-11-19 | `a05s-touch5.img` = `1031` AHB probe | Reset pin readback `rst cfg=0x280 io=0x3` (output, drive 2, high) and pins/loopback unchanged, so GPIO 86 is good. All AHB reads returned `00` on every CS, but **the probe was invalid**: `1031` encoded the AHB address big-endian while the vendor's `hx_parse_assign_cmd()` is **little-endian** (`cmd[0] = addr & 0xFF`). The event stack read is a single-byte command so it was valid; an idle event stack is zero, so it does not prove the FW is missing either. `1032` fixes the byte order and the printed FW-version value (LE). |
| 10 | 2026-11-19 | `a05s-touch6.img` = `1032` (LE AHB) | **Byte order was the bug.** CS0 returned `2a b0 cf ee` (`0xEECFB02A`) on the FW-version register; CS1/2/3 stayed zero. CS0 is the **ilitek@0** socket on this bus (the DTS also has chipone@1 and himax@2), so the answer may be the Ilitek chip or floating MISO; the Himax on **CS2** still does not answer the AHB, which matches the zero-flash bootloader. The event stack is a single-byte command and was always valid. No touch events in the log. |
| 11 | 2026-11-19 | `a05s-touch7.img` = `1033` zero-flash download + `boot-probe --blob a05sfw=...` (untested) | **First real fix attempt.** `boot-probe.sh` now adds `research/fw-a05s/hx83112f_TXD_FW.bin` to the payload (not git); the kernel finds it at `/chosen/memory-map a05sfw` and runs: AHB system reset `0x55`, sense-off, burst-on, 64 KiB FW entity to `0x20000000`, merged config to `0x10006a00`, reload-disable `0x9AA9`, `CTRL_FW=0`, GPIO 86 reset, reload `0xEC`, wait for `C072`, then read the FW version and the event stack. Payload verified locally: `a05sfw = (0x82600000, 131072)`. |
| 12 | 2026-11-19 | `1034-a05s-upm6918-charging.patch` (untested) | **Charging.** The A05s gauge is the same **SM5602** (0x71) as topaz, but on **SE2**; the 0091+0991 `SweetBattery` already probes SE1 then SE2, so the percentage should work. The charger is the **UPM6918** at **SE1 0x6B** (DT `upm6918-charger@6b`). `1034` adds `sweet_a05s_charger_enable()` to `sweet_i2c1.c`: verifies the chip, prints REG00/01/02/04/05, clears `ENHIZ`, sets `CHG_CONFIG`+`WDT_RESET`, clears `OTG`, and disables the watchdog (REG05 bits 5:4); the touch loop kicks REG01 every 30 s as insurance. Called from `a05s_touch_bringup`. If REG00 has HIZ set (input suspended) and/or the WDT was running, this is exactly why iOS stopped charging. |
| 13 | 2026-11-19 | `1035-a05s-upm6918-status.patch` (untested) | **Charging indicator.** `SweetBattery::pollTopaz` now reads the UPM6918 **REG08** at **SE1 0x6B** first: `VBUS_STAT`[7:5] (1 SDP / 2 CDP / 3 DCP / 5 unknown / 6 non-std), `CHRG_STAT`[4:3] (0 idle / 1 precharge / 2 fast / 3 done), `PG_STAT`[2], and publishes external/charging/full from it. If 0x6B is absent it falls back to the topaz bq25890 at 0x6A (and still runs `topaz_charger`), then to the rain SMB1351. `start()` also calls `sweet_a05s_charger_enable()` before the first poll. Log line now prints `(upm=%d topaz=%d)`. |
| 14 | 2026-11-19 | capture `a05s-chg1.txt` (kernel unknown; **Ctrl-C right after the FIFO loopback**) | iOS userland up; phone enumerates on the PC as `1209:0001`; `A05S TOUCH: pins=0x84 0x84 0x84 0x84`, `fifo loopback e=0 11 22 33 44 55 66 77 88`. No `se0`, `fw blob`, `A05S CHG` or `SWEET BATTERY` lines: the capture ended before the reset/FW-download sequence. Inconclusive for 1033/1034/1035; the charging icon seen on the phone may still be the old `SweetBattery` fallback. Need to wait after the loopback until `A05S TOUCH: se0 ...`, `fw blob pa=`, `A05S CHG:`, then drag the lock screen for 30-60 s. |
| 15 | 2026-11-19 | second `chg1` capture (two boots) | Same stop: `pins`/`fifo loopback`, then nothing, because the capture was Ctrl-C'd at the loopback. `strings build-a05s/a05s-chg1.img` **does** contain `A05S TOUCH: rst cfg`, `A05S TOUCH: fw blob pa=` and `A05S CHG:` — the image has 1031/1033/1034; this is not an old kernel. The code after the loopback is `touch_gpio(RST low)`, 10 ms, `touch_gpio(RST high)`, 100 ms, then `rst cfg`/`se0`/`A05S CHG`/FW download, so the user has to leave the capture running past the loopback. |
| 16 | 2026-11-19 | third `chg1` capture | Ends at `pins`/`fifo loopback` with **no further system lines** and no `rst cfg` (the 1031+ fingerprint). `chg1.img` contains `rst cfg`/`A05S CHG`, so the image is new; if the phone was left running this looks like a **full kernel hang/panic at the GPIO-86 reset** (or the later FW/charger path), not just an early Ctrl-C. `1036-a05s-touch-reset-diag.patch` adds prints around reset low/high, the charger call and the FW map/prepare to pinpoint it; keep the phone state (frozen? rebooted? screen?) for the next report. `a05s-touch7.img` (1033 only, no charger) can isolate 1034/1035. |
| 17 | 2026-11-19 | fourth `chg1` capture, `timeout 300` | Same hard stop at `pins`/`fifo loopback`: **all** system lines (`SWEET AKS`, USB) stop too, so this is a full kernel hang/panic, not a Ctrl-C. The next code is the GPIO-86 reset (`rst cfg` never printed). `a05s-touch7.img` (1033, no 1034/1035) and `a05s-touch6.img` (1031/1032, known to print `rst cfg`) are the controls; run them with a charged battery and a wall charger/powered hub, not the PC's 500 mA. If `touch7` also dies: skip the bringup reset or use `1036` diagnostics; if only `chg1` dies: the charger/battery side effects are the trigger. |
| 18 | 2026-11-19 | `touch6` control + `touch6b` | **`touch6` (1031/1032, no blob, no 1033/1034/1035) passes the loopback again** with the same phone/power, so the GPIO-86 reset is fine and the `touch7`/`chg1` hang is **not** a brownout. `touch6b` = same 1032 kernel **+ the 131 KB blob** (the 1032 code never reads it) was built to separate the blob/payload from the 1033 code: if `touch6b` hangs, it is the payload/blob memory map; if it passes, the 1033 FW code is the culprit. |
| 19 | 2026-11-19 | `touch6b` check | **`touch6b` was built with the current (new) kernel zip**, not the 1032 one: `strings build-a05s/a05s-touch6b.img` shows `A05S CHG`/`fw blob`, so it is `chg1` + blob, not a 1032+blob control, and its loopback hang repeats the `touch7`/`chg1` result. Next control: build the **new kernel with no blob** (`mv` the FW file away, `boot-probe.sh ... noblob`, restore); it should print `no a05sfw blob` and then `rst cfg`/`se0`/poll. If `noblob` passes, the blob/payload is the cause; `mkpayload.py` currently puts the blob at `kernel_end` (the first free page), a strong suspect. |
| 20 | 2026-11-19 | `touch6b2` (64 MB blob gap) | **Still hangs at the loopback.** The blob's *presence* in the boot payload, not its address, triggers the hang (`noblob` passes; 1032 never reads the blob). Fix: **1037** removes the boot blob and reads `/private/var/fw/hx83112f.bin` from the mounted iOS root with `vnode_lookup`/`VNOP_READ` into a static 128 KB buffer. `build-iosroot.sh` now installs the FW file into the root image; the boot image is built **without** the blob (`mv` the FW file away while `boot-probe.sh` runs). Requires reflashing `userdata` with the new root image. |
| 21 | 2026-11-19 | physical buttons (user report) | Holding power shows the **Siri setup**: the power key is reaching iOS as the iPhone side button (`sweet_hid_key(0)` → `kHIDUsage_Csmr_Power`), so the long-press is the expected Siri action. A05s DT: power = PMIC **KPDPWR** (`pon_1`, code 0x74), volume-down = PMIC **RESIN** (`pon_2`, code 0x72), volume-up = **TLMM GPIO5** (`gpio_keys/vol_up`, code 0x73, active low). The rain `sweet_keys.c` polls KPDPWR + RESIN + PMIC GPIO4 (rain's volume-up), so A05s **volume-up is missing**; volume-down should work. Next: `1038` to poll TLMM GPIO5 for volume-up; power menu = side+volume or disable Siri. |
| 22 | 2026-11-19 | boot with the root FW + buttons | New kernel/root boot to the Apple logo/lock screen; **physical buttons work** (user: volume buttons + power; the power long-press is the side-button Siri action). **Touch and charging drivers still do not work.** Need the log lines: `A05S TOUCH`/`fw file|prepare|table|download|entity|config|reload|fw-ver` for how far the zero-flash download got, and `A05S CHG`/`SWEET BATTERY`/`SWEET KEYS` for the UPM6918/gauge/keys. Buttons are now a `works` area for the port table. |
| 23 | 2026-11-19 | charging confirmed | User: connecting to the wall charger **or the PC** now recognizes the source and starts charging. The UPM6918 path (1034/1035 + the root/`noblob` boot) is confirmed; mark **battery/charging as works** (still worth checking the iOS percentage/gauge in Settings and the `SWEET BATTERY` line). Buttons 2/2 done. Remaining blocker: touch (HX83112F FW/events). |
| 24 | 2026-11-19 | touch log tail | User's log tail: `A05S TOUCH: poll 1100..3300 last_e=0 last_sum=0 last_n=0 errs=0 state=00 00 00 00` — the SPI/AHB reads succeed (`errs=0`) but the chip returns all zeros, so the HX83112F is not serving the event stack. The tail did **not** include the bringup (`fw file`/`fw table`/`fw download`/`fw entity`/`fw config`/`reload active`/`fw-ver`); need those lines. Vendor comparison (`vendor/qcom/opensource/touch-drivers/hx83112f`): our 1033 writes `0x31 {0}` right after the `0x31 {0x27,0x95}` sense-off — that `0x31 {0}` belongs to the cmd-reset sequence, not the sense-off — and skips the vendor's `ADDR_CS_CENTRAL_STATE (0x900000a8)` = 0x0C check plus the TCON/ADC reset (`0x80020020`/`0x80020094`). Candidate `1038` if `fw-ver` is zero. The system otherwise stable (`SWEET INTF1` ~500 fps); `CollectionsPoster`/`assetsd` crashes are the no-SEP/noexec path, not touch. |
| 25 | 2026-11-19 | touch FW root cause | Bringup log: `fw file 131072 bytes`, `fw prepare`, `fw table pnum=10 fw=0x20000000+65536 cfg=0x10006a00+5200`, then **`fw entity e=-1` and `fw config e=-1`** — the SRAM write failed on the first chunk. Cause: `rain_spi()` rejects `n > 64`, but `himax_write_sram()` capped the **payload** at 60 and `himax_write_raw()` prepends a 6-byte header → 66. `fw config e=-1` is just the carried entity error (the config write never ran). **1038** caps the payload at 56 (total 62). Expected next: `fw entity e=0`, `fw config e=0`, `reload active ok=1`, `fw-ver` nonzero. If it still reloads with `fw-ver 0`, the next candidate is the vendor `hx83112f_sense_off` safe-mode check (`ADDR_CS_CENTRAL_STATE 0x900000a8` = 0x0C + TCON/ADC reset) and removing the extra `0x31 {0}` after the sense-off. |
| 26 | 2026-11-19 | CI workaround + 1038 build | The GitHub-hosted `macos-15` pool kept failing with `not acquired by Runner of type hosted` (even rerun); switching `runs-on` to **`macos-15-intel`** (`a730c01`) gave a runner immediately. Run **`44587828642`** succeeded in 9m19s with the 1038 (ccache restored from the rain cache). Next: build the `noblob` boot from that run, flash boot only (userdata root already has the FW) and check `fw entity e=0`/`fw config e=0`/`reload active ok=1`/`fw-ver`. |
| 27 | 2026-11-19 | 1038 works; reload fails | Boot log with 1038: `fw entity e=0`, `fw config e=0` — the SRAM writes are fixed. Then **`reload active ok=0 tries=30`** (no `fw reload2`/`fw-ver` line captured). The chip takes the writes but does not activate. Vendor `hx83112f_sense_off` does more than our 1033: `CTRL_FW=0xA5` (FW stop), `CS_CENTRAL_STATE (0x900000a8) == 0x0C`, TCON/ADC reset; the 1033's extra `0x31 {0}` after the sense-off is the cmd-reset second step and likely exits safe mode. **1039** adds the vendor sequence + prints `safe-mode state` and the `RELOAD_ACTIVE` bytes. Buttons confirmed in this log (`SWEET KEYS key=1`, HID 0xE9). |
| 28 | 2026-11-19 | 1039 skipped by git apply | The CI `build.sh` applies patches with `git apply --check` and **silently skips** ones that fail. The first 1039 had a pre-1032 context (`hx_put_be32`) so it was skipped; the kernel still only had 1038 (`strings` had no `safe-mode state`). Fixed the 1039 hunk 1 to the final context (`hx_put_le32` + the 1032 comment) and verified `git apply --check` (4 hunks). Rebuild pending. |
| 29 | 2026-11-19 | 1039 in, safe mode reads zero | The 1039 was applied (strings present). Boot: `safe-mode state=00 00` on all 5 tries, `reload active ok=0 ... v=00 00 00 00`, `fw reload2 tries=30 fw-ver 00 00 00 00`. So either the 0x31 never puts the chip in safe mode, or the AHB reads are all coming back zero. **1040** adds read-back diagnostics: `CTRL_FW` (0x9000005c), `FW_STATE` (0x900000f8) and the first 16 SRAM bytes at 0x20000000 (vs the FW image) right after the entity write. Note: the UDP log capture drops lines under the `SWEET AKS` flood (the `fw entity`/`fw config`/`safe-mode done` prints were missing even though the code ran). |
| 30 | 2026-11-19 | 1040 lines lost in UDP burst | 1040 in the kernel, but the log captured only `safe-mode state=00` x5 and the `poll` (1/s); the `ctrl_fw`/`fw-state`/`sram read`/`fw entity`/`reload active` prints were dropped by the UDP console during the `SWEET AKS` crash-loop flood (`CollectionsPoster`/`assetsd`). **1041** spaces the diagnostics with `touch_wait(100)` and splits the SRAM read into 8-byte lines. Still pending: whether `ctrl_fw` reads 0xA5 and the SRAM matches (AHB read/write sane) or is all zero (AHB path broken). |
| 31 | 2026-11-19 | raw-read diagnostics | Definitive finding: **all reads are zero** — `ctrl_fw` after writing 0xA5 reads 00000000, `sram+0/8` read zeros while `want` is the FW image, `fw-ver` 00000000. The writes return `e=0` (SPI TX accepted) but nothing comes back. The `fifo loopback e=0` was the QUP internal loopback, not a chip response. So the AHB/safe-mode theory is out; the chip read path (CS/demux/SPI mode or `himax_read`) is the blocker. **1042** adds `himax_read_dbg` (raw RX dump, shows whether the f3/cmd/00 echo comes back) + `himax_ahb_read_dbg` + reads CID `0x10000000`, FW_VER `0x10007004`, event stack `0x30`, and a write/read scratch at `0x900000f8`. |
| 32 | 2026-11-19 | CS sweep | 1042 log: `read 08 e=0 rx 00 00 00 00 00 00 00`, `read 30 ... 00`, `cid/ver/stack/scratch` all zero. **Not even the command echo comes back**, so the chip never drives MISO. The QUP loopback passes because it is internal. Prime suspect: chip-select — DTS says `reg = <2>` (CS2) and rain writes `RAIN_SPI_DEMUXSEL = 2`. **1043** sweeps DEMUXSEL 0..3, printing the raw RX and the CID for each, then restores 2. |
| 33 | 2026-11-19 | AVDD | 1043 log: all four CS (`cs0..cs3`) still `read 08 rx 00...`, `cid 00 00 00 00`. So CS/demux are not the problem. Found by code review: **the A05s `himax` path never enables AVDD**. `TOUCH_PIN_AVDD` is GPIO36 (EAST tile) and only the old topaz path calls `touch_gpio(TOUCH_PIN_AVDD, 0, 3, 3, true, true)`; the `himax_hw_init`/`himax_download` resets GPIO86 but leaves the TDDI unpowered. An unpowered TDDI gives exactly a dead MISO (no echo). **1044** enables GPIO36 AVDD (+10 ms) before the reset and prints `avdd on`. Note: the first two 1044 revisions were **silently skipped by CI** (`patch failed: bsd/dev/sweet_touch.c:2027`) because the local temp tree differs from the CI `dxb` tree by ~29 lines; the final patch uses a 1-line context. |
| 34 | 2026-11-19 | bit-bang | 1044 applied cleanly in CI (`Applying patch .../1044`) but the log still shows all-zero reads; the `avdd on` line was not captured (listener started after bring-up), and the display works, so the TDDI is likely already powered by the panel. **1045** adds a raw GPIO bit-bang on GPIO0..3 (`bb_xfer`/`a05s_bitbang`): it tries all 24 CLK/MOSI/MISO/CS permutations, reads the `0x30` register of each, prints the raw bytes, then restores the `qup0` mux. Any non-zero `bb rx` line identifies the real pin mapping and proves the chip is alive independent of the QUP. |
| 35 | 2026-11-19 | 1045/1046 image ready | CI run **`44626679964`** (commit `b4017f3`) applied 1043–1046 (verified in the build log). Local image `build-a05s/a05s-noblob.img` (17,715,200 B, 19:39) contains `A05S TOUCH: bb best` and `A05S TOUCH: avdd on` (`strings` check). The newest on-device log (`a05s-touch.log`, 19:26) is still the **1043** boot: CS0..CS3 all `read 08 rx 00...`, `cid 00 00 00 00` — so 1044/1045 have never run. Next: boot this image with the listener started **before** reboot and capture `avdd on` + `bb best` (non-zero bytes identify the real CLK/MOSI/MISO/CS mapping). |
| 36 | 2026-11-19 | DTB analysis | Decompiled the stock `vendor_boot/dtb` (4 concatenated DTBs) and `dtbo_inspect/overlay.1.dts`. Findings: (1) the base `spi@4a80000` (SE0) is `status="disabled"` and has **no touch children**; the touch nodes are added entirely by overlays. (2) `overlay.1` `fragment@68` targets `qupv3_se0_spi` and lists `ilitek@0`, `chipone_tddi@1`, `himax_ts@2` with only `panel` maps; `fragment@13` (overlay.0/1) enables SE0 SPI and defines `ilitek@0` (reset GPIO 86 active-low, IRQ 80, 10 MHz). All touch variants share GPIO86/80. (3) The A05s panels are named `hx83112f_txd`/`hx83112f_boe` — **HX83112F is a TDDI** (display+touch on one die), so the touch core may depend on the DSI panel power/init, not just GPIO86. (4) `qupv3_se0_spi` pins are `gpio0..3`, function `qup0`, drive 6 mA, **bias-disable** — matches our `pins=0x84`. (5) **GPIO36 is the haptic enable** (`RAIN HAPTIC ... gpio36 ctl 0x200`), so 1044's "AVDD" pulse actually pokes the haptic, not the TDDI; the real TDDI AVDD/VDDIO are PMIC LDOs left on by the bootloader. |
| 37 | 2026-11-19 | touch identity test (1047) | 1045/1046 image confirmed booting (`starting in 120 s`) but the listener missed the one-shot bring-up again; the poll loop runs forever, so nothing was captured. Decision: stop guessing the protocol and identify the part. **1047** runs at bring-up: (a) prints the IRQ GPIO80 level, (b) probes I2C SE2 `0x20` (synaptics) and `0x62` (novatek) through `sweet_i2c_bus_read(2,...)`, (c) sweeps SPI `cs 0/2` x `cpha 0/1` x `cpol 0/4` with four 8-byte patterns (`0xf3 0x30` Himax, `0x83` Ilitek read, `0x82 …` Ilitek write, all-FF) and dumps the raw RX, then restores CS2/mode3; and (d) appends `irq=` to the poll line so a finger on the glass can be observed. Any non-zero RX identifies the protocol, a non-zero I2C probe identifies an I2C touch. |
| 38 | 2026-11-19 | 1047 in CI | The CI `dxb` tree is **not** reproducible from this host, and 1047 was silently skipped four times before applying: hunk 1 could not anchor on `static void a05s_touch_run(void);` (the CI order is externs → bitbang → comment → bringup), hunk 2 could not anchor after the `se0 fw` print, and the poll hunk failed on the loop preamble. Final 1047 uses **context-free hunks**: it inserts `a05s_ident()` before the unique `if (rain_panel_off) { touch_report(...); continue; }` block, and the function before the unique `/* Vendor HX_RST_PIN_FUNC... */` comment. CI run **`44641722994`** applied the patch. Local image `build-a05s/a05s-noblob.img` (17,715,200 B, 21:06) has `A05S ID:` strings and `sweettouchdelay=120`. The ident runs at `tick==1` and prints `A05S ID: tick=%u irq=%u` every 10 ticks, so the one-shot bring-up can no longer be missed. |
| 39 | 2026-11-20 | 1047 boot: log dies at the ident | 1047 image (21:06) boots (`backboardd`, `SpringBoard`, `SWEET FB` up) but the UDP log **stops at 21:09:36**, exactly when the 120 s bring-up and `tick==1` ident run; no `A05S ID` line, no panic text. Either the ident hung the machine or the phone rebooted with no log. Prime suspect: the I2C probes (SE2/PMIC from the touch thread). **1048** removes the I2C probes (and the now-unused extern/`b`/`e`), keeps the IRQ print and the SPI sweep, and prints `A05S ID: spi sweep start` before it, so the next hang is localised. CI run **`44644168232`** applied it; image `build-a05s/a05s-noblob.img` (21:27) contains `spi sweep start`. |




























## Current state / next

- `userdata` now holds the iOS 16.5 HFS+ root and the first boot completed.
  The root is 16 GiB inside a 116.6 GB partition; it needs `hfs-grow` (GPU
  userland) later to use the rest.
- **Touch (Himax hx83112f), current blocker.** `0997` adds the A05s branch
  to the rain `sweet_touch.c`: `raintouch=1 a05stouch=1`, SE0 CS2/CPHA=1/
  CPOL=4/9.6 MHz, reset GPIO 86, event stack `0x30`, 56-byte HX83112F report.
  `0998` sets mode 3 and adds the heartbeat; `0999` adds the short FIFO
  timeout, pin readback, internal loopback and the always-on heartbeat.
  Test #4 proved the SoC side: pins muxed, loopback byte-exact, SE alive. The
  chip itself stays silent (MISO all zero), and the vendor source explains it:
  `HX_ZERO_FLASH` (**defined** in `research/himax/himax_common.h:85`) makes
  the HX83112F a **firmware-download-every-boot** part. `himax_boot_upgrade()`
  sets `g_boot_upgrade_flag = true` unconditionally and calls
  `_firmware_update_0f()`, which parses the partition table at
  `CFG_TABLE_FLASH_ADDR`, writes the FW entity and merged config to SRAM over
  the AHB bridge, CRC-checks them and reloads the FW. Only then does it
  `_power_on_init()` / read the FW version. A pin reset alone leaves the ROM
  bootloader, which does not serve `ADDR_EVENT_STACK 0x30`; hence the zeros.
- **Next touch step.** `1031-a05s-himax-ahb-probe.patch` (untested) adds the
  vendor AHB primitive (`[F2, 00, addr(4B BE), data]`, direction `0x0C`,
  data bank `0x08`), burst setup (`0x13=0x31`, `0x0D=0x10`), a GPIO 86
  cfg/IO readback, FW-version/status/reset-event reads at `0x10007004`,
  `0x900000a8`, `0x900000e4`, `0x900000f8`, a CS0..3 scan of the FW version,
  and a `leave-safe-mode` (`0x53 -> 0x90000098`) attempt. If the AHB read
  answers on CS2 the transport/CS/reset are all good and only the download
  is missing; an all-`FF` answer means MISO floats (power/reset/CS) and an
  all-`00` answer means the chip is unpowered or held in reset.
  **touch6 result (1032):** the LE fix works (CS0 answered), but CS0 is the
  **ilitek@0** socket; the Himax on **CS2** is still silent, consistent with
  the zero-flash bootloader. `1033-a05s-himax-fw-download.patch` implements the
  download and `boot-probe.sh` passes the FW with `--blob a05sfw=...`; the
  kernel maps it from `/chosen/memory-map` (same mechanism as rain's
  `TouchFW`). This is the next boot test. If the FW version stays zero, check
  the reload/sense-on sequence (`CTRL_FW`, pin reset, `C072`) and the per-chunk
  delays; if it becomes non-zero, the remaining work is the touch report/HID
  path.
- **Zero-flash download layout (from the file, not yet ported).**
  `research/fw-a05s/hx83112f_TXD_FW.bin` (131072 B): the partition table is at
  **0x10400** (the driver's map moves `CFG_TABLE_FLASH_ADDR` there; the compiled
  default 0x10000 is zero), `pnum=10`, no overlays. Partition 0: SRAM
  **0x20000000**, size **65536**, file offset **0x400** (FW entity). Partitions
  1..9 are config blobs at `0x10006a00..0x10007b00` (sizes 16..1536) from file
  offsets `0x12400..0x14400`; merge them into a zero-filled buffer from the
  lowest SRAM address to the highest end, 16-byte aligned. Sequence: AHB write
  `0x55 -> 0x90000018` (system reset), sense-off (`[F2,31,27,95]`, wait 20 ms,
  `[F2,31,00]`, wait 10 ms), then burst-on
  (`[F2,13,31]`, `[F2,0D,11]`), write the FW entity and the merged config in
  <=60-byte AHB chunks (address = base + offset, LE), then reload
  `0xEC -> 0x90000048` and `_power_on_init()` (rawout/sorting/set-frame,
  sense-on, wait for the `C072` reload-done word). `_calc_crc_by_hw` can be
  skipped at first.
  The FW cannot go into git (vendor/device dump). Preferred transport: put it
  in the iOS root image (e.g. `/System/Library/himax/`) at build time and read
  it in the touch thread with `vnode_open`/`vn_rdwr` after the root mounts.
  Alternative: extend `tools/mkpayload.py` with a reserved FW segment and pass
  its physical address in a boot-arg.
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
- **Touch**: `0997` + `0998` + `0999` are proven on hardware; `1031` ran but
  its AHB addresses were byte-swapped; `1032` corrects that and is the next
  boot. If the FW is not running, port the zero-flash download described
  above. Do **not** commit `research/fw-a05s/hx83112f_TXD_FW.bin`; install it
  into the iOS root image at build time and read it from the mounted root.
- **GPU** (Adreno 610), **audio** (APR/Elite on ADSP), **Wi-Fi** (WCN),
  **USB live log**: all rain code should mostly port, but none has been run on
  the A05s yet.
- **Battery/charging**: gauge = SM5602 0x71 on **SE2** (topaz `SweetBattery`
  0091+0991 already probes SE1/SE2); charger = **UPM6918** 0x6B on **SE1**.
  `1034` enables charging (HIZ off, CHG on, WDT disabled) and kicks it from the
  touch loop. iOS may still display "not charging" because the topaz battery
  code reads the old bq25890 status at 0x6A; the percentage/mV/current should
  rise.
- The kernel is stored in `boot`; the stock backup is
  `/media/MiguelTheDRMR/HDMig/a05s_stock_extract/base_images/boot.img`
  (same build as the phone: the fetched `vendor_boot` matched the stock
  `A057MUBUGDZH1` image). Restore with
  `fastboot flash boot .../boot.img`.
- Uncommitted `build-rain/work/**` changes are a stray global
  `sed s/rain/a05s/` that also corrupted identifiers (`da05s`, `da05sing`).
  Revert with `git checkout -- build-rain/work` before regenerating patches.
| 40 | 2026-11-20 | Android boot breaks the deadlock | Flashed the stock `boot.img` (A057MUBUGDZH1) and booted stock Android 16 (userdebug) after formatting `userdata`. The recovery was A057F / 5.15.123, so `insmod hx83112f.ko` (A057M / 5.15.194) was impossible; Android already ships the matching module. `lsmod` shows **`hx83112f` loaded, `spi0.2` bound to driver `himax_tp`**, and touch works. The driver logs are compiled out (`CONFIG_TOUCHSCREEN_HIMAX_DEBUG` off), so there is no dmesg, but the DT is readable at `/sys/firmware/devicetree/base/soc/qcom,qupv3_0_geni_se@4ac0000/spi@4a80000/himax_ts@2`: `compatible="himax,hxcommon"`, `reg=2`, `spi-max-frequency=0x00989680` (10 MHz), **`spi-cpha` present and `spi-cpol` absent** → **SPI mode 1 (CPOL=0, CPHA=1)**, not mode 3. The vendor `himax_bus_read` is byte-for-byte what we do (`{0xF3, cmd, 0x00}` + len in one full-duplex `spi_sync`), so the transport was never the issue; the clock polarity was. |
| 41 | 2026-11-20 | 1049 SPI mode 1 | `1049-a05s-spi-mode1.patch` writes `RAIN_SPI_CPOL = 0` (CPHA stays 1) for the a05s path (rain/topaz still 0/0), anchored on the unique `SE_MCLK`/`CPHA` lines; verified with `patch -p1` on a fresh 1047+1048 tree. The 1047 sweep still restores mode 3 at `tick==1`, but bring-up runs later (`sweettouchdelay`) and reconfigures, so it cannot override this. Next boot: `A05S ID: spi sweep start` should be followed by a real Himax answer at `cpol=0`, then `fw-ver`/CID non-zero during bring-up. |
| 42 | 2026-11-20 | 1049 boot: freeze at bring-up | `a05s-bw49.img` (1049) boots, SpringBoard runs, but the log/USB stops at **exactly the `sweettouchdelay` (120 s) bring-up**, before the first `A05S TOUCH` print. Same signature as row 39. Every boot since 1044 has died there without printing `avdd on`, and the `pins=`/`fifo loopback` prints of rows 30–34 predate 1044. Conclusion: `touch_gpio(TOUCH_PIN_AVDD=36, mux 3, high)` (the haptic enable, not the TDDI rail) hangs the SoC. Also learned: the listener must be started **before** the phone boots — the shim's UDP logger gives up if 192.168.7.1 is absent when it first sends, so a listener started later sees nothing. |
| 43 | 2026-11-20 | 1050 remove GPIO36 poke | `1050-a05s-no-gpio36.patch` replaces the GPIO36 write with `A05S TOUCH: bringup start`; the TDDI rails stay as the bootloader left them. Verified `patch -p1` after 1047+1048+1049. Next boot should reach `pins=`, `fifo loopback`, `se0 fw`, the FW download and `himax event-stack read`, then the 1047 sweep at `tick==1`. Keep the listener running from before the reboot. |
| 44 | 2026-11-20 | TLMM base bug found (TWRP) | TWRP exposes only `platform/400000.pinctrl`: **pins 0–113 all live in one TLMM at 0x00400000**. Our `touch_gpio()` was writing the topaz/rain WEST/EAST tiles (`0x00500000` for GPIO 80/86, `0x00d00000` for GPIO 36), i.e. the wrong registers: the readback `pins=0x84`/`rst cfg=0x280 io=0x3` came from the same wrong block, which is why it looked right. TWRP's `debugfs/gpio` shows the real pad state with no touch driver: `gpio86 in low pull-down` (= reset held asserted → chip dead, no MISO), `gpio80 in high no pull`, `gpio36 in low` (haptic off). So the chip was never released from reset. The layout was also off: pinctrl-msm uses pull at bits 5–6, drive at bits 7–9, OE bit 9, and the output latch is IN_OUT bit 0 (we wrote bit 1). |
| 45 | 2026-11-20 | 1051 correct TLMM base | `1051-a05s-tlmm-base.patch`: for `a05s` map the single TLMM at `0x00400000` (both west and east point there), use `pull<<5 | drive<<7 | OE 0x200` and set the IN_OUT latch with bit 0. Rain/topaz keep the old tiles. Verified `patch -p1` after 1047–1050. Expected next boot: `pins=0x104`, `rst cfg=0x300 io=0x1`, and a real Himax answer (`cid`/`ver` non-zero) once reset is released. |
| 46 | 2026-11-20 | 1051 boot loop: shared panel reset | `a05s-bw51.img` boots but loops: the display runs for a couple of minutes, then the SoC resets with **no `A05S` print** reaching UDP. Cause: GPIO86 is the **shared panel+touch reset** (HX83112F is a TDDI). With 1051 the write finally lands on the real TLMM, so the reset pulse at bring-up resets the live DSI panel; the shim cannot re-init it and the watchdog reboots. Booting the touch thread's own `raining`/bit-bang does not matter: the pulse does. |
| 47 | 2026-11-20 | 1052 release reset without pulsing | `1052-a05s-no-reset-pulse.patch`: replace the low/high pulse with a single release (`GPIO86 = 1`) and drop the diagnostic bit-bang call from bring-up (the helper is `__unused`). The DSI panel keeps running; the chip, already out of reset from the bootloader, should answer. Verified `patch -p1` on the full 1043–1051 tree. |
| 48 | 2026-11-21 | 1052 still loops; the panic is `rain_touch_report()` | `a05s-bw52.img` (no pulse, no bit-bang) still reboots at ~120 s with **no `A05S` print at all** — not even `reset release`. `touch_thread` calls `rain_touch_probe()` and then `if (rn.err || !nf.wrote || stop == 1) rain_touch_report()`, and `rain_touch_report()` is an unconditional `panic()`. So any early `rn.err` (e.g. an `ml_io_map` failure) reboots silently. 1053 disables that panic for the a05s path, stops writing the pin mux (the bootloader already did it), and prints the map pointers, the pin values and the probe return code so the failure point becomes visible. |
| 49 | 2026-11-21 | 1053 boots stable but no touch prints | `a05s-bw53.img` no longer reboots (the panic is disarmed) but the log shows **no** `probe enter`, `probe map` or `probe ret`: the map print sits after the `!gcc || !west || !rn.se` check, so an `ml_io_map` returning 0 would return silently. 1054 prints each mapping result separately, prints at the end of the 120 s wait, and shrinks the khaje TLMM window to 512 KB (0x80000), which still covers GPIO86 (0x456000). |
| 50 | 2026-11-21 | persistent console log | `tools/sweet-log-pull.sh` reads the shim's 4 MiB console ring from the tail of `userdata` (immune to UDP drops). It confirms the bw54 boot received `sweettouchdelay=60`, printed `SWEET TOUCH: starting in 60 s` and then **nothing**: not `delay done`, `probe enter` or any map line. So the thread stops inside `touch_wait(60000)`, not in the TLMM code. 1055 prints the deadline, the `assert_wait_deadline` result and the wakeup for waits >= 1 s; boot with `sweettouchdelay=15` to see it quickly. |
| 51 | 2026-11-21 | bw55: wait is fine, the log is not | `aw=-1` is **not** a failure: in xnu-8796 `THREAD_WAITING` **is** -1 (`osfmk/kern/kern_types.h`), so `assert_wait_deadline()` did arm the wait at kernel time 17.1 s with the deadline at 32.1 s. The touch thread is not stuck in `touch_wait`. The real gap is the persistent log: the pulled ring header says `flush #1, total 65345`, i.e. the log thread wrote **once** and never again (error path prints and `return`s; a hang is equally possible), so everything after ~20 s of console — the whole bring-up — is invisible. UDP is not a substitute: the shim only starts streaming once `ue0` is up and drops lines under the AKS spam. Boot timeline from the UDP log's launchd timestamps: with `sweettouchdelay=60` the phone reset 80/80/88 s after launchd, with 15 it reset 42 s after: **~20 s after the delay expires**, i.e. the reset is triggered by the bring-up (1052 already removed the GPIO86 pulse), not by the wait. Next: `a05s-bw56.img` = bw55 + `ufslogsecs=1` (flush every second, boot arg from 0047) to see how far the ring really gets before it stops, then pull the ring right after a reset. |
