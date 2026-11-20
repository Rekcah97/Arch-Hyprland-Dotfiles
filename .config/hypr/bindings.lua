---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"
local terminal = "alacritty"
local fileManager = "nautilus"
local menu = "rofi -show drun"
local browser = "brave"

-- Basic applications
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + TAB", hl.dsp.exec_cmd("rofi -show window"))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("flameshot gui --delay 500"))

-- Universal copy/paste/cut (commented out)
-- hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("xclip -selection clipboard"))
-- hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("xclip -selection clipboard -t UTF8_STRING"))
-- hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("xclip -selection clipboard"))

-- Web applications
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("~/.local/share/arch/bin/brave-webapp.sh https://chatgpt.com/ ChatGPT"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("~/.local/share/arch/bin/brave-webapp.sh https://claude.ai/new ClaudeAi"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.local/share/arch/bin/brave-webapp.sh https://web.whatsapp.com/ WhatsApp"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("~/.local/share/arch/bin/brave-webapp.sh https://discord.com/channels/@me Discord"))

-- Lockscreen & window management
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("/home/rekcah/.local/share/arch/bin/toggle-waybar.sh"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Scratchpad workspace
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("swayosd-client --brightness raise"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"))
hl.bind("XF86RFKill", hl.dsp.exec_cmd("/home/rekcah/.local/share/arch/bin/airplane.sh"))

-- Requires playerctl
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("/home/rekcah/.local/share/arch/bin/media.sh previous"))
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("/home/rekcah/.local/share/arch/bin/media.sh play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("/home/rekcah/.local/share/arch/bin/media.sh play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("/home/rekcah/.local/share/arch/bin/media.sh next"))