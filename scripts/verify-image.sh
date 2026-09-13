#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:-$(find "${ROOT_DIR}/out" -maxdepth 1 -name '*.img' -print | sort | tail -1)}"
[[ -f "${IMAGE}" ]] || { echo "usage: sudo $0 path/to/image.img" >&2; exit 2; }
[[ "${EUID}" -eq 0 ]] || { echo "run as root" >&2; exit 1; }

mount_dir="$(mktemp -d)"
loop=""
cleanup() {
  umount -R "${mount_dir}" 2>/dev/null || true
  [[ -z "${loop}" ]] || losetup -d "${loop}" 2>/dev/null || true
  rmdir "${mount_dir}" 2>/dev/null || true
}
trap cleanup EXIT

loop="$(losetup -f --show -rP "${IMAGE}")"
for _ in {1..40}; do [[ -b "${loop}p2" ]] && break; sleep 0.25; done
mount -o ro "${loop}p2" "${mount_dir}"
mount -o ro "${loop}p1" "${mount_dir}/boot"
# Read-only chroot inspection still needs working device nodes and scratch
# space for gpg/lsinitcpio.  These are ephemeral submounts; the image stays RO.
mount -t proc proc "${mount_dir}/proc"
mount --rbind /dev "${mount_dir}/dev"
mount --make-rprivate "${mount_dir}/dev"
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "${mount_dir}/tmp"

root_id="$(blkid -s PARTUUID -o value "${loop}p2")"
boot_id="$(blkid -s PARTUUID -o value "${loop}p1")"
grep -q "root=PARTUUID=${root_id}" "${mount_dir}/boot/cmdline.txt"
grep -qw 'plymouth.ignore-serial-consoles' "${mount_dir}/boot/cmdline.txt"
grep -q "PARTUUID=${root_id}" "${mount_dir}/etc/fstab"
grep -q "PARTUUID=${boot_id}" "${mount_dir}/etc/fstab"

in_image() { chroot "${mount_dir}" "$@"; }

for pkg in linux-rpi uconsole-modules-linux-rpi uconsole-platform uconsole-aiov2-ctl openterfaceqt omarchy quickshell sddm uwsm pipewire-audio pipewire-alsa pipewire-pulse wireplumber rtkit xdg-desktop-portal-xapp; do
  in_image pacman -Q "${pkg}" >/dev/null
done
in_image test -x /usr/bin/openterfaceQT
in_image pacman -Qo /usr/bin/openterfaceQT | grep -q openterfaceqt
in_image test ! -e /opt/openterfaceqt
in_image test -f /usr/share/applications/com.openterface.openterfaceQT.desktop
in_image test -f /usr/lib/udev/rules.d/70-openterfaceqt.rules
for pkg in linux-rpi-headers linux-aarch64 uboot-raspberrypi; do
  if in_image pacman -Q "${pkg}" >/dev/null 2>&1; then
    echo "image contains build-only or conflicting package: ${pkg}" >&2
    exit 1
  fi
done
grep -qx 'User=alarm' "${mount_dir}/var/lib/sddm/state.conf"
[[ "$(stat -c %u "${mount_dir}/var/lib/sddm/state.conf")" == "$(in_image id -u sddm)" ]]
[[ -x "${mount_dir}/usr/bin/uconsole-prepare-kernel-update" ]]
[[ -f "${mount_dir}/usr/share/uconsole/kernel-package/PKGBUILD" ]]
grep -Fq '/usr/bin/uconsole-prepare-kernel-update' "${mount_dir}/usr/share/omarchy/bin/omarchy-update-system-pkgs"
grep -Fq 'tag = "-floating-window"' "${mount_dir}/home/alarm/.config/hypr/looknfeel.lua"
grep -Fq 'panel.height -' "${mount_dir}/usr/share/omarchy/shell/plugins/image-picker/ImagePicker.qml"
grep -Fq 'font=JetBrainsMono Nerd Font:size=10' "${mount_dir}/usr/share/omarchy/default/foot/screensaver.ini"
grep -qx 'uconsole' "${mount_dir}/home/alarm/.local/state/omarchy/current/theme.name"
grep -Fq '#ff6b1a' "${mount_dir}/home/alarm/.local/state/omarchy/current/theme/colors.toml"
grep -qx 'Papirus-Dark-Deeporange' "${mount_dir}/home/alarm/.local/state/omarchy/current/theme/icons.theme"
in_image test -f /usr/share/icons/Papirus-Dark-Deeporange/48x48/places/folder.svg
grep -qx 'CriticalPowerAction=PowerOff' "${mount_dir}/etc/UPower/UPower.conf.d/90-uconsole.conf"
grep -Fq 'ATTR{constant_charge_current_max}="1500000", ATTR{constant_charge_current}="1500000"' "${mount_dir}/usr/lib/udev/rules.d/90-uconsole-charging.rules"
grep -Fq 'org.freedesktop.impl.portal.Settings=xapp;gtk' "${mount_dir}/etc/xdg/xdg-desktop-portal/hyprland-portals.conf"
grep -Fq '/usr/bin/uconsole-sync-gtk-theme' "${mount_dir}/usr/share/omarchy/bin/omarchy-theme-set-gnome"
[[ -L "${mount_dir}/usr/lib/systemd/user/graphical-session.target.wants/uconsole-theme-sync.service" ]]
grep -qx 'FONT=ter-128n' "${mount_dir}/etc/vconsole.conf"
grep -Fq '/usr/share/uconsole/omarchy/bindings.lua' "${mount_dir}/home/alarm/.config/hypr/bindings.lua"
grep -Fq 'uconsole-window width' "${mount_dir}/usr/share/uconsole/omarchy/bindings.lua"
grep -Fq 'uconsoleDimMonitor' "${mount_dir}/usr/share/omarchy/shell/plugins/services/idle/Service.qml"
grep -Fq 'include=/usr/share/uconsole/mpv/mpv.conf' "${mount_dir}/home/alarm/.config/mpv/mpv.conf"
[[ ! -d "${mount_dir}/var/lib/uconsole/package-signing/private-keys-v1.d" ]]
linux_pkg="$(in_image pacman -Q linux-rpi | awk '{print $2}')"
in_image pacman -Qi uconsole-modules-linux-rpi \
  | grep -q "linux-rpi=${linux_pkg}"

shopt -s nullglob
cm4_dtbs=("${mount_dir}"/boot/bcm2711*.dtb)
cm5_dtbs=("${mount_dir}"/boot/bcm2712*.dtb)
modules=("${mount_dir}"/usr/lib/modules/*/updates/uconsole/panel-cwu50.ko*)
((${#cm4_dtbs[@]} > 0 && ${#cm5_dtbs[@]} > 0 && ${#modules[@]} > 0))
for overlay in clockworkpi-uconsole-cm4 uconsole-cm5-base uconsole-audio-cm5; do
  [[ -s "${mount_dir}/boot/overlays/${overlay}.dtbo" ]]
  in_image pacman -Qo "/boot/overlays/${overlay}.dtbo" \
    | grep -q uconsole-platform
done
[[ -s "${mount_dir}/boot/kernel8.img" && -s "${mount_dir}/boot/initramfs-linux.img" ]]
grep -Rqs 'updates/uconsole/panel-cwu50' "${mount_dir}"/usr/lib/modules/*/modules.dep
initramfs_listing="$(in_image lsinitcpio /boot/initramfs-linux.img)"
grep -Fq 'usr/lib/udev/rules.d/90-uconsole-charging.rules' <<< "${initramfs_listing}"
for required in panel-cwu50 ocp8178_bl i2c-bcm2708 i2c-gpio i2c-brcmstb axp20x-i2c axp20x-regulator plymouth usr/lib/plymouth/renderers/drm.so usr/share/plymouth/themes/omarchy/omarchy.script; do
  grep -Fq "${required}" <<< "${initramfs_listing}"
done

for package in "${mount_dir}"/var/cache/uconsole/repo/*.pkg.tar.*; do
  [[ "${package}" == *.sig ]] && continue
  [[ -s "${package}.sig" ]]
  image_package="${package#"${mount_dir}"}"
  in_image gpgv --keyring /etc/pacman.d/gnupg/pubring.gpg \
    "${image_package}.sig" "${image_package}" >/dev/null
done
repo_db=/var/cache/uconsole/repo/uconsole.db.tar.gz
[[ -s "${mount_dir}${repo_db}.sig" ]]
in_image gpgv --keyring /etc/pacman.d/gnupg/pubring.gpg \
  "${repo_db}.sig" "${repo_db}" >/dev/null

[[ ! -e "${mount_dir}/var/lib/tailscale/tailscaled.state" ]]
if find "${mount_dir}/etc/ssh" -name 'ssh_host_*' -print -quit | grep -q .; then
  echo "image contains SSH host keys" >&2; exit 1
fi
if find "${mount_dir}/etc/NetworkManager/system-connections" -type f -print -quit 2>/dev/null | grep -q .; then
  echo "image contains NetworkManager profiles" >&2; exit 1
fi
if grep -q '^IgnorePkg' "${mount_dir}/etc/pacman.conf"; then
  echo "image contains a forbidden IgnorePkg rule" >&2; exit 1
fi

grep -q '/dev/mmcblk\*p\|/dev/nvme\*n\*p' "${mount_dir}/usr/bin/uconsole-resize-rootfs"
grep -q '^\[cm4\]' "${mount_dir}/boot/config.txt"
grep -q '^\[cm5\]' "${mount_dir}/boot/config.txt"
grep -q '^kernel=kernel8.img' "${mount_dir}/boot/config.txt" && {
  echo "boot config must use linux-rpi's standard kernel fallback, not override kernel=" >&2
  exit 1
}

echo "image verification passed: ${IMAGE}"
echo "root=${root_id} boot=${boot_id} linux-rpi=${linux_pkg}"
