-- Scrolling columns fit the uConsole's wide, short logical display better.
hl.config({
  general = { layout = "scrolling" },
  scrolling = {
    column_width = 0.5,
    follow_focus = true,
    fullscreen_on_one_column = true,
  },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
})
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Desktop-sized floating dialogs must fit the logical monitor dimensions.
hl.window_rule({
  match = { tag = "floating-window" },
  size = { "(monitor_w*0.9)", "(monitor_h*0.85)" },
  center = true,
})
hl.window_rule({
  match = { class = "^org[.]omarchy[.]about$" },
  size = { "(monitor_w*0.9)", "(monitor_h*0.85)" },
  center = true,
})
hl.window_rule({
  match = { class = "^(org[.]omarchy[.]terminal|org[.]codeberg[.]dnkl[.]foot)$" },
  tag = "-floating-window",
  float = false,
})
