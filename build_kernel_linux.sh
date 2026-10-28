#!/bin/bash

# Kernel for booting a GNU/Linux userspace from the recovery partition.
# See README.linux.md.

export PLATFORM_VERSION=11
export ANDROID_MAJOR_VERSION=r
export ARCH=arm64

if [ ! -f .config ]; then
	make ARCH=arm64 exynos980-a51x-linux_defconfig
fi
make ARCH=arm64 -j$(nproc)
