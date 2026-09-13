#!/usr/bin/env bash
# Build and sign the uConsole packages inside an aarch64 Arch Linux root.
set -euo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-/root/uconsole-source}"
REPO_OUT="${REPO_OUT:-/root/uconsole-repo}"
BUILD_ROOT="${BUILD_ROOT:-/var/tmp/uconsole-package-build}"
PACMAN=(pacman --disable-sandbox)

[[ "$(uname -m)" == aarch64 ]] || {
  echo "build-packages.sh must run in an aarch64 root (native or qemu)" >&2
  exit 1
}
[[ -d "${SOURCE_ROOT}/packages" ]] || {
  echo "missing ${SOURCE_ROOT}/packages" >&2
  exit 1
}

pacman-key --init
pacman-key --populate archlinuxarm
"${PACMAN[@]}" -Syu --noconfirm
for old_kernel in linux-aarch64 uboot-raspberrypi; do
  if pacman -Qq "${old_kernel}" >/dev/null 2>&1; then
    "${PACMAN[@]}" -Rdd --noconfirm "${old_kernel}"
  fi
done
"${PACMAN[@]}" -S --needed --noconfirm \
  base-devel git dtc linux-rpi linux-rpi-headers gnupg imagemagick python papirus-icon-theme

id -u uconsole-build >/dev/null 2>&1 || useradd -m -s /bin/bash uconsole-build
rm -rf "${BUILD_ROOT}"
install -d -o uconsole-build -g uconsole-build "${BUILD_ROOT}"
cp -a "${SOURCE_ROOT}/packages/." "${BUILD_ROOT}/"
chown -R uconsole-build:uconsole-build "${BUILD_ROOT}"

build_one() {
  local name="$1"
  runuser -u uconsole-build -- bash -lc \
    "cd '${BUILD_ROOT}/${name}' && makepkg --nodeps --noconfirm --cleanbuild --clean"
}

build_one uconsole-modules-linux-rpi
module_pkg="$(find "${BUILD_ROOT}/uconsole-modules-linux-rpi" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -print -quit)"
"${PACMAN[@]}" -U --noconfirm "${module_pkg}"
build_one uconsole-platform
build_one uconsole-aiov2-ctl
# Build the native KVM app against Arch libraries (never a bundled AppImage).
"${PACMAN[@]}" -S --needed --noconfirm cmake ninja qt6-tools extra-cmake-modules \
  qt6-base qt6-declarative qt6-multimedia qt6-serialport qt6-svg qt6-wayland \
  ffmpeg gstreamer gst-plugins-base gst-plugins-good libpulse libusb v4l-utils \
  libjpeg-turbo libgudev libglvnd libxkbcommon wayland zlib libx11 libxrandr \
  libxrender libxi libxv libxcb xcb-util-cursor tesseract leptonica
build_one openterfaceqt

install -d "${REPO_OUT}"
find "${BUILD_ROOT}" -maxdepth 2 -name '*.pkg.tar.*' ! -name '*.sig' -exec cp -f {} "${REPO_OUT}/" \;

ephemeral_keyring=0
if [[ -z "${GNUPGHOME:-}" ]]; then
  GNUPGHOME=/root/.gnupg-uconsole-build
  ephemeral_keyring=1
fi
export GNUPGHOME
install -d -m0700 "${GNUPGHOME}"
gpgconf --homedir "${GNUPGHOME}" --kill all 2>/dev/null || true
key_selector=packages@uconsole.local
if ! gpg --homedir "${GNUPGHOME}" --list-secret-keys "${key_selector}" >/dev/null 2>&1; then
  gpg --homedir "${GNUPGHOME}" --batch --generate-key <<'GPG'
%no-protection
Key-Type: EdDSA
Key-Curve: ed25519
Key-Usage: sign
Name-Real: uConsole Image Package Builder
Name-Email: packages@uconsole.local
Expire-Date: 0
%commit
GPG
fi
key="$(gpg --homedir "${GNUPGHOME}" --batch --with-colons --list-secret-keys "${key_selector}" | awk -F: '$1=="fpr" {print $10; exit}')"
[[ -n "${key}" ]]
gpg --homedir "${GNUPGHOME}" --batch --export-secret-keys "${key}" >/dev/null

shopt -s nullglob
packages=()
for package in "${REPO_OUT}"/*.pkg.tar.*; do
  [[ "${package}" == *.sig ]] && continue
  packages+=("${package}")
done
((${#packages[@]} > 0)) || { echo "no packages were built" >&2; exit 1; }
for package in "${packages[@]}"; do
  gpg --homedir "${GNUPGHOME}" --batch --yes --local-user "${key}" --detach-sign "${package}"
done
rm -f "${REPO_OUT}"/uconsole.db* "${REPO_OUT}"/uconsole.files*
repo-add -s -k "${key}" "${REPO_OUT}/uconsole.db.tar.gz" "${packages[@]}"
gpg --homedir "${GNUPGHOME}" --batch --armor --export "${key}" > "${REPO_OUT}/uconsole-repo-key.asc"
printf '%s\n' "${key}" > "${REPO_OUT}/uconsole-repo-key.fingerprint"
if ((ephemeral_keyring)); then
  gpgconf --homedir "${GNUPGHOME}" --kill all 2>/dev/null || true
  rm -rf "${GNUPGHOME}"
fi

echo "Built signed repository: ${REPO_OUT}"
echo "Signing fingerprint: ${key}"
