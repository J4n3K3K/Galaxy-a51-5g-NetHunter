# NetHunter kernel — SM-A516B (Galaxy A51 5G, exynos9630)

Kali NetHunter-ready kernel configuration for the Samsung Galaxy A51 5G
(`SM-A516B`, SoC **exynos9630 / "exynos980"**), based on the stock
Android 13 / One UI 5.1 OSRC source (`4.19.87`).

Target firmware this was prepared against (from the device screenshot):
`A516BXXS9FXE3` — Android 13, One UI 5.1, kernel 4.19.87.

## What was added

A new defconfig `arch/arm64/configs/exynos980-a51x_nethunter_defconfig`
= the stock `exynos980-a51x_defconfig` plus the NetHunter options below.

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

A cross toolchain is required (this source is built with Clang/LLVM +
aarch64 GNU binutils). Proton Clang works well:

```bash
git clone --depth=1 https://github.com/kdrag0n/proton-clang.git ~/proton-clang
export TC=~/proton-clang
./build_nethunter.sh        # see the script; edit TC if needed
```

Or directly:

```bash
export PATH="$TC/bin:$PATH" ARCH=arm64 PLATFORM_VERSION=13 ANDROID_MAJOR_VERSION=t
make ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
     OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
     CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
     CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
     exynos980-a51x_nethunter_defconfig
make ARCH=arm64 CC=clang LD=ld.lld ... -j"$(nproc)" Image dtbs
```

Output: `arch/arm64/boot/Image`.

> Note: the OSRC script dump lost the executable bit on the `scripts/*.sh`
> helpers; this commit restores it so `make` can run them.

## Packaging & flashing (done off-device, outside this repo)

1. Take your stock `boot.img` for `A516BXXS9FXE3`, unpack it
   (e.g. AIK — Android Image Kitchen), replace the kernel with the new
   `Image`, repack.
2. Flash the repacked `boot.img` (Odin AP slot, or `fastboot`/`heimdall`).
3. Install the Kali NetHunter app + chroot on top.

**Prerequisites on the device:** unlocked bootloader (OEM unlocking),
which trips the Knox e-fuse (0x1), and root (Magisk). This kernel keeps
Samsung's RKP/KDP/DEFEX/PROCA/FIVE as-is; if you hit boot/root issues you
may additionally need to disable those in the defconfig.
