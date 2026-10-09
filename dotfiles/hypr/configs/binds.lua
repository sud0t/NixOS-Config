---------------------
---- KEYBINDINGS ----
---------------------

-- add binds for shift plus super plus h j k l for window swapping

require("configs.programs")
local mainMod = "SUPER"
local pyterm = "kitty -e python3"

-- Window minimizing with special workspaces
hl.bind("SUPER + X", function() -- Minimize window with super x
	hl.dispatch(hl.dsp.window.tag({ tag = "minimized", window = hl.get_active_window() }))
	hl.dispatch(hl.dsp.window.move({ workspace = "10", follow = false }))
end)
hl.bind("SUPER + Z", function() -- Get minimized windows with super z
	if hl.get_workspace("10") then
		hl.dispatch(hl.dsp.window.move({ workspace = hl.get_active_workspace(), window = "tag:minimized" }))
		hl.dispatch(hl.dsp.window.clear_tags({ window = "tag:minimized" }))
	end
end)

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd(pyterm))
hl.bind(mainMod .. " + C", hl.dsp.window.close())

hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + M", hl.dsp.focus({ workspace = 10 }))
-- hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen_state({ internal = 3, client = 3, action = "toggle" }))

-- hl.bind("ALT + TAB", hl.dsp.exec_cmd("snappy-switcher next --mod alt"))
-- hl.bind("SUPER + TAB", hl.dsp.exec_cmd("snappy-switcher next --workspace --mod super"))

-- Noctalia keybind
hl.bind(mainMod .. "+ A", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"))
hl.bind("ALT + TAB", hl.dsp.exec_cmd("noctalia msg window-switcher"))

-- Dwindle layout binds
hl.bind(mainMod .. " + S", hl.dsp.layout("swapsplit"))
hl.bind(mainMod .. " + SHIFT +S", hl.dsp.layout("togglesplit"))

-- Scrolling layout binds
-- hl.bind(mainMod .. " + SHIFT + H", hl.dsp.layout("swapcol l"))
-- hl.bind(mainMod .. " + SHIFT + L", hl.dsp.layout("swapcol r"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Screenshotting
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -z -m region -o ~/Pictures/Screenshots"))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- WIP
-- for i = 1, 10 do
--     local key = i % 10
--     hl.bind(mainMod .. " + mouse_up", hl.dsp.window.cycle_next({ window = key }))
-- end
-- hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ direction = "up" }))

-- Move/resize windows
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("noctalia msg volume-up")
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("noctalia msg volume-down")
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("noctalia msg volume-mute")
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
)
-- hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brillo -A 5"), { locked = true, repeating = true })
-- hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brillo -U 5"), { locked = true, repeating = true })

-- Requires playerctl
-- hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
-- hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
-- hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
-- hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
