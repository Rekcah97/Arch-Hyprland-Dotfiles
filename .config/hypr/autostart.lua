-----------------
---- AUTOSTART ----
-----------------

-- See https://wiki.hypr.land/configuring/core/autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:

hl.on("hyprland.start", function ()
  hl.exec_cmd("hypridle")
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("waybar")
  hl.exec_cmd("swayosd-server")
  hl.exec_cmd("waypaper --restore")
  hl.exec_cmd("uwsma-app mako")

  -- Import environment variables for other services
  hl.exec_cmd("systemctl --user import-environment DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR")
end)