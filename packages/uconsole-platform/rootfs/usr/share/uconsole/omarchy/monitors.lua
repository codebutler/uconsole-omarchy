-- uConsole panel: portrait-native 720x1280, rotated to 1280x720 landscape.
-- Omarchy's monitor controls persist changes through these named variables.
local omarchy_monitor_scale = 1.6
local omarchy_gdk_scale = 2
hl.monitor({ output = "DSI-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale, transform = 3 })
-- Preserve Omarchy's useful behavior for an attached external display.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
