-- The built-in keyboard firmware emits Left Super for Fn+Left Alt.
-- Swap those two keys so window-manager shortcuts do not require Fn.
-- Keep Omarchy's Compose/Caps defaults; do not change external keyboards.
hl.device({ name = "clockworkpi-uconsole-keyboard",
            kb_options = "compose:caps,shift:both_capslock_cancel,altwin:swap_lalt_lwin" })

-- Face buttons are mirrored to evdev F13-F16 by uconsole-gamepad-keys.
-- Explicit symbols avoid Hyprland's Lua code:N/NoSymbol matching bug.
hl.device({ name = "uconsole-gamepad-keys", kb_file = "/usr/share/uconsole/xkb/gamepad.xkb",
            resolve_binds_by_sym = true })
-- Capture release in every submap, including the default map where the press
-- originated. Register before mode-entry binds so the release is tracked.
for _, key in ipairs({ "F13", "F14", "F15", "F16" }) do
  hl.bind(key, hl.dsp.submap("reset"), { release = true, submap_universal = true, transparent = true })
end
local function leave_mode()
  hl.bind("ESCAPE", hl.dsp.submap("reset"), { description = "Exit held-button mode" })
end

-- Descriptions are consumed directly by Omarchy's live keybinding browser.
-- Include the held button because its normal key column only shows the chord
-- inside a submap, not the physical button that enters that submap.
local raw_bind = hl.bind
local held_button = nil
local function bind(key, action, options)
  options = options or {}
  if held_button and options.description then
    options.description = "Hold " .. held_button .. ": " .. options.description
  end
  return raw_bind(key, action, options)
end

hl.bind("F16", hl.dsp.submap("uconsole-focus"), { description = "A: focus mode" })
hl.define_submap("uconsole-focus", function()
  held_button = "A"
  leave_mode("F16")
  bind("LEFT", hl.dsp.focus({ direction = "l" }), { repeating = true, description = "Focus left" })
  bind("RIGHT", hl.dsp.focus({ direction = "r" }), { repeating = true, description = "Focus right" })
  bind("UP", hl.dsp.focus({ direction = "u" }), { repeating = true, description = "Focus up" })
  bind("DOWN", hl.dsp.focus({ direction = "d" }), { repeating = true, description = "Focus down" })
  held_button = nil
end)

hl.bind("F15", hl.dsp.submap("uconsole-move"), { description = "B: move mode" })
hl.define_submap("uconsole-move", function()
  held_button = "B"
  leave_mode("F15")
  bind("LEFT", hl.dsp.window.swap({ direction = "l" }), { repeating = true, description = "Move window left" })
  bind("RIGHT", hl.dsp.window.swap({ direction = "r" }), { repeating = true, description = "Move window right" })
  bind("UP", hl.dsp.window.swap({ direction = "u" }), { repeating = true, description = "Move window up" })
  bind("DOWN", hl.dsp.window.swap({ direction = "d" }), { repeating = true, description = "Move window down" })
  for n = 1, 6 do
    bind(tostring(n), hl.dsp.window.move({ workspace = tostring(n) }),
      { description = "Move window to workspace " .. n })
  end
  held_button = nil
end)

hl.bind("F14", hl.dsp.submap("uconsole-go"), { description = "X: workspace mode" })
hl.define_submap("uconsole-go", function()
  held_button = "X"
  leave_mode("F14")
  bind("LEFT", hl.dsp.focus({ workspace = "e-1" }), { repeating = true, description = "Previous workspace" })
  bind("RIGHT", hl.dsp.focus({ workspace = "e+1" }), { repeating = true, description = "Next workspace" })
  bind("UP", hl.dsp.workspace.toggle_special("scratchpad"), { description = "Show or hide scratchpad" })
  bind("DOWN", hl.dsp.exec_cmd("uconsole-window scratchpad"), { description = "Stash or retrieve focused window" })
  for n = 1, 6 do
    bind(tostring(n), hl.dsp.focus({ workspace = tostring(n) }),
      { description = "Switch to workspace " .. n })
  end
  held_button = nil
end)

hl.bind("F13", hl.dsp.submap("uconsole-size"), { description = "Y: size mode" })
hl.define_submap("uconsole-size", function()
  held_button = "Y"
  leave_mode("F13")
  bind("LEFT", hl.dsp.layout("colresize -0.1"), { repeating = true, description = "Narrower column" })
  bind("RIGHT", hl.dsp.layout("colresize +0.1"), { repeating = true, description = "Wider column" })
  bind("UP", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Toggle fullscreen" })
  bind("DOWN", hl.dsp.layout("fit visible"), { description = "Fit visible columns" })
  for n = 1, 9 do
    bind(tostring(n), hl.dsp.exec_cmd("uconsole-window width " .. n),
      { description = "Set column width to " .. n * 10 .. "%" })
  end
  held_button = nil
end)
held_button = nil

-- Reach Omarchy's own launchers and help without hunting for a Super key.
bind("ALT + SPACE", hl.dsp.exec_cmd("omarchy-menu toggle apps"), { description = "Application launcher" })
bind("CTRL + ALT + RETURN", hl.dsp.exec_cmd("omarchy-launch-terminal"), { description = "Terminal" })
bind("CTRL + ALT + H", hl.dsp.exec_cmd("omarchy-menu-keybindings"), { description = "Keyboard shortcuts" })
