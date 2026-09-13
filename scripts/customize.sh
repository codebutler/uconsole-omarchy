#!/usr/bin/env bash
# Customize an extracted Arch Linux ARM root into a universal Omarchy uConsole.
set -euo pipefail

UC_HOSTNAME="${UC_HOSTNAME:-uconsole}"
TIMEZONE="${TIMEZONE:-America/New_York}"
LOCALE="${LOCALE:-en_US.UTF-8}"
ROOT_PARTUUID="${ROOT_PARTUUID:?ROOT_PARTUUID is required}"
SOURCE_ROOT="${SOURCE_ROOT:-/root/uconsole-source}"
LOCAL_REPO="${LOCAL_REPO:-/var/cache/uconsole/repo}"
OMARCHY_REPO="${OMARCHY_REPO:-https://pkgs.omarchy.org/edge/aarch64}"
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
PAC=(pacman --disable-sandbox)

log() { printf '\n==> [image] %s\n' "$*"; }

log "Initialize Arch Linux ARM signing keys"
pacman-key --init
pacman-key --populate archlinuxarm
"${PAC[@]}" -Sy --noconfirm --needed archlinuxarm-keyring archlinux-keyring

log "Trust the official Omarchy package signing key"
pacman-key --recv-keys "${OMARCHY_KEY}" --keyserver hkps://keys.openpgp.org
pacman-key --lsign-key "${OMARCHY_KEY}"
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
  # Omarchy rebuilds a small set of Arch packages as an ABI-matched unit.  Its
  # repository must precede [extra], otherwise pacman selects ALARM's package
  # with the same name even when Omarchy's Hyprland stack is newer.
  sed -i "/^\[core\]/i\\
[omarchy]\\
SigLevel = Required DatabaseOptional\\
Server = ${OMARCHY_REPO}\\
" /etc/pacman.conf
fi

log "Trust and enable the image's signed uConsole package repository"
repo_key="${LOCAL_REPO}/uconsole-repo-key.asc"
repo_fpr="$(cat "${LOCAL_REPO}/uconsole-repo-key.fingerprint")"
pacman-key --add "${repo_key}"
pacman-key --lsign-key "${repo_fpr}"
if ! grep -q '^\[uconsole\]' /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<EOF

[uconsole]
SigLevel = Required DatabaseRequired
Server = file://${LOCAL_REPO}
EOF
fi

log "Replace the generic ALARM boot stack with package-managed linux-rpi"
for pkg in linux-aarch64 uboot-raspberrypi; do
  if pacman -Qq "${pkg}" >/dev/null 2>&1; then
    "${PAC[@]}" -Rdd --noconfirm "${pkg}"
  fi
done

log "Install full Omarchy package set and the 4K Raspberry Pi kernel"
mapfile -t packages < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
  "${SOURCE_ROOT}/config/omarchy/packages.txt")
"${PAC[@]}" -Syu --noconfirm
"${PAC[@]}" -S --needed --noconfirm omarchy-keyring omarchy "${packages[@]}"

log "Install uConsole hardware packages"
# Package filenames are intentionally stable across identical builds, while an
# image-local signing key is generated for each build.  Never reuse a package
# cached from an earlier build/key pair.
rm -f /var/cache/pacman/pkg/uconsole-*.pkg.tar.*
"${PAC[@]}" -S --needed --noconfirm \
  uconsole-modules-linux-rpi uconsole-platform uconsole-aiov2-ctl

log "Configure locale, clock, hostname, and the initial user"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
escaped_locale="${LOCALE//./\.}"
sed -i "s/^#[[:space:]]*\(${escaped_locale}[[:space:]]\)/\1/" /etc/locale.gen
grep -q "^${LOCALE}[[:space:]]" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "${LOCALE}" > /etc/locale.conf
printf 'LANG=%s\n' "${LOCALE}" > /etc/environment
printf '%s\n' "${UC_HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${UC_HOSTNAME}.localdomain ${UC_HOSTNAME}
EOF
install -d /var/log/journal /var/lib/uconsole
: > /var/lib/uconsole/resize-rootfs.pending

id alarm >/dev/null 2>&1 || useradd -m -G wheel,video,input,audio -s /bin/bash alarm
usermod -aG wheel,video,input,audio alarm
install -Dm0440 /dev/stdin /etc/sudoers.d/10-alarm <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

log "Provision Omarchy's per-user configuration"
cp -a -n /etc/skel/. /home/alarm/
chown -R alarm:alarm /home/alarm
if command -v omarchy-provision-user >/dev/null; then
  runuser -u alarm -- env HOME=/home/alarm USER=alarm \
    OMARCHY_SETUP_CONTEXT=provision-owner omarchy-provision-user --first-install
fi
install -Dm0644 /usr/share/uconsole/omarchy/monitors.lua /home/alarm/.config/hypr/monitors.lua
install -Dm0644 /usr/share/uconsole/omarchy/looknfeel.lua /home/alarm/.config/hypr/looknfeel.lua
install -Dm0644 /usr/share/uconsole/omarchy/bindings-loader.lua /home/alarm/.config/hypr/bindings.lua
chown -R alarm:alarm /home/alarm/.config
uconsole-initialize-login
uconsole-configure-omarchy-updates
uconsole-configure-omarchy-display
runuser -u alarm -- env HOME=/home/alarm USER=alarm OMARCHY_PATH=/usr/share/omarchy \
  OMARCHY_THEME_HEADLESS=1 uconsole-configure-handheld-user --theme

log "Select the safe platform services"
systemctl disable systemd-networkd.service systemd-networkd.socket \
  systemd-networkd-wait-online.service systemd-timesyncd.service 2>/dev/null || true
systemctl mask systemd-networkd.service systemd-networkd.socket \
  systemd-networkd-wait-online.service systemd-timesyncd.service
systemctl enable NetworkManager.service NetworkManager-wait-online.service chronyd.service
systemctl enable bluetooth.service cups.service avahi-daemon.service systemd-resolved.service
systemctl enable sddm.service tailscaled.service
systemctl enable uconsole-initialize-login.service
systemctl enable uconsole-resize-rootfs.service uconsole-speaker-amp.service \
  uconsole-wifi-watchdog.timer uconsole-gamepad-keys.service
systemctl enable aiov2-rails-boot.service
systemctl set-default graphical.target
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

log "Install universal boot configuration and regenerate the initramfs"
uconsole-install-boot-config "${ROOT_PARTUUID}"
mkinitcpio -P

log "Remove build-only packages and machine-specific state"
"${PAC[@]}" -Rns --noconfirm linux-rpi-headers 2>/dev/null || true
# dtc remains installed because raspberrypi-utils uses it at runtime.
"${PAC[@]}" -Sc --noconfirm
rm -rf /var/lib/NetworkManager/* /var/lib/tailscale/* /etc/ssh/ssh_host_* \
  /var/lib/systemd/random-seed /root/.cache /home/alarm/.cache
rm -f /etc/machine-id
: > /etc/machine-id
find /root /home/alarm -maxdepth 2 -type f -name '*history*' -delete 2>/dev/null || true

log "Customization complete"
