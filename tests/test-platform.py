#!/usr/bin/env python3
import os
import configparser
import runpy
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
PLATFORM = ROOT / "packages/uconsole-platform/rootfs"


class PlatformTests(unittest.TestCase):
    def test_power_policy_uses_explicit_shutdown_and_limits_pack_current(self):
        config = configparser.ConfigParser()
        config.read(PLATFORM / "etc/UPower/UPower.conf.d/90-uconsole.conf")
        power = config["UPower"]
        self.assertEqual(power["CriticalPowerAction"], "PowerOff")
        self.assertFalse(power.getboolean("AllowRiskyCriticalPowerAction"))
        self.assertTrue(power.getboolean("UsePercentageForPolicy"))
        self.assertEqual([power.getfloat(k) for k in ("PercentageLow", "PercentageCritical", "PercentageAction")], [20, 5, 2])
        rules = (PLATFORM / "usr/lib/udev/rules.d/90-uconsole-charging.rules").read_text()
        self.assertIn('ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="axp20x-battery"', rules)
        self.assertIn('ATTR{constant_charge_current_max}="1500000", ATTR{constant_charge_current}="1500000"', rules)
        self.assertNotIn("voltage_max_design}=", rules)
        initramfs = (PLATFORM / "etc/mkinitcpio.conf.d/zz-uconsole.conf").read_text()
        self.assertIn("FILES+=(/usr/lib/udev/rules.d/90-uconsole-charging.rules)", initramfs)
        hook = (PLATFORM / "usr/share/libalpm/hooks/97-uconsole-power-policy.hook").read_text()
        self.assertIn("Target = upower", hook)
        self.assertIn("Target = uconsole-platform", hook)
        helper = (PLATFORM / "usr/bin/uconsole-apply-power-policy").read_text()
        self.assertIn("--chroot", helper)
        self.assertIn("--sysname-match=axp20x-battery", helper)
        self.assertIn("try-restart upower.service", helper)

    def test_builtin_keyboard_swaps_left_alt_and_super_only(self):
        config = (PLATFORM / "usr/share/uconsole/omarchy/bindings.lua").read_text()
        self.assertIn('hl.device({ name = "clockworkpi-uconsole-keyboard",\n'
                      '            kb_options = "compose:caps,shift:both_capslock_cancel,altwin:swap_lalt_lwin" })', config)
        self.assertEqual(config.count("altwin:swap_lalt_lwin"), 1)
        self.assertIn('name = "uconsole-gamepad-keys", kb_file =', config)

    def test_uconsole_theme_selects_orange_icons(self):
        self.assertEqual((PLATFORM / "usr/share/omarchy/themes/uconsole/icons.theme").read_text().strip(), "Papirus-Dark-Deeporange")
        self.assertIn("papirus-icon-theme", (ROOT / "packages/uconsole-platform/PKGBUILD").read_text())
        self.assertIn("papirus-icon-theme", (ROOT / "scripts/build-packages.sh").read_text())

    def test_papirus_deeporange_preserves_aliases_and_upstream(self):
        helper = runpy.run_path(str(ROOT / "packages/uconsole-platform/build-papirus-theme.py"))
        icons = self.root / "icons"
        for size in (22, 24, 32, 48, 64):
            source = icons / "Papirus" / f"{size}x{size}/places"
            source.mkdir(parents=True)
            for color in ("blue", "deeporange"):
                (source / f"folder-{color}.svg").write_text("svg")
            (source / "folder.svg").symlink_to("folder-blue.svg")
            (source / "inode-directory.svg").symlink_to("folder.svg")
        output = self.root / "theme"
        helper["build"](icons, output)
        self.assertIn("Inherits=Papirus-Dark", (output / "index.theme").read_text())
        for name in ("folder", "inode-directory"):
            self.assertEqual(os.readlink(output / f"48x48/places/{name}.svg"),
                             "/usr/share/icons/Papirus/48x48/places/folder-deeporange.svg")
        self.assertEqual(os.readlink(icons / "Papirus/48x48/places/folder.svg"), "folder-blue.svg")

    def test_gtk_accent_css_validates_and_chooses_readable_text(self):
        helper = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-sync-gtk-theme"))
        css = helper["accent_css"]("#ff6b1a")
        self.assertIn("@define-color theme_selected_bg_color #ff6b1a;", css)
        self.assertIn("@define-color theme_selected_fg_color #000000;", css)
        self.assertIn("accent_fg_color #ffffff;", helper["accent_css"]("#000000"))
        for invalid in ("orange", "#fff", "#123456; * {color:red}", None):
            with self.assertRaises(ValueError):
                helper["accent_css"](invalid)

    def test_gtk_accent_preserves_personal_css_and_is_idempotent(self):
        helper = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-sync-gtk-theme"))
        config = self.root / "config"
        path = config / "gtk-3.0/gtk.css"
        path.parent.mkdir(parents=True)
        personal = "/* My rules */\nbutton { border-radius: 3px; }\n"
        path.write_text(personal)
        for color in ("#ff6b1a", "#abcdef"):
            helper["write_gtk3"](config, helper["accent_css"](color))
        self.assertEqual(path.read_text(), helper["IMPORT"] + "\n" + personal)
        self.assertIn("#abcdef", path.with_name("uconsole-accent.css").read_text())

    def test_appearance_sync_uses_current_theme_and_keeps_dark_and_contrast(self):
        helper = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-sync-gtk-theme"))
        state_dir = self.root / "state"
        theme = state_dir / "omarchy/current/theme/colors.toml"
        theme.parent.mkdir(parents=True)
        theme.write_text('accent = "#ff6b1a"\n')
        calls = []
        main = helper["main"]
        with mock.patch.dict(os.environ, XDG_STATE_HOME=str(state_dir), XDG_CONFIG_HOME=str(self.root / "config")), \
             mock.patch.dict(main.__globals__, get_setting=lambda schema, key: "'prefer-dark'" if key == "color-scheme" else "true",
                             set_setting=lambda *args: calls.append(args)):
            main()
        self.assertEqual(calls, [("org.x.apps.portal", "color-scheme", "'prefer-dark'"),
                                 ("org.x.apps.portal", "high-contrast", "true"),
                                 ("org.x.apps.portal", "accent-rgb", "#ff6b1a")])

    def test_theme_adapter_keeps_accent_sync_after_gnome_preferences(self):
        service = (PLATFORM / "usr/lib/systemd/user/uconsole-theme-sync.service").read_text()
        self.assertIn("ExecStart=/usr/share/omarchy/bin/omarchy-theme-set-gnome", service)
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-configure-omarchy-display"))
        main = module["main"]
        main.__globals__.update(ROOT=self.root / "usr/share/omarchy", BACKUPS=self.root / "backup",
                                RESOURCES=PLATFORM / "usr/share/uconsole/omarchy")
        path = self.root / "usr/share/omarchy/bin/omarchy-theme-set-gnome"
        path.parent.mkdir(parents=True)
        path.write_text('#!/bin/bash\ngsettings set example color-scheme prefer-dark\n# Change gnome icon theme color\n')
        for _ in range(2):
            main()
        self.assertEqual(path.read_text().count("/usr/bin/uconsole-sync-gtk-theme"), 1)
        self.assertLess(path.read_text().index("gsettings set"), path.read_text().index("uconsole-sync-gtk-theme"))

    def test_graphical_boot_console_and_power_dependencies(self):
        template = (PLATFORM / "usr/share/uconsole/boot/cmdline.txt").read_text()
        self.assertEqual(template, (ROOT / "config/boot/cmdline.txt").read_text())
        self.assertIn("plymouth.ignore-serial-consoles", template.split())
        config = (PLATFORM / "etc/mkinitcpio.conf.d/zz-uconsole.conf").read_text()
        result = subprocess.run(["bash", "-c", config + '\nprintf "%s\\n" "${MODULES[@]}"'],
                                text=True, capture_output=True, check=True)
        modules = result.stdout.splitlines()
        for name in ("i2c_bcm2708", "i2c_gpio", "axp20x_i2c", "axp20x_regulator"):
            self.assertLess(modules.index(name), modules.index("panel-cwu50"))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def run_script(self, name):
        script = (PLATFORM / "usr/bin" / name).read_text()
        for prefix in ("/var/lib", "/usr/share", "/usr/local/share"):
            script = script.replace(prefix, str(self.root) + prefix)
        script = script.replace("id alarm >/dev/null", "true")
        script = script.replace("install -d -o sddm -g sddm", "install -d")
        script = script.replace('chown sddm:sddm "${state_file}"', "true")
        return subprocess.run(["bash", "-s"], input=script, text=True, capture_output=True)

    def state(self, text=None):
        state = self.root / "var/lib/sddm/state.conf"
        if text is not None:
            state.parent.mkdir(parents=True, exist_ok=True)
            state.write_text(text)
        return state

    def session(self):
        session = self.root / "usr/share/wayland-sessions/hyprland-uwsm.desktop"
        session.parent.mkdir(parents=True)
        session.touch()
        return session

    def test_first_login_has_a_username(self):
        session = self.session()
        result = self.run_script("uconsole-initialize-login")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("User=alarm\n", self.state().read_text())
        self.assertIn(f"Session={session}\n", self.state().read_text())
        self.assertEqual(self.state().stat().st_mode & 0o777, 0o600)

    def test_existing_login_selection_is_preserved(self):
        original = "[Last]\nUser=another-user\nSession=custom.desktop\n"
        self.state(original)
        self.assertEqual(self.run_script("uconsole-initialize-login").returncode, 0)
        self.assertEqual(self.state().read_text(), original)

    def test_empty_username_is_repaired_with_backup(self):
        self.session()
        original = "[Last]\nUser=\n"
        self.state(original)
        self.assertEqual(self.run_script("uconsole-initialize-login").returncode, 0)
        self.assertIn("User=alarm", self.state().read_text())
        self.assertEqual(Path(str(self.state()) + ".before-uconsole-init").read_text(), original)

    def test_missing_session_is_not_written(self):
        self.assertNotEqual(self.run_script("uconsole-initialize-login").returncode, 0)
        self.assertFalse(self.state().exists())

    def update_script(self, contents):
        script = self.root / "usr/share/omarchy/bin/omarchy-update-system-pkgs"
        script.parent.mkdir(parents=True, exist_ok=True)
        script.write_text(contents)
        return script

    def test_update_adapter_is_idempotent_and_reapplies(self):
        original = "#!/bin/bash\nset -e\necho upstream\n"
        script = self.update_script(original)
        for _ in range(2):
            result = self.run_script("uconsole-configure-omarchy-updates")
            self.assertEqual(result.returncode, 0, result.stderr)
        adapted = script.read_text()
        self.assertEqual(adapted.count("sudo /usr/bin/uconsole-prepare-kernel-update"), 1)
        self.assertLess(adapted.index("uconsole-prepare-kernel-update"), adapted.index("echo upstream"))
        script.write_text(original)
        self.assertEqual(self.run_script("uconsole-configure-omarchy-updates").returncode, 0)
        self.assertEqual(script.read_text(), adapted)

    def test_unknown_upstream_update_script_is_not_overwritten(self):
        original = "#!/bin/bash\nset -euo pipefail\necho changed\n"
        script = self.update_script(original)
        self.assertNotEqual(self.run_script("uconsole-configure-omarchy-updates").returncode, 0)
        self.assertEqual(script.read_text(), original)

    def test_module_recipe_can_target_an_uninstalled_kernel(self):
        env = dict(os.environ, UCONSOLE_KERNEL_PACKAGE_VERSION="6.18.50-1",
                   UCONSOLE_KERNEL_RELEASE="6.18.50-1-rpi",
                   UCONSOLE_KERNEL_BUILD_DIR=str(self.root / "headers"))
        recipe = ROOT / "packages/uconsole-modules-linux-rpi/PKGBUILD"
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; printf "%s\\n" "$pkgver" "$pkgrel" "${depends[0]}" "$_kver" "$_build_dir"', "bash", str(recipe)],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["6.18.50", "1.1", "linux-rpi=6.18.50-1",
                                                     "6.18.50-1-rpi", str(self.root / "headers")])

    def prepare_with_fake_packages(self, installed="6.18.48-1", headers="6.18.50-1"):
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        call_log = self.root / "pacman-calls"
        fake_pacman = binary_dir / "pacman"
        fake_pacman.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_CALL_LOG"
case "$*" in
  '-Si linux-rpi') echo 'Version : 6.18.50-1' ;;
  '-Si linux-rpi-headers') echo "Version : $TEST_HEADERS" ;;
  '-Q linux-rpi') echo "linux-rpi $TEST_INSTALLED" ;;
  '-Si uconsole-modules-linux-rpi') echo 'Depends On : linux-rpi=6.18.48-1' ;;
  '-Spdd --print-format %f linux-rpi') echo 'linux-rpi.pkg.tar.xz' ;;
  '-Spdd --print-format %f linux-rpi-headers') echo 'headers.pkg.tar.xz' ;;
  '-Swdd '*) echo 'simulated signature/download failure' >&2; exit 1 ;;
  *) exit 99 ;;
esac
''')
        fake_pacman.chmod(0o755)
        for command in ("pacman-conf", "flock", "makepkg", "gcc", "make", "bsdtar", "zstd", "modinfo", "gpg", "repo-add"):
            fake_command = binary_dir / command
            output = 'printf "%s\\n" "$TEST_REPO"' if command == "pacman-conf" else "exit 0"
            fake_command.write_text("#!/bin/bash\n" + output + "\n")
            fake_command.chmod(0o755)
        script = (PLATFORM / "usr/bin/uconsole-prepare-kernel-update").read_text()
        script = script.replace('[[ ${EUID} -eq 0 ]]', 'true')
        for prefix in ("/run/lock", "/var/cache", "/var/lib"):
            script = script.replace(prefix, str(self.root) + prefix)
        (self.root / "run/lock").mkdir(parents=True)
        env = dict(os.environ, PATH=str(binary_dir) + os.pathsep + os.environ["PATH"],
                   TEST_CALL_LOG=str(call_log), TEST_HEADERS=headers,
                   TEST_INSTALLED=installed, TEST_REPO="file://" + str(self.root / "var/cache/uconsole/repo"))
        result = subprocess.run(["bash", "-s"], input=script, env=env, text=True, capture_output=True)
        return result, call_log.read_text()

    def test_current_kernel_does_not_build_or_install(self):
        result, calls = self.prepare_with_fake_packages(installed="6.18.50-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("-Sw", calls)
        self.assertFalse((self.root / "var/cache/uconsole/build").exists())

    def test_mismatched_headers_stop_before_download(self):
        result, calls = self.prepare_with_fake_packages(headers="6.18.49-1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("out of sync", result.stderr)
        self.assertNotIn("-Sw", calls)

    def test_failed_download_never_installs_or_publishes(self):
        result, calls = self.prepare_with_fake_packages()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated signature/download failure", result.stderr)
        self.assertNotIn("-Syu", calls)
        self.assertNotIn("-U ", calls)
        self.assertFalse((self.root / "var/cache/uconsole/repo").exists())
        self.assertFalse((self.root / "var/lib/uconsole/package-signing").exists())

    def test_small_screen_adaptations_are_idempotent(self):
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-configure-omarchy-display"))
        main = module["main"]
        main.__globals__["ROOT"] = self.root
        main.__globals__["BACKUPS"] = self.root / "backups"
        picker = self.root / "shell/plugins/image-picker/ImagePicker.qml"
        picker.parent.mkdir(parents=True)
        picker.write_text("\n".join([
            "property int expandedWidth: 768", "property int expandedHeight: 475",
            "property int sliceHeight: 432",
            "width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)",
            "clip: false",
        ]))
        saver = self.root / "default/foot/screensaver.ini"
        saver.parent.mkdir(parents=True)
        saver.write_text("font=JetBrainsMono Nerd Font:size=18\n")
        main()
        first = picker.read_text()
        main()
        self.assertEqual(picker.read_text(), first)
        self.assertIn("panel.width - 64", first)
        self.assertIn("panel.height -", first)
        self.assertIn("size=10", saver.read_text())
        self.assertIn("size=18", (self.root / "backups/default/foot/screensaver.ini").read_text())

    def test_unknown_picker_is_preserved(self):
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-configure-omarchy-display"))
        path = self.root / "changed.qml"
        path.write_text("new upstream layout\n")
        with self.assertRaises(RuntimeError):
            module["adapt"](path, [("property int expandedWidth: 768", "replacement")])
        self.assertEqual(path.read_text(), "new upstream layout\n")

    def test_audio_plugins_are_explicit_image_packages(self):
        packages = (ROOT / "config/omarchy/packages.txt").read_text().splitlines()
        for name in ("pipewire-audio", "pipewire-alsa", "pipewire-pulse", "wireplumber", "rtkit"):
            self.assertIn(name, packages)

    def test_rotated_width_uses_landscape_axis_and_reservations(self):
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-window"))
        monitor = {"width": 720, "height": 1280, "scale": 1.6,
                   "transform": 3, "reserved": [5, 26, 5, 0]}
        self.assertEqual(module["logical_width"](monitor), 790)
        monitor["transform"] = 0
        self.assertEqual(module["logical_width"](monitor), 440)

    def test_dim_restore_is_idempotent_and_preserves_manual_changes(self):
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-idle-backlight"))
        brightness = self.root / "brightness"
        brightness.write_text("6")
        (self.root / "max_brightness").write_text("9")
        state = self.root / "saved"
        update = module["update"]
        update("dim", self.root, state)
        update("dim", self.root, state)
        self.assertEqual(brightness.read_text(), "1")
        self.assertEqual(state.read_text(), "6")
        update("restore", self.root, state)
        self.assertEqual(brightness.read_text(), "6")
        self.assertFalse(state.exists())
        update("dim", self.root, state)
        brightness.write_text("4")
        update("restore", self.root, state)
        self.assertEqual(brightness.read_text(), "4")
        brightness.write_text("0")
        update("dim", self.root, state)
        self.assertEqual(brightness.read_text(), "0")
        self.assertFalse(state.exists())

    def test_native_idle_and_shortcut_adapters_are_idempotent(self):
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-configure-omarchy-display"))
        main = module["main"]
        main.__globals__.update(ROOT=self.root, BACKUPS=self.root / "backup",
                                RESOURCES=PLATFORM / "usr/share/uconsole/omarchy")
        idle = self.root / "shell/plugins/services/idle/Service.qml"
        idle.parent.mkdir(parents=True)
        idle.write_text("Item {\n  id: root\n}\n")
        browser = self.root / "bin/omarchy-menu-keybindings"
        browser.parent.mkdir()
        browser.write_text('  dsp = dsp_proxy("hl.dsp"),\n')
        main()
        first = idle.read_text()
        main()
        self.assertEqual(idle.read_text(), first)
        self.assertEqual(first.count("id: uconsoleDimMonitor"), 1)
        self.assertIn("respectInhibitors: true", first)
        self.assertIn("define_submap = function", browser.read_text())

    def test_scratchpad_round_trip_only_hides_a_visible_special_workspace(self):
        module = runpy.run_path(str(PLATFORM / "usr/bin/uconsole-window"))
        scratchpad = module["scratchpad"]
        calls = []
        window = {"monitor": 0, "workspace": {"name": "1"}}
        monitor = {"id": 0, "activeWorkspace": {"id": 1}, "specialWorkspace": {"name": ""}}
        scratchpad.__globals__["query"] = lambda name: window if name == "activewindow" else [monitor]
        scratchpad.__globals__["dispatch"] = calls.append
        scratchpad()
        self.assertEqual(calls, ['hl.dsp.window.move({workspace="special:scratchpad", follow=false})'])
        window["workspace"]["name"] = "special:scratchpad"
        monitor["specialWorkspace"]["name"] = "special:scratchpad"
        calls.clear()
        scratchpad()
        self.assertEqual(calls[0], 'hl.dsp.window.move({workspace="1", follow=false})')
        self.assertEqual(calls[1], 'hl.dsp.workspace.toggle_special("scratchpad")')

    def test_handheld_defaults_do_not_replace_omarchy(self):
        config = (PLATFORM / "usr/share/uconsole/omarchy/bindings.lua").read_text()
        self.assertIn("omarchy-menu toggle apps", config)
        self.assertIn("omarchy-menu-keybindings", config)
        self.assertIn("uconsole-window width", config)
        self.assertIn("Hold ", config)
        self.assertIn("kb_file =", config)
        self.assertIn('hl.bind("F16"', config)
        self.assertNotIn('"code:', config)
        self.assertNotIn('", "reset", function()', config)
        self.assertIn('submap_universal = true, transparent = true', config)
        self.assertFalse((PLATFORM / "etc/chrony.conf.d/uconsole.conf").exists())
        video = (PLATFORM / "usr/share/uconsole/mpv/hwdec.lua").read_text()
        self.assertIn("brcm,bcm2711", video)
        self.assertIn("if cm4 and decoder then", video)
        self.assertIn('"hwdec-codecs", "h264"', video)


if __name__ == "__main__":
    unittest.main()
