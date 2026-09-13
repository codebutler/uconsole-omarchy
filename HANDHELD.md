# uConsole additions to Omarchy

The desktop, app launcher, status panels, Tailscale/Taildrop, lock screen,
screensaver, theme picker and shortcut browser remain upstream Omarchy.
The platform package supplies only hardware and small-screen integrations.

## Controls

Hold a face button, then press the D-pad or a number. Releasing the button
returns to normal keyboard input; Escape also leaves the mode.
Several actions can be performed during one continuous hold. The submaps
must not use Hyprland's optional reset-after-action argument; universal,
transparent release bindings end the mode when the face button is released.

| Hold | Left / right | Up / down | Numbers |
|---|---|---|---|
| A | Focus windows | Focus windows | — |
| B | Swap windows | Swap windows | 1–6: move window to workspace |
| X | Previous / next workspace | Show/hide scratchpad; stash/retrieve focused window | 1–6: switch workspace |
| Y | Narrower / wider column | Fullscreen; fit visible columns | 1–9: column width 10–90% |

Y+3 means **30%**, not exactly one third. Width calculations account for the
panel's rotation, fractional scale and reserved bar space. Floating/fullscreen
windows are not resized by the column helper.

Alt+Space opens Omarchy's Apps menu. Ctrl+Alt+Return opens a terminal.
On the built-in keyboard, **Left Alt acts as Super**, and **Fn+Left Alt acts
as Alt**. This is a Hyprland device-specific XKB swap; external keyboards,
the text console and login screen are unchanged. Omarchy's Compose/Caps
defaults are retained. Thus Left Alt+W closes a window, and Left Alt+Return
opens a terminal. For Alt shortcuts use Fn+Left Alt (or Right Alt).

Ctrl+Alt+H opens the **existing Omarchy keybinding browser**. Its list comes
from live bindings and descriptions, including the held face-button context.
The source scanner is adapted to visit submaps, allowing numeric keycodes to
be shown as readable keys. No separate hardcoded cheatsheet is maintained.

The USB joystick exposes Y=291, X=288, B=290, A=289. The remapper mirrors those
as F13–F16 respectively. A keymap scoped to the virtual gamepad keyboard gives
these real F13–F16 symbols; this avoids Hyprland's Lua `code:N` matching bug
for unnamed keys. L/R mouse buttons and
the D-pad are not remapped. The joystick is not exclusively grabbed: games
can still see the original buttons, alongside the desktop shortcuts.

## Appearance and idle behavior

`uconsole` is a native Omarchy dark theme: neutral panels, squared corners,
and keyboard-orange `#ff6b1a` accents. It is selected by default during image
provisioning, but package upgrades do not reset a user's later theme choice.
Switch using the normal theme picker or `omarchy-theme-set uconsole`.
The package generates its wallpaper PNG from the checked-in SVG.
Its `icons.theme` selects `Papirus-Dark-Deeporange`: Papirus Dark with its
deeporange folder artwork. The platform package supplies an inherited theme
of links (including folder aliases), without modifying Papirus-owned files.
Papirus upgrades therefore preserve the choice. Other icons inherit Papirus Dark.

GTK accents follow `accent` in the current Omarchy theme's `colors.toml`.
The packaged XApp Settings backend publishes that RGB value to libadwaita
and sandboxed apps; Hyprland still handles screenshots/screen sharing and GTK
still handles file selection. The other GTK settings namespaces remain available.
`uconsole-sync-gtk-theme` runs at graphical login and after Omarchy's GNOME
theme preferences are applied. It copies dark/light and high-contrast preferences
to XApp and imports generated named colors into GTK3's `gtk.css`, preserving
later personal rules. No GTK4 CSS override is installed: libadwaita maps the
portal color to its supported accent palette, so its orange shade can differ
from the shell's exact `#ff6b1a`. Already-running GTK3 apps may need reopening.
Run `uconsole-sync-gtk-theme` to reapply manually after changing preferences.

Omarchy's native idle service dims the backlight after 120 seconds and
restores the previous level on activity. It respects idle inhibitors and
Omarchy's stay-awake toggle. Existing screensaver, lock and display-off
timings remain under Omarchy's control. This is **not suspend**.
The brightness helper serializes updates, does not wake a manually darkened
panel, and preserves manual brightness changes made while dimmed.

### Battery policy

The `90-uconsole-charging.rules` udev rule sets total charge current and its
driver ceiling to **1.5 A** on battery-device add, including boot. This is below
the Samsung INR18650-35E's 1.7 A standard and 2.0 A maximum per-cell charging
rates even if only one cell is connected. It does not certify cell condition,
current accuracy, temperature protection, or charging while powered off.
No charging-voltage setting is changed. Other cells require their own review.
Source: [Samsung SDI 35E specification](https://www.bto.pl/pdf/08097/INR18650-35E.pdf).

UPower's package-owned `90-uconsole.conf` drop-in selects **PowerOff**, with
percentage thresholds 20% low / 5% critical / 2% action. UPower 1.91.4's `Auto`
otherwise falls through from unavailable Sleep to Ignore on this machine.
The package hook reapplies the current limit and reloads an active UPower daemon
after upgrades; first-boot images pick up both configurations automatically.
The percentage gauge is not a calibrated per-cell measurement. Graceful
shutdown is not a hardware undervoltage cutoff or a guarantee against drain
while powered off. Do not intentionally exhaust cells to test this policy.

The recovery console uses Terminus `ter-128n`; other vconsole settings are
preserved. Its font is included in the initramfs.

Plymouth keeps Omarchy's upstream graphical theme. The boot command line
includes `plymouth.ignore-serial-consoles`: without it, `console=tty3` is
treated as a non-default console and forces Plymouth's details/text path.
The initramfs also includes both models' PMIC I2C buses and AXP regulator
drivers, so the panel's power supply is available before switching root.

## Video

The user mpv configuration includes platform defaults before user overrides.
On BCM2711/CM4, when `bcm2835-codec-decode` is exposed, H.264 uses
`v4l2m2m-copy`. Other codecs are not forced through that decoder. On CM5 (or
without that driver), mpv retains `auto-safe`, including software fallback.
CM5 HEVC acceleration requires its separate stateless decode userspace path;
the CM4 test is not evidence that this works on CM5.

Internet video selection prefers H.264 at up to 720p. This configures mpv,
not browser hardware decoding. User/command-line explicit hwdec choices win.

## Networking and time

Chrony uses its package's active `/etc/chrony.conf`. The unused uConsole
drop-in was removed; no extra NTP service runs alongside it.

Check Wi-Fi country with `iw reg get`. Choose the regulatory country for the
device's actual location; firmware may also report its own per-PHY domain.
The image contains no SSID, password or network-specific band lock.

If desired, clone your own NetworkManager Wi-Fi profile, set the clone's
`802-11-wireless.band` to `a`, and give it a higher `connection.autoconnect-priority`.
Keep the original unpinned profile as fallback. This affects future connection
selection; do not force a reconnect over SSH without a recovery path. A
5GHz preference is deliberately opt-in because coverage varies by location.

## Maintenance and verification

`uconsole-platform` owns the helpers, theme and config templates. Its existing
post-transaction Omarchy adapter preserves upstream backups, validates patch
anchors and reapplies after Omarchy updates. Unknown upstream changes stop
with an error instead of silently applying a guessed patch.

`tests/test-static.sh` tests platform behavior and adaptation idempotency.
`tests/test-handheld-live.py --run` explicitly creates two temporary test
terminals, injects hold/release chords and checks resizing/scratchpad round trips.
Face buttons and number keys are injected from separate devices, including
three number presses during one continuous Y hold and a release-state check.
It refuses a locked session and cleans up only its own windows.
Physical button labeling and CM5 behavior still require the respective hardware.
