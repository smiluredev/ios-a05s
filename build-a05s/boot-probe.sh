#!/bin/bash
# A05s: build a boot image from an XNU kernel + ADT and print the flash command.
#   MODE=console build-a05s/boot-probe.sh <kernel | xnu-kernel.zip | run-id> <tag> [extra cmdline]
#   MODE=ios     ...   (root read-write, iOS userland first boot)
#
# console: XNU text console, read-only root (milestone 1).
# ios:     rd=ufsroot0 with ufsrw=1 rootrw=1, cpus=4; use after userdata holds
#          the iOS HFS+ root from build-a05s/build-iosroot.sh.
# e.g. build-a05s/boot-probe.sh ~/Downloads/kernel.development.sweet A05S1
#      build-a05s/boot-probe.sh xnu-kernel.zip A05S1
#      build-a05s/boot-probe.sh 44419768019 A05S1        (needs gh, logged in)
#
# This does NOT flash anything: it writes build-a05s/a05s-<tag>.img and prints
# the fastboot command. Restore the stock boot with:
#   fastboot flash boot /media/MiguelTheDRMR/HDMig/a05s_stock_extract/base_images/boot.img
set -euo pipefail
cd "$(dirname "$0")/.."
P=$PWD
R=${1:?kernel file, zip or run id}
T=${2:?tag, e.g. A05S1}
EXTRA=${3:-}
REPO=smiluredev/ios-a05s
ADT=build-a05s/a05s-ios-2g.adt
OUT="xnu/out-$T"

if [ -f "$R" ]; then
	case "$R" in
	*.zip) rm -rf "$OUT"; mkdir -p "$OUT"; unzip -q -o "$R" -d "$OUT" ;;
	*) mkdir -p "$OUT"; cp -f "$R" "$OUT/kernel.development.sweet" ;;
	esac
else
	command -v gh >/dev/null || { echo "gh not installed; download the xnu-kernel artifact and pass the zip" >&2; exit 1; }
	rm -rf "$OUT"
	gh run download "$R" -R "$REPO" -n xnu-kernel -D "$OUT"
fi
K="$OUT/kernel.development.sweet"
[ -s "$K" ] || { echo "missing $K" >&2; exit 1; }
(cd "$OUT" && [ -f SHA256SUMS ] && sha256sum -c SHA256SUMS) || true

# sweettouch=0 keeps the rain Novatek/Himax path out; sweetfb_noshadow=1
# skips the flip/fade buffers (the rain AppleCLCD hang).
COMMON="debug=0xc serial=3 keepsyms=1 -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin wdt=-1 sweettouch=0 sweetchg=0 sweetfb_noshadow=1"
if [ "${MODE:-console}" = ios ]; then
	# First iOS userland boot: write the root (needed for the data volume).
	CMDLINE="$COMMON cpus=4 ufsrw=1 rootrw=1 launchd_unsecure_cache=1 $EXTRA"
else
	# Milestone 1: read-only, one core (the known-good rain first boot).
	CMDLINE="$COMMON cpus=1 $EXTRA"
fi

# The Himax is a zero-flash part: put its firmware in the boot payload, not in
# git, and let the kernel find it at /chosen/memory-map a05sfw = <pa, len>.
FW=research/fw-a05s/hx83112f_TXD_FW.bin
BLOBS=()
[ -s "$FW" ] && BLOBS=(--blob "a05sfw=$FW")
python3 tools/mkpayload.py "$K" "$ADT" "build-a05s/payload-$T.bin" --cmdline "$CMDLINE" "${BLOBS[@]}" >/dev/null
PATH="$P/build-rain/bin:$PATH" MKBOOTIMG=mkbootimg bash shim/build.sh "$P/build-a05s/payload-$T.bin" >/dev/null 2>&1
cp shim/out/shim-boot.img "build-a05s/a05s-$T.img"
ls -l "build-a05s/a05s-$T.img"
echo
echo "flash (destructive to the Android boot partition; stock backup exists):"
echo "  fastboot flash boot build-a05s/a05s-$T.img && fastboot reboot"
