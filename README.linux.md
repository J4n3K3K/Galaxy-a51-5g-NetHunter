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

## Installation

1. Create `/data/linux.img` and format it with a filesystem the kernel
   supports.
2. Mount it and extract an arm64 (or armhf) rootfs into it, then set it up.
3. Put the built kernel into a recovery image (with a ramdisk that mounts
   `/data/linux.img` as root, e.g. the one from map220v's `Linux11.img`),
   flash it to the recovery partition and reboot to recovery.

Copying the contents of the vendor partition to `/vendor` in the rootfs is
recommended (Wi-Fi firmware).

## Status

Untested on hardware. The changes build, but colors, refresh and
unblank behaviour still need to be checked on a real device.
