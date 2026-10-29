#!/bin/bash
# Build Linux-a51x-J4n3K recovery image (kernel + Linux initramfs).
#
# usage: linux-recovery/mkrecovery.sh <base> [stock-recovery.img]
#
#   <base>                 map220v's Linux11.img (or any boot image / gzip
#                          cpio) providing the initramfs userland; only its
#                          /init is replaced with linux-recovery/init
#   [stock-recovery.img]   optional: take header fields and dtb from the
#                          phone's own recovery image instead of the
#                          defaults in a51x.json (recommended)
#
# Run from the kernel tree after building Image and dtbs. Writes
# linux-recovery/out/Linux-a51x-J4n3K.{img,tar} (for Odin, AP).

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/.." && pwd)
base=${1:?usage: $0 <Linux11.img|ramdisk> [stock-recovery.img]}
stock=${2:-}
out=$here/out
name=Linux-a51x-J4n3K
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

image=$tree/arch/arm64/boot/Image
dtb=$tree/arch/arm64/boot/dts/exynos/exynos9630.dtb
for f in "$image" "$dtb"; do
	[ -f "$f" ] || { echo "missing $f, build Image and dtbs first" >&2; exit 1; }
done

# initramfs userland
if [ "$(head -c 8 "$base")" = "ANDROID!" ]; then
	python3 -I "$here/bootimg.py" unpack "$base" "$work/base" >/dev/null
	base=$work/base/ramdisk
fi
mkdir "$work/rd"
(cd "$work/rd" && gzip -dc "$base" | cpio -idm --quiet --no-absolute-filenames)
install -m 755 "$here/init" "$work/rd/init"
mkdir -p "$work/rd/android_data"
(cd "$work/rd" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9n) \
	> "$work/ramdisk"

# header and dtb
extra=()
if [ -n "$stock" ]; then
	python3 -I "$here/bootimg.py" unpack "$stock" "$work/stock" >/dev/null
	info=$work/stock/info.json
	for part in dtb recovery_dtbo; do
		[ -f "$work/stock/$part" ] && extra+=("$part=$work/stock/$part")
	done
else
	info=$here/a51x.json
	python3 -I "$here/bootimg.py" dtimg "$work/dtb" "$dtb" >/dev/null
	extra+=("dtb=$work/dtb")
fi

mkdir -p "$out"
python3 -I "$here/bootimg.py" pack "$info" "$out/$name.img" \
	kernel="$image" ramdisk="$work/ramdisk" "${extra[@]}"
cp "$out/$name.img" "$work/recovery.img"
tar -C "$work" -H ustar -cf "$out/$name.tar" recovery.img
echo "Odin package: $out/$name.tar"
