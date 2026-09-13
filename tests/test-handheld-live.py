#!/usr/bin/env python3
"""Explicit device test: inject face-key chords; use only our own test windows.

Run as root with the graphical user's XDG_RUNTIME_DIR and
HYPRLAND_INSTANCE_SIGNATURE preserved. Never run against a locked session.
"""
import argparse
import json
import os
import subprocess
import time
from evdev import UInput, ecodes


def ctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True).strip()


def state(name):
    return json.loads(ctl("-j", name))


def dispatch(expression):
    result = ctl("dispatch", expression)
    assert result == "ok", result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.parse_args()
    assert os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    locked = subprocess.check_output(["runuser", "-u", "alarm", "--", "env",
        "XDG_RUNTIME_DIR=" + os.environ["XDG_RUNTIME_DIR"],
        "OMARCHY_PATH=/usr/share/omarchy", "omarchy-shell", "lock", "isLocked"], text=True).strip()
    assert locked == "false", "Unlock the device before testing"
    keys = [ecodes.KEY_F13, ecodes.KEY_F14, ecodes.KEY_F15, ecodes.KEY_F16,
            ecodes.KEY_3, ecodes.KEY_5, ecodes.KEY_7, ecodes.KEY_UP, ecodes.KEY_DOWN]
    # Hyprland suffixes duplicate device names. Give the test device its own
    # matching keymap rule rather than silently testing a different US keymap.
    ctl("eval", 'hl.device({name="uconsole-validation-keyboard", kb_file="/usr/share/uconsole/xkb/gamepad.xkb", resolve_binds_by_sym=true})')
    faces = keys[:4]
    ui = UInput({ecodes.EV_KEY: faces}, name="uconsole-validation-keyboard")
    keyboard = UInput({ecodes.EV_KEY: keys[4:]}, name="uconsole-validation-dpad")
    time.sleep(1)
    def key(code, value):
        device = ui if code in faces else keyboard
        device.write(ecodes.EV_KEY, code, value)
        device.syn()
        time.sleep(0.15)
    def chord(face, arrow):
        key(face, 1)
        key(arrow, 1)
        key(arrow, 0)
        key(face, 0)
        time.sleep(1)
    old = state("activewindow")
    owned = []
    try:
        for code, mode in [(ecodes.KEY_F16, "focus"), (ecodes.KEY_F15, "move"),
                           (ecodes.KEY_F14, "go"), (ecodes.KEY_F13, "size")]:
            key(code, 1)
            assert ctl("submap") == "uconsole-" + mode, ctl("submap")
            key(code, 0)
            assert ctl("submap") in ("default", "reset"), ctl("submap")
            print("PASS held/released", mode, flush=True)
        for n in range(2):
            dispatch('hl.dsp.exec_cmd("foot --app-id=uconsole-validation sh -c \'sleep 180\'")')
            time.sleep(2)
        owned = [w["address"] for w in state("clients") if w["class"] == "uconsole-validation"]
        assert len(owned) == 2, owned
        address = owned[-1]
        dispatch('hl.dsp.focus({window="address:' + address + '"})')
        time.sleep(0.5)
        key(ecodes.KEY_F13, 1)
        for number, code in [(3, ecodes.KEY_3), (7, ecodes.KEY_7), (5, ecodes.KEY_5)]:
            key(code, 1)
            key(code, 0)
            time.sleep(1)
            assert ctl("submap") == "uconsole-size", "Mode exited before Y was released"
            window = state("activewindow")
            assert window.get("address") == address, "Focus changed during test"
            monitor = next(m for m in state("monitors") if m["id"] == window["monitor"])
            axis = "height" if monitor["transform"] % 2 else "width"
            width = monitor[axis] / monitor["scale"] - monitor["reserved"][0] - monitor["reserved"][2]
            ratio = window["size"][0] / width
            assert abs(ratio - number / 10) < 0.025, (number, ratio)
            print("PASS Y+", number, "width", ratio, flush=True)
        key(ecodes.KEY_F13, 0)
        assert ctl("submap") in ("default", "reset"), "Mode stuck after releasing Y"
        print("PASS multiple actions during one hold; release exits", flush=True)
        original_workspace = state("activewindow")["workspace"]["id"]
        chord(ecodes.KEY_F14, ecodes.KEY_DOWN)
        window = next(w for w in state("clients") if w["address"] == address)
        assert window["workspace"]["name"] == "special:scratchpad"
        chord(ecodes.KEY_F14, ecodes.KEY_UP)
        assert state("activewindow").get("address") == address, "Scratchpad did not reveal/focus"
        chord(ecodes.KEY_F14, ecodes.KEY_DOWN)
        window = next(w for w in state("clients") if w["address"] == address)
        assert window["workspace"]["id"] == original_workspace, window
        print("PASS X+Down stash, X+Up reveal, X+Down retrieve", flush=True)
    finally:
        for code in keys:
            device = ui if code in faces else keyboard
            device.write(ecodes.EV_KEY, code, 0)
        ui.syn()
        keyboard.syn()
        ui.close()
        keyboard.close()
        dispatch('hl.dsp.submap("reset")')
        # Re-read so a failure during creation still cleans up only our windows.
        for window in state("clients"):
            if window["class"] == "uconsole-validation":
                dispatch('hl.dsp.window.close({window="address:' + window["address"] + '"})')
        if old.get("address") and any(w["address"] == old["address"] for w in state("clients")):
            dispatch('hl.dsp.focus({window="address:' + old["address"] + '"})')


if __name__ == "__main__":
    main()
