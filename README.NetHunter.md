# NetHunter kernel — SM-A516B (Galaxy A51 5G, exynos9630)

Kali NetHunter-ready kernel configuration for the Samsung Galaxy A51 5G
(`SM-A516B`, SoC **exynos9630 / "exynos980"**), based on the stock
Android 13 / One UI 5.1 OSRC source (`4.19.87`).

Target firmware this was prepared against (from the device screenshot):
`A516BXXS9FXE3` — Android 13, One UI 5.1, kernel 4.19.87.

## What was added

Two defconfigs are provided:

| defconfig | RKP/KDP/DEFEX | Use |
|-----------|---------------|-----|
| `exynos980-a51x_nethunter_defconfig` | **on** (stock) | stock-faithful; boots like stock but Magisk/`su` is likely blocked |
| `exynos980-a51x_nethunter_root_defconfig` | **off** | for Magisk root on an unlocked bootloader |

Both = the stock `exynos980-a51x_defconfig` plus the NetHunter options
below; the `_root_` one additionally disables Samsung's kernel
self-protection (`UH`/`UH_RKP`, `KDP_CRED`/`KDP_NS`/`KDP_DMAP`,
`UH_LKM_BLOCK`, `SECURITY_DEFEX`) so root can change process credentials.
`PROCA`, `FIVE` and `UHID` stay enabled in both. The config was verified
1:1 against the device's own `/proc/config.gz` (A516BXXS9FXE3) — the only
deltas are these intentional NetHunter/root changes.

### 802.11 soft-MAC stack (for external injection adapters)
The internal Samsung/SLSI Wi-Fi chip does **not** support monitor mode or
packet injection, so NetHunter relies on an external USB adapter. That needs
the `mac80211` stack, which the stock kernel ships disabled:

- `CONFIG_MAC80211=y` (+ minstrel rate control, mesh, LEDs)
- `CONFIG_RFKILL=y`

### USB Wi-Fi drivers with monitor-mode / injection (built-in)
| Driver | Chips / common adapters |
|--------|-------------------------|
| `ATH9K_HTC` | Atheros AR9271 / AR7010 — TP-Link TL-WN722N v1, Alfa AWUS036NHA |
| `CARL9170`  | Atheros AR9170 USB |
| `RT2800USB` (+ RT33xx/35xx/3573/53xx/55xx/unknown) | Ralink RT3070 / RT5370 |
| `RT2500USB` | Ralink RT2500 USB |
| `RTL8187`   | Realtek RTL8187 — Alfa AWUS036H |
| `RTL8XXXU` (+ untested IDs) | Realtek RTL8188/8192/8723 USB |
| `ZD1211RW`  | ZyDAS ZD1211 |
| `MT7601U`   | MediaTek MT7601U |
| `P54_USB`   | Prism54 USB |

(All the wired-USB NIC drivers — AX88179, RTL8152, etc. — were already on.)

### USB gadget functions
- `CONFIG_USB_CONFIGFS_F_HID=y` — HID keyboard gadget ("BadUSB" / HID attacks)
- `CONFIG_USB_CONFIGFS_MASS_STORAGE=y` — DriveDroid / USB CD-ROM emulation

### Already present in the stock config (verified, no change needed)
`CONFIG_MODULES=y` (unsigned — out-of-tree drivers load), netfilter NAT /
`TPROXY` / `REDIRECT` / `NETMAP` / `MASQUERADE`, all `WLAN_VENDOR_*` switches,
`CONFIG_CFG80211` + WEXT, `CONFIG_UHID`.

> Out-of-tree Realtek drivers (8812au/8821au/88x2bu, 8188eu, 8821cu) that
> ship with NetHunter are **not** in a 4.19 tree. Build them as external
> modules against this kernel, or add them under `drivers/net/wireless/`
> and extend the defconfig.

## Building

A cross toolchain is required. This was built and verified with
**Proton Clang 13.0.0** (LLVM) plus its bundled aarch64/arm GNU binutils,
on an Ubuntu 24.04 (glibc 2.39) host:

```bash
git clone --depth=1 https://github.com/kdrag0n/proton-clang.git ~/proton-clang
sudo apt-get install -y flex bison bc libssl-dev libelf-dev build-essential
cd Galaxy-a51-5g-NetHunter
TC=~/proton-clang ./build_nethunter.sh                 # stock-RKP variant
# root variant (RKP/KDP/DEFEX off):
TC=~/proton-clang DEFCONFIG=exynos980-a51x_nethunter_root_defconfig ./build_nethunter.sh
```

Output: `arch/arm64/boot/Image` (~33 MB) and
`arch/arm64/boot/dts/exynos/exynos9630.dtb`.

The build script documents the exact `make` flags. The non-obvious ones,
all needed because Proton Clang 13 is much newer than the clang this 4.19
tree was written for:

- **Host tools with the system GCC** (`HOSTCC=gcc`) so `fixdep` links
  against the RELR-capable system `ld` (Proton's old GNU `ld` can't read
  glibc 2.39's `.relr.dyn`).
- **`as`/`ld` symlinks** in the toolchain pointing at the aarch64 binutils
  (clang's `--prefix` otherwise picks the x86 `as`/`ld`, which reject
  `-EL` / `aarch64linux`).
- **`LD=aarch64-linux-gnu-ld`** for the final link: Proton's `ld.lld` 13
  refuses the backward location-counter move Samsung's RKP `.rkp_ro`
  section needs; GNU ld handles it.
- **`KCFLAGS=-Wno-error`** (Samsung hard-codes bare `-Werror`) and
  **`HOSTCFLAGS=-fcommon`** (4.19 `dtc` vs modern GCC `-fno-common`).

### OSRC source fixes carried in this branch

Samsung's OSRC tarball is incomplete; the build needs these, all included:

- Executable bit restored on `scripts/**/*.sh`, `*.py`, `*.pl` and
  `arch/arm64/kernel/vdso/gen_vdso_offsets.sh` (the dump stripped them,
  which silently produced an empty `vdso-offsets.h`).
- Re-created missing uapi netfilter headers: `xt_mark.h`, `xt_dscp.h`,
  `xt_rateest.h`, `ipt_ttl.h`, `ip6t_hl.h` (canonical mainline content).
- Relocated two camera headers to their canonical include paths:
  `dt-bindings/camera/exynos_is_dt.h` and `linux/videodev2_exynos_camera.h`.
- `firmware/Makefile`: `fwdir` falls back to `firmware/` so the touchscreen
  blob (`tsp_melfas/mss100_a51x.fw`) auto-generates from its shipped
  `.ihex`; the `sensorhub` blobs (no source in the OSRC) are dropped from
  the built-in list and load from `/vendor/firmware` at runtime. The NPU
  blob is likewise not built in (`CONFIG_EXTRA_FIRMWARE=""`).
- `lib/string.c`: added `stpcpy()` (newer clang lowers some `strcpy()`
  uses to `stpcpy`, which 4.19 otherwise lacks → link error).

## Packaging & flashing (done off-device, outside this repo)

1. Take your stock `boot.img` for `A516BXXS9FXE3`, unpack it
   (e.g. AIK — Android Image Kitchen), replace the kernel with the new
   `Image`, repack.
2. Flash the repacked `boot.img` (Odin AP slot, or `fastboot`/`heimdall`).
3. Install the Kali NetHunter app + chroot on top.

**Prerequisites on the device:** unlocked bootloader (OEM unlocking),
which trips the Knox e-fuse (0x1), and root (Magisk). For working Magisk
root use the **`_root_` variant** (RKP/KDP/DEFEX off) — the stock-RKP
variant will boot but `su` is likely blocked by `KDP_CRED`/`DEFEX`. Keep
the stock-RKP build as a fallback in case the RKP-off kernel misbehaves on
your firmware.
