# Maintaining the universal uConsole image

## Trust and upstreams

| Component | Source / pinned revision |
|---|---|
| Omarchy | official `https://pkgs.omarchy.org/edge/aarch64` repository |
| Omarchy key | `40DF B630 FF42 BCFF B047 046C F013 4EE6 80CA C571` |
| Kernel | Arch Linux ARM `linux-rpi`, 4K pages |
| CM4 overlay | ClusterM ClockworkPi-linux `213641631845a112a594fb088da0db6f4a00469a` |
| CM4/CM5 modules and CM5 overlays | yota9/uconsole-cm5 `bf7a0ab55654c96b74d013520e1196d39f66391a` |
| AIO controller | HackerGadgets/aiov2_ctl `c21ca742775b32ecea30b334e15a2d7f003e511a` |

All source archives have SHA-256 checksums in their PKGBUILDs. Upstream Omarchy
and the generated uConsole repository require package signatures. The image
build creates an ephemeral signing key, embeds only its public key, and exports
the signed repository to `out/repo`.

For a published repository, build with a protected persistent `GNUPGHOME`,
publish the exported repository directory, and change its `Server` URL. Never
publish or embed the secret key.

## Kernel update procedure

The module PKGBUILD defaults to the installed `linux-rpi` version and header
tree. On-device preparation supplies `UCONSOLE_KERNEL_PACKAGE_VERSION`,
`UCONSOLE_KERNEL_RELEASE`, and `UCONSOLE_KERNEL_BUILD_DIR` to build against
downloaded headers without installing the new kernel first. It sets:

```text
depends=("linux-rpi=<exact pkgver-pkgrel>")
/usr/lib/modules/<kernel release>/updates/uconsole/*.ko.zst
```

The image-local repository is maintained on the device by
`uconsole-prepare-kernel-update`. Omarchy's system-package updater calls it after
refreshing databases and before starting the upgrade transaction. It downloads
signed kernel/headers, verifies exact versions, builds as `uconsole-build`, checks
all nine module vermagic values, and signs the result with a root-only key created
on that device. Only the module package and repository metadata are published;
the actual kernel installation remains pacman's job. Failed downloads, builds,
or verification stop the update without removing the old dependency lock.

`uconsole-configure-omarchy-updates` adds two preparation commands after upstream's
`set -e`. The package hook reapplies that small adaptation on Omarchy upgrades.
It refuses an unrecognized entry point instead of silently assuming integration
still works. The pristine upstream command is saved under `/var/lib/uconsole`.

`uconsole-configure-omarchy-display` similarly reapplies the bounded image-picker
layout and smaller Foot screensaver font after package upgrades, retaining upstream
backups. It refuses unknown source layouts. The user look-and-feel template sizes
floating dialogs relative to the logical monitor and keeps normal terminals tiled.
Keep the bar's monitor scale unchanged when adjusting these content dimensions.

The `uconsole-plymouth` mkinitcpio build hook runs after `plymouth`, adapting
only the initramfs copy of Omarchy's current theme so its progress bar does not
require a disk-unlock prompt. It uses Plymouth's estimated boot progress, not
a timer pretending to measure completion. Unknown upstream script layouts fail
the build. Colors, assets and password prompts remain upstream-owned.
Plymouth exits with `--retain-splash` while preserving normal SDDM ordering;
the greeter compositor disables its unused XWayland server. Retaining a frame
does not guarantee a zero-black-frame transition when DRM ownership changes.

The display adapter adds keyboard-accessible Restart/Shut down buttons to both
Omarchy's packaged SDDM template and its installed theme. Updating the template
preserves the controls across subsequent `omarchy-plymouth-set` theme refreshes;
the package hook reapplies them after upgrades. Actions use SDDM's capability
checks and require confirmation with Cancel focused by default. No suspend
action is exposed. Do not invoke real power actions during UI tests.

Audio requires `pipewire-audio`, `pipewire-alsa`, `pipewire-pulse`, and WirePlumber,
not just the base PipeWire daemon. The ALSA and Bluetooth SPA plugins live in
`pipewire-audio`; without it the kernel can expose sound cards while the desktop
has no audio devices. These are explicit platform dependencies and image packages.

For centrally published packages, when ALARM releases a kernel:

1. Build in a clean aarch64 Arch root with the new `linux-rpi` and
   `linux-rpi-headers` installed.
2. Run `scripts/build-packages.sh`.
3. Confirm every package and `uconsole.db.tar.gz` has a signature.
4. Boot and complete the CM4 hardware checklist.
5. Repeat it on CM5 before changing the universal-verification label.
6. Publish the whole repository atomically. Never publish `linux-rpi` without
   its matching uConsole module package.

Because of the exact dependency, `pacman -Syu` safely reports an unsatisfied
dependency while the repository is between kernel builds. Do not add
`IgnorePkg`; that hides the synchronization problem instead of enforcing it.

## Automated verification

```sh
./tests/test-static.sh
sudo ./scripts/verify-image.sh out/uconsole-omarchy-universal-YYYYMMDD.img
```

The image verifier checks PARTUUID boot/fstab references, package ownership,
the exact kernel dependency, module priority, initramfs and kernel presence,
both generations of DTBs, all uConsole overlays, repository signatures, and
absence of identity/secrets.

The following structural cases use the same bytes and are covered by the boot
filters and storage parser:

| Model/storage | Firmware section | root device parser |
|---|---|---|
| CM4 Lite microSD | `[cm4]` | `/dev/mmcblk*pN` |
| CM4 eMMC | `[cm4]` | `/dev/mmcblk*pN` |
| CM5 Lite microSD | `[cm5]` | `/dev/mmcblk*pN` |
| CM5 eMMC | `[cm5]` | `/dev/mmcblk*pN` |
| directly flashed NVMe | `[cm4]` or `[cm5]` | `/dev/nvme*n*pN` |

## Physical hardware checklist

Run the entire list after every kernel, module, overlay, firmware, Omarchy, or
boot configuration change.

### CM4 (old and new panel batches where possible)

- [ ] Plymouth hands off to scaled SDDM; Omarchy starts through UWSM.
- [ ] DSI image is clean, landscape, and correctly scaled.
- [ ] DRM/V3D acceleration and Vulkan Broadcom driver work.
- [ ] AXP228 reports battery presence, charge percentage, health, voltage, and
      charger state; test charge termination without bypassing the PMIC.
- [ ] Backlight levels and permissions work.
- [ ] Internal speaker and headphone switching work.
- [ ] Keyboard, trackball, mouse buttons, and A/B/X/Y hold modes work.
- [ ] Wi-Fi/Bluetooth work; NetworkManager is the only network manager.
- [ ] `chronyc tracking` synchronizes after wireless association.
- [ ] Root expands on microSD and exposed eMMC.
- [ ] `vcgencmd get_throttled` shows no undervoltage/thermal history.

### HackerGadgets upgrade kit

- [ ] NVMe enumerates but an existing disk is unchanged.
- [ ] Gigabit Ethernet works.
- [ ] CM4 USB 2 works; CM5 exposes the one supported USB 3 host port.
- [ ] CM4 fixed fan and CM5 firmware-controlled PWM fan behave correctly.
- [ ] CSI camera enumerates.
- [ ] Optional MT7921AUN Wi-Fi and Bluetooth enumerate with MediaTek firmware.
- [ ] `uconsole-aio-config` enables the intended model section only.
- [ ] Installing AIO tools alone leaves every gated rail untouched.
- [ ] Explicit GPS/LoRa/SDR/internal-USB rail choices persist across boot.

### CM5 additions

- [ ] Repeat every applicable CM4 test on physical CM5 hardware.
- [ ] BCM2712 DTB and CM5 panel/audio overlays are active.
- [ ] RP1 audio, headphone detection, and amplifier auto-mute work.
- [ ] Internal RTC keeps time using the kit RTC battery connector.
- [ ] EEPROM boot order and firmware are recorded.
- [ ] Thermal/fan behavior and undervoltage history remain healthy under load.
- [ ] Flash the identical artifact to microSD and CM5 eMMC; both boot and expand.

Only after the CM4 checklist passes may an artifact be labeled
**CM4-tested / CM5-candidate**. Until then both models are candidates.

## Omarchy package delta

`config/omarchy/packages.txt` starts from Omarchy's full aarch64 base list.
Removed: `asdcontrol`, `bolt`, `dotnet-runtime`, `kernel-modules-hook`,
`obs-studio`, `obsidian`, `pinta`, `qemu-user-static-binfmt`, and
`power-profiles-daemon`. Replacements: `wf-recorder` for GPU Screen Recorder and
`neovim` for `nvim`. Added: `linux-rpi`, `vulkan-broadcom`, `upower`, `chrony`,
`python-evdev`, `libgpiod`, `raspberrypi-utils`, and `tailscale`.

Rationale: remove x86-only, unsupported, heavyweight optional, and suspend/power
daemon assumptions; retain the complete Omarchy shell; add Raspberry Pi graphics,
hardware, time, input, and portable-networking integration.

Do not copy Omarchy's x86 pacman mirror configuration. Keep ALARM's `core` and
`extra` mirrors, and add only Omarchy's `edge/aarch64` repository. It must have
higher priority than ALARM `extra` because Omarchy publishes ABI-matched rebuilds
of packages such as Hyprland and Hyprtoolkit.
