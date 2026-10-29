# NetHunter kernel — SM-A516B (Galaxy A51 5G, exynos9630)

Kali NetHunter kernel for the Samsung Galaxy A51 5G (`SM-A516B`, SoC
**exynos9630 / "exynos980"**), built from the stock Android 13 / One UI 5.1
OSRC source (`4.19.87`).

**Verified booting** on firmware `A516BXXS9FXE3`, kernel string
`4.19.87-NetHunter-J4n3K`.

## Two defconfigs

| defconfig | self-protection | use |
|-----------|-----------------|-----|
| `exynos980-a51x_nethunter_defconfig` | stock (RKP+KDP+DEFEX on) | boots like stock; Magisk `su` likely blocked by KDP |
| `exynos980-a51x_nethunter_root_defconfig` | RKP **on**, KDP+DEFEX **off** | for Magisk root on an unlocked bootloader |

Both add, on top of the stock `exynos980-a51x_defconfig`:

- **mac80211 + RFKILL** — the soft-MAC stack external injection adapters
  need (the internal SLSI chip can't do monitor mode / injection).
- **USB Wi-Fi drivers BUILT-IN (`=y`)** — ath9k_htc, carl9170, rt2800usb
  (+rt33/35/3573/53/55xx), rt2500usb, rtl8187, rtl8xxxu, zd1211rw,
  mt7601u, p54usb. ⚠️ They must be `=y`, **not modules**: Samsung RKP
  (kept on, for boot) resets the phone when a module is `insmod`'d at
  runtime. Built-in, they are part of the RKP-approved kernel text and
  simply bind when an adapter is plugged in — no `insmod`, no reset.
  (Covers b/g/n adapters; the out-of-tree **rtl88xxau** AC driver —
  8812au/8821au/8814au — is *not* in mainline 4.19 and is not included.)
- **USB gadget functions** `CONFIG_USB_CONFIGFS_F_HID` (BadUSB / HID) and
  `CONFIG_USB_CONFIGFS_MASS_STORAGE` (DriveDroid).
- `CONFIG_EXTRA_FIRMWARE=""` (the NPU/sensorhub firmware blobs are absent
  from the OSRC; they load from `/vendor/firmware` at runtime).

The `_root_` variant additionally keeps `UH`/`UH_RKP` enabled (the
bootloader hands off to an EL2 micro-hypervisor; a kernel with UH/RKP
disabled panics before console) and disables only `KDP_CRED`/`KDP_NS`/
`KDP_DMAP` (the hypervisor-enforced credential protection that blocks
root), `SECURITY_DEFEX` and `UH_LKM_BLOCK`. `PROCA`, `FIVE` and `UHID`
stay enabled in both.

The base config was verified 1:1 against the device's own
`/proc/config.gz` — the only deltas are the intentional changes above.

## Building

Two toolchains are required, and **both matter** (see notes):

```bash
# 1. The exact AOSP clang Samsung shipped this kernel with (clang 9.0.8)
git clone --depth=1 \
  https://github.com/Cyborg2017/prebuilts_clang_host_linux-x86_clang-r365631c.git \
  ~/clang-r365631c
# 2. GNU aarch64 binutils (external assembler + GNU ld)
sudo apt install -y binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu \
  flex bison bc libssl-dev libelf-dev build-essential

cd Galaxy-a51-5g-NetHunter
CLANG=~/clang-r365631c ./build_nethunter.sh                 # stock-RKP
CLANG=~/clang-r365631c DEFCONFIG=exynos980-a51x_nethunter_root_defconfig \
  ./build_nethunter.sh                                      # root
```

Output: `arch/arm64/boot/Image`, `exynos9630.dtb`, and the Wi-Fi `.ko`
modules under `drivers/net/wireless/`.

### Why these exact tools (hard-won)

- **clang 9.0.8 (r365631c), not newer.** Proton clang 13 compiles the
  tree but the resulting kernel did **not boot** on this device. clang 9
  matches what Samsung used (`CONFIG_CLANG_VERSION`).
- **GNU aarch64 ld for the final link, not ld.lld.** Both ld.lld 9 and 13
  refuse the Samsung RKP `.rkp_ro` section with "unable to move location
  counter backward" (`swapper_pg_dir` is sized from `_end`). GNU ld's
  multi-pass resolution links it.
- **System GCC for host tools** (`HOSTCC=gcc`): Proton's old GNU ld can't
  read modern glibc's `.relr.dyn` when linking host programs like fixdep.
- **`KCFLAGS=-Wno-error`** (Samsung hard-codes bare `-Werror`),
  **`HOSTCFLAGS=-fcommon`** (4.19 `dtc` vs modern GCC), **`LOCALVERSION=`**
  (suppress the git-hash suffix → stable vermagic for modules).

### OSRC source fixes carried in this branch

Samsung's OSRC tarball is incomplete; the build needs these, all included:

- Executable bit restored on `scripts/**/*.sh`, `*.py`, `*.pl` and
  `arch/arm64/kernel/vdso/gen_vdso_offsets.sh` (the dump stripped them,
  silently producing an empty `vdso-offsets.h`).
- Re-created missing uapi netfilter headers: `xt_mark.h`, `xt_dscp.h`,
  `xt_rateest.h`, `ipt_ttl.h`, `ip6t_hl.h`.
- Relocated two camera headers to their canonical include paths:
  `dt-bindings/camera/exynos_is_dt.h`, `linux/videodev2_exynos_camera.h`.
- `firmware/Makefile`: `fwdir` falls back to `firmware/` so the melfas
  touchscreen blob auto-generates from its shipped `.ihex`; absent
  sensorhub blobs dropped from the built-in firmware list.
- `lib/string.c`: added `stpcpy()` (harmless; some clang lowers `strcpy`
  to `stpcpy`).
- Root `.gitignore` (the OSRC dump shipped without one).

## Flashing

This device **does not enforce AVB** on an unlocked bootloader, but it
**does** matter *how* the boot image is written. Take your stock
`boot.img`, replace only the kernel (keep the stock ramdisk + dtb), drop
the AVB footer, and keep the `SEANDROIDENFORCE` tag; zero-fill to the full
partition size so a TWRP `dd` overwrites any stale footer. Then:

- **Odin** (recommended): put the boot image in a `.tar` and flash it in
  the **AP** slot (Download Mode).
- **TWRP**: Install Image → select the `.img` → **Boot** partition.

Always keep a copy of the **stock `boot.img`** to recover via Odin.

### Getting root (Magisk)

The kernel only *enables* root (KDP off); it ships the stock ramdisk, so
Magisk is not installed yet. Patch the root `boot.img` with the Magisk app
("Install → Select and Patch a File"), then flash the `magisk_patched`
image. `su` then works because KDP is disabled.

### Wi-Fi adapters

The drivers are built into the kernel, so **nothing to load** — plug an
adapter in (OTG) and it binds automatically; check with `dmesg` and
`iw dev`. Some chips need firmware in `/vendor/firmware` or
`/lib/firmware` (ath9k_htc → `htc_9271.fw`, carl9170 → `carl9170-1.fw`,
rt2800usb → `rt2870.bin`, …); add it there if `dmesg` reports it missing.
Do **not** try to `insmod` a Wi-Fi module — with RKP on, that resets the
device.

## Prerequisites

Unlocked bootloader (OEM unlocking, trips Knox 0x1) and Magisk. The 5 GHz
internal Wi-Fi is Samsung/SLSI (no monitor/injection) — NetHunter wireless
attacks require an external USB adapter from the list above.
