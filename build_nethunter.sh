#!/bin/bash
# =====================================================================
# Build the NetHunter kernel for SM-A516B (Galaxy A51 5G, exynos9630)
#
# VERIFIED to produce a booting kernel on firmware A516BXXS9FXE3 with:
#   * clang-r365631c (9.0.8)  -- the exact AOSP clang Samsung shipped
#     this kernel with (the device's /proc/config.gz reports
#     CONFIG_CLANG_VERSION=9000x). Newer clang (e.g. 13) compiles but
#     the result did not boot on this device.
#   * GNU aarch64 ld for the final vmlinux link. ld.lld (both 9 and 13)
#     refuses the Samsung RKP ".rkp_ro" section ("unable to move
#     location counter backward"), so GNU ld is required here.
#   * The system GCC for host tools (its ld reads modern glibc's RELR).
#
# The USB Wi-Fi drivers are built as MODULES (=m): built-in (=y) panics
# at early boot on this device; as modules they load on demand.
# =====================================================================
set -e

# ---- Toolchains -----------------------------------------------------
# clang 9.0.8 (r365631c):
#   git clone --depth=1 https://github.com/Cyborg2017/prebuilts_clang_host_linux-x86_clang-r365631c.git ~/clang-r365631c
CLANG="${CLANG:-$HOME/clang-r365631c}"
# GNU aarch64 binutils (provides the external assembler + GNU ld):
#   Debian/Ubuntu:  sudo apt install binutils-aarch64-linux-gnu
#   or any aarch64-linux-gnu-* cross toolchain (e.g. Proton clang's).
BINUTILS_DIR="${BINUTILS_DIR:-/usr/bin}"

[ -x "$CLANG/bin/clang" ] || { echo "ERROR: clang not found in $CLANG/bin"; exit 1; }
command -v "$BINUTILS_DIR/aarch64-linux-gnu-ld" >/dev/null 2>&1 \
  || { echo "ERROR: aarch64-linux-gnu-ld not found in $BINUTILS_DIR"; exit 1; }

# Which defconfig. Default = stock-RKP NetHunter. Root (Magisk) variant:
#   DEFCONFIG=exynos980-a51x_nethunter_root_defconfig ./build_nethunter.sh
DEFCONFIG="${DEFCONFIG:-exynos980-a51x_nethunter_defconfig}"

# ---------------------------------------------------------------------
# clang is driven with --prefix=<binutils>/ and -no-integrated-as, so it
# invokes "<binutils>/as" and "<binutils>/ld". Those bare names are the
# x86 host tools, which reject aarch64 -- so point them at the aarch64
# binutils via a private symlink dir (never touch the system /usr/bin).
# ---------------------------------------------------------------------
GNUPREFIX="$(pwd)/.ak_binutils"
mkdir -p "$GNUPREFIX/bin"
for t in $(cd "$BINUTILS_DIR" && ls aarch64-linux-gnu-* 2>/dev/null); do
  ln -sf "$BINUTILS_DIR/$t" "$GNUPREFIX/bin/$t"
done
ln -sf "$BINUTILS_DIR/aarch64-linux-gnu-as" "$GNUPREFIX/bin/as"
ln -sf "$BINUTILS_DIR/aarch64-linux-gnu-ld" "$GNUPREFIX/bin/ld"

export PATH="/usr/bin:/bin:$GNUPREFIX/bin"
export ARCH=arm64
export PLATFORM_VERSION=13
export ANDROID_MAJOR_VERSION=t

MAKE_ARGS=(
  ARCH=arm64
  CC="$CLANG/bin/clang"
  HOSTCC=gcc HOSTCXX=g++
  LD="$GNUPREFIX/bin/aarch64-linux-gnu-ld"
  AR="$CLANG/bin/llvm-ar" NM="$CLANG/bin/llvm-nm"
  OBJCOPY="$CLANG/bin/llvm-objcopy" OBJDUMP="$CLANG/bin/llvm-objdump"
  STRIP="$CLANG/bin/llvm-strip"
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  KCFLAGS=-Wno-error
  HOSTCFLAGS=-fcommon
  LOCALVERSION=
)

echo ">> Building $DEFCONFIG with $("$CLANG/bin/clang" --version | head -1)"
make "${MAKE_ARGS[@]}" "$DEFCONFIG"
make "${MAKE_ARGS[@]}" -j"$(nproc)" Image dtbs modules

echo
echo "=== Build artifacts ==="
ls -lh arch/arm64/boot/Image
ls -lh arch/arm64/boot/dts/exynos/exynos9630.dtb
echo "Wi-Fi modules (.ko):"
find drivers/net/wireless drivers/misc/eeprom -name '*.ko'
