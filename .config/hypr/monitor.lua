--------------------
---- MONITORS ----
--------------------

hl.env("GDK_SCALE", "1.7")

hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = "1",
})

hl.monitor({
    output   = "HDMI-A-1",
    mode     = "800x600",
    position = "0x0",
    scale    = "1",
})