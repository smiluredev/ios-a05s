#!/bin/bash
# A05s: build the iOS 16.5 (iPhone X, 20F66) root image for userdata.
#   sudo bash build-a05s/build-iosroot.sh
# Reads research/ipsw/{OS,SystemOS,AppOS}.dmg (symlinks to rootfs/ are made if
# missing), writes research/ipsw/ios16-root.img and .simg.
set -euo pipefail
cd "$(dirname "$0")/.."
. build-a05s/lib-fsck.sh
I=research/ipsw
out=$I/ios16-root.img
img=$out
mkdir -p "$I"
# IPSW members from BuildManifest.plist (iPhone10,3 16.5 20F66):
#   OS = 096-04088-077 (UDIF/lzfse), Cryptex1,SystemOS = 096-04666-078,
#   Cryptex1,AppOS = 096-03536-083 (both raw APFS).
for pair in OS:096-04088-077 SystemOS:096-04666-078 AppOS:096-03536-083; do
	name=${pair%%:*}; hash=${pair#*:}
	[ -e "$I/$name.dmg" ] || ln -s "../../rootfs/$hash.dmg" "$I/$name.dmg"
	[ -e "$I/$name.dmg" ] || { echo "missing $I/$name.dmg (rootfs/$hash.dmg)" >&2; exit 1; }
done

bash tools/mkiosroot.sh "$I/OS.dmg" "$I/SystemOS.dmg" "$I/AppOS.dmg" "$out" 16G

mnt=$(mktemp -d)
mount -t hfsplus -o loop,force "$out" "$mnt"
trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt"' EXIT
python3 tools/sweet-root-tweaks.py "$mnt"
# The HX83112F FW is read from the root by SweetTouch (1037), not from the boot payload.
install -D -m 0644 -o 0 -g 0 research/fw-a05s/hx83112f_TXD_FW.bin "$mnt/private/var/fw/hx83112f.bin"
umount "$mnt"
trap - EXIT
rmdir "$mnt"

fsck_clean	# the tweak mount touched the volume again
# img2simg is optional (and absent here): flash the raw .img with -S 256M.
if command -v img2simg >/dev/null 2>&1; then
	img2simg "$out" "$I/ios16-root.simg"
	chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$I/ios16-root.simg"
	ls -la "$I/ios16-root.simg"
else
	echo "img2simg not installed: flash the raw .img (fastboot -S 256M)"
fi
sha256sum "$out" > "$I/ios16-root.img.sha256"
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$out" "$I/ios16-root.img.sha256"
ls -la "$out"
echo "DONE: iOS root image built"
