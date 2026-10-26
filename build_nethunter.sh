#!/bin/bash
# Build the NetHunter kernel for SM-A516B (Galaxy A51 5G, exynos9630)
# Toolchain: Proton Clang (LLVM) with aarch64/arm GNU binutils.
set -e

# ---- EDIT THIS to point at your Proton/AOSP clang toolchain ----
TC=${TC:-/tmp/claude-0/-home-user-Galaxy-a51-5g-NetHunter/deb99b45-a003-504d-9b3c-017f2ba71222/scratchpad/toolchain-proton}

export PATH="$TC/bin:$PATH"
export ARCH=arm64
export PLATFORM_VERSION=13
export ANDROID_MAJOR_VERSION=t

MAKE_ARGS="ARCH=arm64   CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm   OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip   READELF=llvm-readelf HOSTCC=clang HOSTCXX=clang++   CLANG_TRIPLE=aarch64-linux-gnu-   CROSS_COMPILE=aarch64-linux-gnu-   CROSS_COMPILE_ARM32=arm-linux-gnueabi-"

make $MAKE_ARGS exynos980-a51x_nethunter_defconfig
make $MAKE_ARGS -j$(nproc) Image dtbs

echo "=== Build artifacts ==="
ls -lh arch/arm64/boot/Image 2>/dev/null
