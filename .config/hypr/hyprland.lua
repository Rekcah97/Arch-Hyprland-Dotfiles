-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- HYPRLAND LUA CONFIGURATION (Hyprland 0.55+)
-- Modular structure: each section in its own file
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Entry point: require all modules
require("monitor")
require("input")
require("bindings")
require("looknfeel")
require("autostart")
require("windows")

-- Shared environment variables (can also go in individual modules)
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("ADW_DISABLE_PORTAL", "1")