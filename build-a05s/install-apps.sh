#!/bin/bash
# rain: sideload apps into the iOS root image as system apps (/Applications), and list what is there.
#   - every *.app built by the userland workflow (userland/out-gpu, e.g. RainDodge.app)
#   - every *.ipa or *.app the owner drops into build-rain/apps/ (not in git). App Store apps must be
#     DECRYPTED (FairPlay cryptid 0); an encrypted one is refused here, it could never launch.
# The LaunchServices database in the image is removed so lsd rebuilds it at the next boot and the new
# icons appear (the first boot takes longer). Signatures are left as they are: the kernel has no AMFI.
# Run from the ios-topaz folder:  sudo bash build-rain/install-apps.sh
set -euo pipefail
cd "$(dirname "$0")/.."
img=research/ipsw/ios16-root.img
. build-rain/lib-fsck.sh
fsck_clean

work=$(mktemp -d)
mnt=$(mktemp -d)
mount -t hfsplus -o loop,force "$img" "$mnt"
trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt"; rm -rf "$work"' EXIT

# collect the bundles
shopt -s nullglob
for a in userland/out-gpu/*.app build-rain/apps/*.app; do cp -a "$a" "$work/"; done
for i in build-rain/apps/*.ipa; do
	unzip -q -o "$i" 'Payload/*' -d "$work/ipa"
	for a in "$work"/ipa/Payload/*.app; do mv "$a" "$work/"; done
	rm -rf "$work/ipa"
done

# cryptid of the main executable's LC_ENCRYPTION_INFO_64 (0x2C): 1 means still FairPlay-encrypted
cryptid() {
	python3 -I - "$1" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read(65536)
magic = struct.unpack_from('<I', d)[0]
if magic != 0xfeedfacf:
    print('?'); sys.exit()
ncmds = struct.unpack_from('<I', d, 16)[0]
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', d, off)
    if cmd == 0x2c:
        print(struct.unpack_from('<I', d, off + 16)[0]); sys.exit()
    off += size
print(0)
EOF
}

for a in "$work"/*.app; do
	name=$(basename "$a")
	exe=$(python3 -I -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleExecutable"])' "$a/Info.plist")
	c=$(cryptid "$a/$exe")
	if [ "$c" = 1 ]; then
		echo "SKIP $name: still FairPlay-encrypted (cryptid 1); it needs a decrypted IPA"
		continue
	fi
	rm -rf "$mnt/Applications/$name"
	cp -a "$a" "$mnt/Applications/$name"
	chown -R 0:0 "$mnt/Applications/$name"
	chmod -R u=rwX,go=rX "$mnt/Applications/$name"
	chmod 755 "$mnt/Applications/$name/$exe"
	echo "installed /Applications/$name ($exe, cryptid $c)"
done

# Apple's removable apps (Files, Notes, Calculator, Weather, ...): iOS 16 ships them in
# /private/var/staged_system_apps and installs them during the first-boot data migration, which the
# root tweaks skip. Copied (not moved) into /Applications, so they register as system apps.
for a in "$mnt"/private/var/staged_system_apps/*.app; do
	name=$(basename "$a")
	if [ ! -e "$mnt/Applications/$name" ]; then
		cp -a "$a" "$mnt/Applications/$name"
		echo "installed Apple's /Applications/$name (from staged_system_apps)"
	fi
done

# make lsd rebuild its database at the next boot
n=0
for db in "$mnt"/private/var/containers/Data/System/*/Library/Caches/com.apple.LaunchServices*.csstore; do
	rm -f "$db"; n=$((n + 1))
done
echo "LaunchServices: $n database file(s) removed (rebuilt at the next boot)"

echo "apps in /Applications:"
ls "$mnt/Applications" | sed 's/\.app$//' | column -c 120

umount "$mnt"
trap - EXIT
rmdir "$mnt"
rm -rf "$work"
fsck_clean
sha256sum "$img" > research/ipsw/ios16-root.img.sha256
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$img" research/ipsw/ios16-root.img.sha256
echo "DONE: apps installed in $img"
