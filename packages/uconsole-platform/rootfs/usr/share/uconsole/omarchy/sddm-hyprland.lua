hl.monitor({ output = "DSI-1", mode = "preferred", position = "0x0", scale = 1.6, transform = 3 })
hl.config({
  -- The Qt greeter is native Wayland; no X server is needed here.
  xwayland = { enabled = false },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },
  animations = { enabled = false },
})
