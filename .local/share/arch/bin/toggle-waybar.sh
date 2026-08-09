#!/bin/bash

if pgrep -x waybar > /dev/null
then
    pkill waybar
else
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR 2>/dev/null
    nohup waybar > /tmp/waybar.log 2>&1 & disown
fi