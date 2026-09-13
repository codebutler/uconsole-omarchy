#!/usr/bin/env bash
# Build the universal CM4/CM5 Omarchy uConsole raw disk image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

IMG_SIZE="${IMG_SIZE:-12G}"
BOOT_SIZE="${BOOT_SIZE:-512M}"
DISK_ID="${DISK_ID:-0x55434f4e}"
UC_HOSTNAME="${UC_HOSTNAME:-uconsole}"
TIMEZONE="${TIMEZONE:-America/New_York}"
LOCALE="${LOCALE:-en_US.UTF-8}"
TARBALL_URL="${TARBALL_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz}"
OMARCHY_REPO="${OMARCHY_REPO:-https://pkgs.omarchy.org/edge/aarch64}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/out}"
CACHE_DIR="${CACHE_DIR:-${SCRIPT_DIR}/cache}"
WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/work}"
IMG_NAME="${IMG_NAME:-uconsole-omarchy-universal-$(date +%Y%m%d).img}"
IMG_PATH="${OUT_DIR}/${IMG_NAME}"
TARBALL_PATH="${CACHE_DIR}/$(basename "${TARBALL_URL}")"
ROOT_MNT="${WORK_DIR}/root"
LOOPDEV=""

require_root
require_cmds sfdisk losetup mkfs.vfat mkfs.ext4 bsdtar mount chroot
mkdir -p "${OUT_DIR}" "${CACHE_DIR}" "${WORK_DIR}"

fetch_tarball() {
  [[ -f "${TARBALL_PATH}" ]] && { ok "using cached ${TARBALL_PATH}"; return; }
  log "fetching Arch Linux ARM root filesystem"
  local tmp="${TARBALL_PATH}.part"
  if command -v curl >/dev/null; then
    curl -fL --retry 3 -o "${tmp}" "${TARBALL_URL}"
  else
    wget -O "${tmp}" "${TARBALL_URL}"
  fi
  mv "${tmp}" "${TARBALL_PATH}"
  if curl -fsL -o "${TARBALL_PATH}.md5" "${TARBALL_URL}.md5" 2>/dev/null; then
    (cd "${CACHE_DIR}" && md5sum -c "$(basename "${TARBALL_PATH}.md5")")
  fi
}

create_image() {
  log "creating ${IMG_PATH} (${IMG_SIZE}, disk id ${DISK_ID})"
  rm -f "${IMG_PATH}"
  truncate -s "${IMG_SIZE}" "${IMG_PATH}"
  sfdisk "${IMG_PATH}" <<EOF
label: dos
label-id: ${DISK_ID}
unit: sectors
start=2048, size=${BOOT_SIZE}, type=c, bootable
type=83
EOF
  LOOPDEV="$(losetup -f --show -P "${IMG_PATH}")"
  push_cleanup "losetup -d '${LOOPDEV}'"
  for _ in {1..40}; do
    [[ -b "${LOOPDEV}p1" && -b "${LOOPDEV}p2" ]] && break
    sleep 0.25
  done
  [[ -b "${LOOPDEV}p1" && -b "${LOOPDEV}p2" ]] || \
    die "partition devices did not appear for ${LOOPDEV}"
  mkfs.vfat -F32 -n BOOT "${LOOPDEV}p1" >/dev/null
  mkfs.ext4 -q -L ROOT "${LOOPDEV}p2"
}

mount_and_extract() {
  install -d "${ROOT_MNT}"
  mount "${LOOPDEV}p2" "${ROOT_MNT}"
  push_cleanup "umount -Rl '${ROOT_MNT}' 2>/dev/null || true"
  install -d "${ROOT_MNT}/boot"
  mount "${LOOPDEV}p1" "${ROOT_MNT}/boot"
  log "extracting base root filesystem"
  bsdtar -xpf "${TARBALL_PATH}" -C "${ROOT_MNT}"
}

mount_chroot_filesystems() {
  # Keep pacman's construction-time cache outside the image.  The Omarchy
  # transaction downloads roughly 1.6 GiB before its free-space check; those
  # archives are build inputs, not image contents.
  install -d "${CACHE_DIR}/pacman-pkg" "${ROOT_MNT}/var/cache/pacman/pkg"
  rm -rf "${ROOT_MNT}/var/cache/pacman/pkg/"*
  mount --bind "${CACHE_DIR}/pacman-pkg" "${ROOT_MNT}/var/cache/pacman/pkg"
  mount -t proc proc "${ROOT_MNT}/proc"
  mount --rbind /sys "${ROOT_MNT}/sys"
  mount --rbind /dev "${ROOT_MNT}/dev"
  mount --make-rprivate "${ROOT_MNT}/sys"
  mount --make-rprivate "${ROOT_MNT}/dev"
  push_cleanup "umount -Rl '${ROOT_MNT}/proc' '${ROOT_MNT}/sys' '${ROOT_MNT}/dev' '${ROOT_MNT}/var/cache/pacman/pkg' 2>/dev/null || true"
  cp --remove-destination /etc/resolv.conf "${ROOT_MNT}/etc/resolv.conf"
}

prepare_sources() {
  log "copying package recipes into the target build root"
  rm -rf "${ROOT_MNT}/root/uconsole-source"
  install -d "${ROOT_MNT}/root/uconsole-source"
  cp -a "${SCRIPT_DIR}/packages" "${ROOT_MNT}/root/uconsole-source/"
  cp -a "${SCRIPT_DIR}/config" "${ROOT_MNT}/root/uconsole-source/"
  install -Dm0755 "${SCRIPT_DIR}/scripts/build-packages.sh" \
    "${ROOT_MNT}/root/uconsole-source/scripts/build-packages.sh"
  install -Dm0755 "${SCRIPT_DIR}/scripts/customize.sh" "${ROOT_MNT}/root/customize.sh"
  local qemu
  qemu="$(command -v qemu-aarch64-static || true)"
  [[ -z "${qemu}" ]] || install -Dm0755 "${qemu}" "${ROOT_MNT}/usr/bin/qemu-aarch64-static"
}

build_and_customize() {
  mount_chroot_filesystems
  prepare_sources
  log "building signed, kernel-version-matched uConsole packages"
  chroot "${ROOT_MNT}" /root/uconsole-source/scripts/build-packages.sh
  rm -rf "${ROOT_MNT}/var/cache/uconsole/repo"
  install -d "${ROOT_MNT}/var/cache/uconsole"
  mv "${ROOT_MNT}/root/uconsole-repo" "${ROOT_MNT}/var/cache/uconsole/repo"
  rm -rf "${OUT_DIR}/repo"
  cp -a "${ROOT_MNT}/var/cache/uconsole/repo" "${OUT_DIR}/repo"

  local disk_hex="${DISK_ID#0x}"
  local root_partuuid="${disk_hex,,}-02"
  log "installing Omarchy and universal platform configuration"
  chroot "${ROOT_MNT}" /usr/bin/env \
    UC_HOSTNAME="${UC_HOSTNAME}" TIMEZONE="${TIMEZONE}" LOCALE="${LOCALE}" \
    ROOT_PARTUUID="${root_partuuid}" OMARCHY_REPO="${OMARCHY_REPO}" \
    /bin/bash /root/customize.sh

  cat > "${ROOT_MNT}/etc/fstab" <<EOF
# <file system>                 <mount> <type> <options>          <dump> <pass>
PARTUUID=${disk_hex,,}-02       /       ext4   defaults,noatime  0      1
PARTUUID=${disk_hex,,}-01       /boot   vfat   defaults          0      2
EOF
  rm -rf "${ROOT_MNT}/root/uconsole-source" "${ROOT_MNT}/root/customize.sh"
  rm -f "${ROOT_MNT}/usr/bin/qemu-aarch64-static"
  chroot "${ROOT_MNT}" /usr/bin/gpgconf --kill all 2>/dev/null || true
  kill_chroot_procs
}

kill_chroot_procs() {
  local proc root
  for proc in /proc/[0-9]*; do
    root="$(readlink "${proc}/root" 2>/dev/null || true)"
    [[ "${root}" == "${ROOT_MNT}" || "${root}" == "${ROOT_MNT}/"* ]] || continue
    kill "${proc##*/}" 2>/dev/null || true
  done
}

verify_mounted() {
  log "verifying the mounted image"
  local root_id="${DISK_ID#0x}"
  root_id="${root_id,,}-02"
  grep -q "root=PARTUUID=${root_id}" "${ROOT_MNT}/boot/cmdline.txt"
  grep -q '^\[cm4\]' "${ROOT_MNT}/boot/config.txt"
  grep -q '^\[cm5\]' "${ROOT_MNT}/boot/config.txt"
  [[ -s "${ROOT_MNT}/boot/kernel8.img" ]]
  [[ -s "${ROOT_MNT}/boot/initramfs-linux.img" ]]
  [[ -s "${ROOT_MNT}/boot/overlays/clockworkpi-uconsole-cm4.dtbo" ]]
  [[ -s "${ROOT_MNT}/boot/overlays/uconsole-cm5-base.dtbo" ]]
  [[ -s "${ROOT_MNT}/boot/overlays/uconsole-audio-cm5.dtbo" ]]
  [[ ! -e "${ROOT_MNT}/var/lib/tailscale/tailscaled.state" ]]
  if find "${ROOT_MNT}/etc/ssh" -name 'ssh_host_*' -print -quit | grep -q .; then
    die "image contains SSH host keys"
  fi
  ok "mounted-image checks passed"
}

main() {
  fetch_tarball
  create_image
  mount_and_extract
  build_and_customize
  verify_mounted
  # Unmount before hashing. Unmounting an ext4 filesystem commits journal and
  # superblock state, so a checksum taken while it is mounted does not describe
  # the final image copied to the host.
  sync
  run_cleanup
  _cleanup_stack=()
  sync
  (cd "${OUT_DIR}" && sha256sum "${IMG_NAME}" > "${IMG_NAME}.sha256")
  ok "image complete: ${IMG_PATH}"
  ok "checksum: ${IMG_PATH}.sha256"
  ok "signed package repository: ${OUT_DIR}/repo"
}

main "$@"
