#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t shell_files < <(find . -type f \( -name '*.sh' -o -path '*/usr/bin/*' -o -path '*/usr/lib/uconsole/*' \))
for file in "${shell_files[@]}"; do
  head -1 "${file}" | grep -qE '(bash|/sh)$' || continue
  bash -n "${file}"
done
for pkgbuild in packages/*/PKGBUILD; do bash -n "${pkgbuild}"; done

boot=packages/uconsole-platform/rootfs/usr/share/uconsole/boot/config.txt
cmdline=packages/uconsole-platform/rootfs/usr/share/uconsole/boot/cmdline.txt
grep -q '^\[cm4\]' "${boot}"
grep -q '^\[cm5\]' "${boot}"
grep -q 'dtoverlay=clockworkpi-uconsole-cm4' "${boot}"
grep -q 'dtoverlay=uconsole-cm5-base' "${boot}"
grep -q 'dtoverlay=uconsole-audio-cm5' "${boot}"
grep -q 'initramfs initramfs-linux.img followkernel' "${boot}"
grep -q 'root=PARTUUID=@ROOT_PARTUUID@' "${cmdline}"
if grep -RqE 'root=/dev/|/dev/mmcblk0p1' config packages scripts build.sh; then exit 1; fi
if grep -RqE '^IgnorePkg|kernel8-cm4|install_kernel_artifacts' config packages scripts build.sh lib; then exit 1; fi

modules=packages/uconsole-modules-linux-rpi/PKGBUILD
# shellcheck disable=SC2016
grep -Fq 'depends=("linux-rpi=${_linux_pkgver}")' "${modules}"
grep -Fq '/updates/uconsole' "${modules}"
grep -q 'linux-rpi-headers' "${modules}"
grep -q 'UCONSOLE_KERNEL_BUILD_DIR' "${modules}"
grep -q 'uconsole-initialize-login' scripts/customize.sh
grep -Fq 'tag = "-floating-window"' packages/uconsole-platform/rootfs/usr/share/uconsole/omarchy/looknfeel.lua
grep -q 'uconsole-configure-omarchy-updates' packages/uconsole-platform/rootfs/usr/share/libalpm/hooks/95-uconsole-omarchy-updates.hook

packages=config/omarchy/packages.txt
for removed in asdcontrol bolt dotnet-runtime kernel-modules-hook obs-studio obsidian pinta qemu-user-static-binfmt power-profiles-daemon gpu-screen-recorder nvim; do
  if grep -qx "${removed}" "${packages}"; then exit 1; fi
done
for wanted in omarchy-nvim neovim wf-recorder vulkan-broadcom upower chrony python-evdev libgpiod raspberrypi-utils tailscale linux-rpi linux-firmware-mediatek; do
  grep -qx "${wanted}" "${packages}"
done

grep -q 'ConditionPathExists=/var/lib/aiov2_ctl/config.json' \
  packages/uconsole-aiov2-ctl/aiov2-rails-boot.service
aio_config=packages/uconsole-platform/rootfs/usr/bin/uconsole-aio-config
grep -q "dtoverlay=i2c-rtc,pcf85063a,i2c_csi_dsi0" "${aio_config}"
grep -q "dtparam=uart0" "${aio_config}"
grep -q "Do not enable spi0" "${aio_config}"
if find packages config -type f -print0 | xargs -0 grep -nE \
  '(tailscaled\.state|psk=|password=|ssh_host_(rsa|ecdsa|ed25519)_key)' | grep -v 'verify-image.sh'; then
  exit 1
fi

if command -v shellcheck >/dev/null; then
  mapfile -t checked_shell < <(for file in build.sh lib/common.sh scripts/*.sh \
    packages/uconsole-platform/rootfs/usr/bin/* packages/uconsole-platform/rootfs/usr/lib/uconsole/*; do
    head -1 "${file}" | grep -qE '(bash|/sh)$' && echo "${file}"
  done)
  shellcheck "${checked_shell[@]}"
fi

echo "static checks passed"
python3 tests/test-platform.py
if command -v lua >/dev/null; then lua tests/test-mpv.lua; fi
