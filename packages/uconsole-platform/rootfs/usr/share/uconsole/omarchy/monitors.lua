-- uConsole panel: portrait-native 720x1280, rotated to 1280x720 landscape.
hl.monitor({ output = "DSI-1", mode = "preferred", position = "0x0", scale = 1.6, transform = 3 })
-- Preserve Omarchy's useful behavior for an attached external display.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.env("GDK_SCALE", "2")
