# uConsole Omarchy

A universal Omarchy image builder and hardware integration layer for ClockworkPi
uConsole, maintained at [codebutler/uconsole-omarchy](https://github.com/codebutler/uconsole-omarchy).

Derived from [fabiiw05/uconsole-archlinux](https://github.com/fabiiw05/uconsole-archlinux),
with its Git history and MIT license preserved. This project installs upstream
[Omarchy](https://github.com/omacom/omarchy) packages; it is an independent hardware
port, not an official Omarchy or ClockworkPi release. Device-specific packages
and a small set of upgrade-time adaptations live here, rather than a fork of the
complete Omarchy shell.

This project builds one aarch64 raw image for a stock uConsole or the
[HackerGadgets upgrade kit](https://hackergadgets.com/products/uconsole-upgrade-kit),
using either Raspberry Pi CM4 or CM5:

- CM4 Lite from microSD
- CM4 with eMMC, after exposing eMMC over USB
- CM5 Lite from microSD
- CM5 with eMMC, after exposing eMMC through the upgrade kit flash port
- an NVMe drive to which the same image was written, when EEPROM boot order permits

The image does not copy itself between drives and never formats an attached
NVMe device. Non-Lite Compute Modules cannot boot from the uConsole microSD
socket; write the same image to their eMMC instead.

Artifacts remain hardware candidates until tested. Use **CM4-tested / CM5-candidate**
only after that exact artifact passes the CM4 checklist in [MAINTAINING.md](MAINTAINING.md).

See [handheld controls and integration](HANDHELD.md) for the native orange
theme, face-button modes, shortcut browser, idle dimming and mpv defaults.

## Build on macOS

Docker Desktop or OrbStack is required. Nothing is installed on macOS:

```sh
./scripts/build-in-docker.sh
```

The build runs as native `linux/arm64`, keeps loop-backed working files in a
case-sensitive Docker volume, and writes these artifacts:

```text
out/uconsole-omarchy-universal-YYYYMMDD.img
out/uconsole-omarchy-universal-YYYYMMDD.img.sha256
out/repo/                 signed uConsole pacman repository
```

The default image is 12 GiB and therefore needs a nominal 16 GB or larger card.
It expands its root partition on first boot. Common overrides:

```sh
IMG_SIZE=14G TIMEZONE=Europe/London UC_HOSTNAME=deck ./scripts/build-in-docker.sh
```

Linux builders can run `sudo ./build.sh` directly with `sfdisk`, `losetup`,
`dosfstools`, `e2fsprogs`, `bsdtar`, and an aarch64 execution environment.

## Flash

Raspberry Pi Imager's **Use custom** action accepts the `.img`. On macOS:

```sh
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=out/uconsole-omarchy-universal-YYYYMMDD.img of=/dev/rdiskN bs=4m
diskutil eject /dev/diskN
```

Selecting the wrong output disk destroys its existing contents. For Compute
Module eMMC, expose it as USB mass storage first, then use Imager or `dd` in
exactly the same way. See Raspberry Pi's
[Compute Module flashing documentation](https://www.raspberrypi.com/documentation/computers/compute-module.html).

## What is integrated

The base is Arch Linux ARM plus Omarchy's official `edge/aarch64` repository and
upstream Quickshell. It uses SDDM, UWSM, Plymouth, a 1.6× rotated DSI output, and
the scrolling Hyprland layout.

The normal ALARM `linux-rpi` package supplies the 4K `kernel8.img`, firmware,
BCM2711/BCM2712 DTBs, and initramfs preset. Three signed local packages add the
device-specific layer:

- `uconsole-modules-linux-rpi`: panel, backlight, AXP228 battery/PMIC, regulator,
  power-key, ADC, and CM5 amplifier modules. It depends on the exact installed
  `linux-rpi` package version, so pacman refuses an unsafe kernel-only upgrade.
- `uconsole-platform`: CM4/CM5 overlays, universal boot configuration, first-boot
  expansion, controls, Wi-Fi recovery, battery/backlight/audio integration, and
  uConsole game-button translation.
- `uconsole-aiov2-ctl`: the MIT HackerGadgets controller. Its service has a
  `ConditionPathExists` guard; no rail is driven until the user explicitly saves
  a rail state.

The upgrade kit gets PCIe/NVMe, Ethernet, CM4 USB 2, CM5 USB 3 host mode, the
CM5 firmware-managed PWM fan, CSI camera autodetection, CM5 RTC, and optional
MT7921AUN support from the kernel plus MediaTek firmware. Hardware limitations
remain hardware limitations: the kit's Type-C USB 3 data port is presently not
functional, only one CM5 USB 3 port is expected, and RPITX remains experimental.

## Optional AIO V2 board

The tools are always present, but optional buses and every GPIO-gated rail are
off by default:

```sh
sudo uconsole-aio-config enable     # detects CM4/CM5; enables model-specific RTC/SPI/UART config
sudo aiov2_ctl --boot-rail GPS on   # explicit, persistent user choice
sudo aiov2_ctl --boot-rails-status
sudo reboot
```

The base upgrade kit uses CM5's internal RTC through its battery connector.
When AIO V2 integration is explicitly enabled, CM5 instead uses the AIO board's
PCF85063A, as required by HackerGadgets' wiring and setup instructions.
The GPS UART is free because the image does not place a serial console on it.
Read the manufacturer's physical installation guide: ribbon orientation cannot
be protected by software.

## Updates

Use Omarchy's updater (including its graphical update button):

```sh
omarchy update
```

The platform package adds a preparation step to Omarchy's system-package update
command. When a new kernel arrives, it downloads signature-verified kernel and
header packages, builds the nine drivers as an unprivileged user against the
unpacked headers, checks their ABI, and publishes a signed module package to the
local repository. It does not replace the running kernel during preparation.
Omarchy then updates the kernel and drivers together through pacman.

The signing key is generated on the device, stays root-only under
`/var/lib/uconsole/package-signing`, and is never included in fresh images.
Compilation failure leaves the existing kernel installed and the version lock intact.
The small Omarchy adapter is reapplied by a package hook after Omarchy upgrades.
Build tools are runtime dependencies for this reason. Direct `pacman -Syu` still
stops safely if matching drivers have not been prepared; use Omarchy's updater.

There is no file-injected kernel. A new
`linux-rpi` can only install when the configured uConsole repository also has a
`uconsole-modules-linux-rpi` package whose exact dependency matches it. See
[MAINTAINING.md](MAINTAINING.md) for publishing that matched package.

## Privacy and identity

The image contains no wireless profiles, Tailscale state, SSH host keys,
machine ID, or build signing secret. SSH host keys and machine ID are generated
on first boot. Tailscale is installed but unauthenticated.

## Project layout

```text
build.sh                         Linux image builder
scripts/build-in-docker.sh       macOS/Docker entry point
scripts/build-packages.sh        builds and signs the local pacman repository
scripts/customize.sh             installs Omarchy inside the image
scripts/verify-image.sh          mounted-image verification
packages/                        three uConsole PKGBUILDs
config/omarchy/packages.txt      full Omarchy list plus documented ARM delta
tests/test-static.sh             fast invariants and lint checks
```
