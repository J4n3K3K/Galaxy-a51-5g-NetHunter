# Linux kernel for Samsung Galaxy A51 5G (SM-A516B/F, Exynos 980)

Port of [map220v's Galaxy A51 Linux kernel](https://github.com/map220v/kernel_samsung_a51-linux)
to the Galaxy A51 5G (Exynos 980) kernel. It is meant to be flashed to the
recovery partition and boot a regular GNU/Linux userspace, while Android stays
on the boot partition.

**Only for the Exynos variant.** Snapdragon models (SM-A516U/N/0) need a
different kernel.

## Build

```sh
./build_kernel_linux.sh
```

This uses `arch/arm64/configs/exynos980-a51x-linux_defconfig`. Compared to
`exynos980-a51x_defconfig` it:

- enables VT, fbcon, fonts and the boot logo,
- adds `console=tty0 rw` to the built-in command line,
- enables features systemd/distros need (SysV IPC, POSIX mqueue, user/IPC
  namespaces, fhandle, autofs, pids/devices cgroups, checkpoint/restore),
- enables USB gadget serial/ECM/EEM/mass-storage,
- disables SELinux, audit, integrity/FIVE, PROCA, DEFEX, DSMS, SDP and
  Samsung's hypervisor (UH/RKP/KDP),
- disables DPU hibernation and enables `CONFIG_EXYNOS_DPU30_FBCON`.

## Display (`CONFIG_EXYNOS_DPU30_FBCON`)

The stock DPU driver relies on Android's HWC and never shows plain fbdev
writes. With this option (ported from map220v's dpu20 patches):

- the framebuffer stays mapped in the kernel and `fb_read`/`fb_write` use the
  generic helpers,
- `cfb_copyarea`/`cfb_imageblit` are wired up for fbcon,
- decon0 is unblanked at boot and stays on when the last fb client exits,
- a new frame is started on every vsync, and the framebuffer is repainted
  after unblank,
- pixel format is ARGB8888, matching the `fb_var_screeninfo` bitfields.

The option is off in the Android defconfig, so Android builds are unchanged.

## Recovery image

```sh
./build_kernel_linux.sh
make ARCH=arm64 dtbs
linux-recovery/mkrecovery.sh Linux11.img [stock-recovery.img]
```

`Linux11.img` is map220v's prebuilt A51 image (in the history of
`kernel_samsung_a51-linux`, commit `b75d476b9`, `prebuild/Linux11.img`); only
its initramfs userland (busybox, udev) is reused, `/init` is replaced with
`linux-recovery/init`. The result is `linux-recovery/out/Linux-a51x-J4n3K.img`
and `.tar` for Odin.

Without `stock-recovery.img` the header uses the A51 layout from
`linux-recovery/a51x.json` (base `0x10000000`, header v2, page 2048) and a DT
table built from `exynos9630.dtb`. If the bootloader refuses the image, pass
the phone's own `recovery.img` (from `AP_*.tar.md5`, `recovery.img.lz4`,
`lz4 -d`) and its header, dtb and recovery_dtbo are used instead.

The initramfs:

1. finds the `userdata` partition by its GPT name,
2. loop-mounts `linux.img` from it as `/` and runs `/sbin/init`,
3. moves Android's data partition to `/android_data` and mounts EFS
   read-only on `/efs` (and `/mnt/vendor/efs`) if those directories exist
   in the rootfs.

Kernel command line overrides: `linuximg=<path in userdata>`,
`datapart=<partition name>`, `root=<device>` (boot from a partition instead),
`break=premount|postmount` (drop to a shell).

## Dual boot with Android

Android keeps the boot partition, Linux lives in the recovery partition,
the root filesystem is a file on Android's data partition. Nothing is
repartitioned.

Requirements: unlocked bootloader and verified boot disabled (vbmeta), as
for TWRP or Magisk. The recovery partition no longer holds TWRP; flash TWRP
back when you need it.

1. Prepare the root filesystem on a PC, e.g. Arch Linux ARM or Debian arm64:

   ```sh
   truncate -s 8G linux.img
   mkfs.ext4 -L linux linux.img
   sudo mount -o loop linux.img /mnt
   sudo tar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt
   sudo mkdir -p /mnt/android_data /mnt/efs /mnt/mnt/vendor/efs
   # firmware, see below
   sudo umount /mnt
   ```

2. Copy it to the phone (root required):

   ```sh
   adb push linux.img /sdcard/
   adb shell su -c 'mv /sdcard/linux.img /data/linux.img'
   ```

   `/data` itself is not covered by file-based encryption, so Linux can read
   the image without Android's keys. A factory reset deletes it.

3. Flash `Linux-a51x-J4n3K.tar` with Odin in the AP slot (uncheck
   Auto Reboot if you also flash other things), or from root:
   `dd if=Linux-a51x-J4n3K.img of=/dev/block/by-name/recovery`.

Switching:

- Android -> Linux: `adb reboot recovery`, the reboot menu of Magisk/root
  apps, or Volume Up + Power (on Android 11+ Exynos Samsung only with a USB
  cable connected to a PC).
- Linux -> Android: plain `reboot`. If Linux crashes or panics the phone may
  boot Linux again; reboot from the emergency shell with `reboot -f`.

## Firmware from the vendor partition

Copying the whole `/vendor` is not needed, only the firmware:

| Linux path | From Android | Needed for |
|---|---|---|
| `/vendor/etc/wifi/` | `/vendor/etc/wifi/` | Wi-Fi/Bluetooth (the driver opens it directly) |
| `/lib/firmware/` | `/vendor/firmware/` | other `request_firmware()` users |
| `/lib/firmware/sensorhub/shub_neus_a51x.bin` | built into the stock kernel | sensors |
| `/lib/firmware/npu/NPU.bin` | built into the stock kernel | NPU (optional) |

```sh
adb shell su -c 'tar -cf /sdcard/vendor-fw.tar /vendor/etc/wifi /vendor/firmware'
adb pull /sdcard/vendor-fw.tar
# then in the mounted image:
sudo tar -xf vendor-fw.tar -C /mnt
sudo cp -a /mnt/vendor/firmware/. /mnt/lib/firmware/
```

These are proprietary Samsung files, keep them out of this repository.

## Status

Untested on hardware. The kernel and the recovery image build, but boot,
colors, refresh and unblank behaviour still need to be checked on a real
device.
