---------------------
---- WINDOWS AND WORKSPACES ----
---------------------

-- See https://wiki.hypr.land/configuring/core/rules/

-- Example window rules that are useful

-- Suppress maximize events from all apps
hl.window_rule({
  name  = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
  name  = "fix-xwayland-drags",
  match = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = true,
    fullscreen = false,
    pin        = false,
  },
  no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
  name = "move-hyprland-run",
  match = { class = "hyprland-run" },
  move  = "20 monitor_h-120",
  float = true,
})

-- Make impala window float and appear on top
hl.window_rule({
  name  = "impala-float",
  match = {
    class = "^(Alacritty)$",
    title = "^(impala)$",
  },
  float    = true,
  center   = true,
  size     = "800 600",
})

-- Make btop window float and appear on top
hl.window_rule({
  name  = "btop-float",
  match = {
    class = "^(Alacritty)$",
    title = "^(btop)$",
  },
  float    = true,
  center   = true,
  size     = "800 530",
})

-- Make bluetui window float and appear on top
hl.window_rule({
  name  = "bluetui-float",
  match = {
    class = "^(Alacritty)$",
    title = "^(bluetui)$",
  },
  float    = true,
  center   = true,
  size     = "725 530",
})

-- Make wiremix window float and appear on top
hl.window_rule({
  name  = "wiremix-float",
  match = {
    class = "^(Alacritty)$",
    title = "^(wiremix)$",
  },
  float    = true,
  center   = true,
  size     = "700 430",
})

-- Window rules for web apps
hl.window_rule({
  name  = "brave-webapp",
  match = { class = "^(brave-.*)$" },
  float = false,
  center = false,
  size   = "1400 900",
})

-- Make yayfzf window float and appear on top
hl.window_rule({
  name  = "yayfzf-float",
  match = {
    class = "^(Alacritty)$",
    title = "^(yayfzf)$",
  },
  float    = true,
  center   = true,
  size     = "700 430",
})

-- Steam filepicker
hl.window_rule({
  name  = "steam-filepicker",
  match = {
    class = "^(steam)$",
    title = "^(Open)$",
  },
  float    = true,
  center   = true,
  size     = "900 600",
})

-- Make screenshot window float and appear on top
hl.window_rule({
  name  = "screenshot-float",
  match = { class = "^(org\\.adishatz\\.Screenshot)$" },
  float    = true,
  center   = true,
  size     = "800 200",
})

hl.window_rule({
  name  = "tmog-task-manager",
  match = { class = "^(com\\.tmog\\.taskmanager)$" },
  float  = true,
  center = true,
  size   = "1500 800",
})