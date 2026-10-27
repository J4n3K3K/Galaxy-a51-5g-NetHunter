#!/bin/bash
# =====================================================================
# Build the NetHunter kernel for SM-A516B (Galaxy A51 5G, exynos9630)
#
# Toolchain: Proton Clang (LLVM 13) for the ARM target + its bundled
# aarch64/arm GNU binutils for assembling and the final vmlinux link.
# Host tools are built with the system GCC.
#
# Verified to build arch/arm64/boot/Image with Proton Clang 13.0.0 on
# an Ubuntu 24.04 (glibc 2.39) host. Other clang versions may need
# different work-arounds.
# =====================================================================
set -e

# ---- Point TC at your Proton/AOSP clang toolchain --------------------
#   git clone --depth=1 https://github.com/kdrag0n/proton-clang.git ~/proton-clang
TC="${TC:-$HOME/proton-clang}"
[ -x "$TC/bin/clang" ] || { echo "ERROR: clang not found in $TC/bin"; exit 1; }

# Which defconfig to build. Default = stock-faithful (RKP on).
# Root variant (RKP/KDP/DEFEX off):
#   DEFCONFIG=exynos980-a51x_nethunter_root_defconfig ./build_nethunter.sh
DEFCONFIG="${DEFCONFIG:-exynos980-a51x_nethunter_defconfig}"

# ---------------------------------------------------------------------
# Why the two symlinks below:
# Clang is driven with --prefix=<toolchain>/bin/, so with -no-integrated-as
# it invokes "<toolchain>/bin/as" and (for the VDSO) "<toolchain>/bin/ld".
# In Proton those bare names are the *x86* binutils, which reject the
# aarch64 "-EL" flag / "aarch64linux" emulation. Repoint them at the
# cross tools. (Only clang's cross asm/link stage uses them; host links
# go through the system GCC/ld.)
# ---------------------------------------------------------------------
ln -sf aarch64-linux-gnu-as "$TC/bin/as"
ln -sf aarch64-linux-gnu-ld "$TC/bin/ld"

# System binutils first so host-tool (fixdep, dtc, …) links use the
# RELR-capable system ld; Proton last for the aarch64-linux-gnu-* tools.
export PATH="/usr/bin:/bin:$TC/bin"
export ARCH=arm64
export PLATFORM_VERSION=13           # One UI 5.1 / Android 13 (A516BXXS9FXE3)
export ANDROID_MAJOR_VERSION=t

MAKE_ARGS=(
  ARCH=arm64
  CC="$TC/bin/clang"
  HOSTCC=gcc HOSTCXX=g++
  # ld.lld (Proton 13) refuses the backward location-counter move the
  # Samsung RKP .rkp_ro section needs, so link vmlinux with GNU ld.
  LD="$TC/bin/aarch64-linux-gnu-ld"
  AR="$TC/bin/llvm-ar" NM="$TC/bin/llvm-nm"
  OBJCOPY="$TC/bin/llvm-objcopy" OBJDUMP="$TC/bin/llvm-objdump"
  STRIP="$TC/bin/llvm-strip"
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  # Samsung hard-codes bare -Werror; the newer clang emits warnings 4.19
  # never anticipated, so demote them. -fcommon fixes the 4.19 host dtc
  # build under modern GCC's -fno-common default.
  KCFLAGS=-Wno-error
  HOSTCFLAGS=-fcommon
  # Set (empty) so scripts/setlocalversion does not append a "+" when
  # building from a git tree. UTS_RELEASE then comes purely from
  # CONFIG_LOCALVERSION -> a stable "4.19.87-NetHunter-J4n3K" vermagic,
  # identical whether built from git or a tarball.
  LOCALVERSION=
)

echo ">> Building $DEFCONFIG"
make "${MAKE_ARGS[@]}" "$DEFCONFIG"
make "${MAKE_ARGS[@]}" -j"$(nproc)" Image dtbs

echo
echo "=== Build artifacts ==="
ls -lh arch/arm64/boot/Image
ls -lh arch/arm64/boot/dts/exynos/exynos9630.dtb
