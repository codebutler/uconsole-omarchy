-- Omarchy edits its named scale variables, then Hyprland reloads this file.
local path = "packages/uconsole-platform/rootfs/usr/share/uconsole/omarchy/monitors.lua"
local file = assert(io.open(path))
local template = file:read("*a")
file:close()

local function evaluate(source, expected, gdk)
  local monitors, env = {}, {}
  local context = {
    tostring = tostring,
    hl = {
      monitor = function(rule) monitors[#monitors + 1] = rule end,
      env = function(key, value) env[key] = value end,
    },
  }
  assert(load(source, path, "t", context))()
  assert(monitors[1].output == "DSI-1")
  assert(monitors[1].scale == expected, "panel scale must follow Omarchy's saved value")
  assert(monitors[1].transform == 3, "rotation must survive scale changes")
  assert(monitors[2].output == "" and monitors[2].scale == "auto")
  assert(env.GDK_SCALE == tostring(gdk))
end

evaluate(template, 1.6, 2)
for _, scale in ipairs({ 1, 1.25, 1.6, 2 }) do
  local gdk = math.floor(scale + 0.5)
  local source, count = template:gsub("local omarchy_monitor_scale = [^\n]+", "local omarchy_monitor_scale = " .. scale)
  assert(count == 1)
  source, count = source:gsub("local omarchy_gdk_scale = [^\n]+", "local omarchy_gdk_scale = " .. gdk)
  assert(count == 1)
  evaluate(source, scale, gdk)
  evaluate(source, scale, gdk) -- A second reload must not restore the default.
end
print("monitor scale persistence: 5 cases passed")
