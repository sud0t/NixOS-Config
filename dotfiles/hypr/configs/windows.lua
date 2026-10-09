--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

require("configs.programs")

hl.workspace_rule({
	workspace = "1",
	layout = "dwindle",
	monitor = "eDP-1",
})
hl.workspace_rule({
	workspace = "2",
	layout = "dwindle",
	monitor = "HDMI-A-1",
})
hl.workspace_rule({
	workspace = "10",
	default_name = "-minimized",
	layout = "dwindle",
})

hl.config({
	dwindle = {
		preserve_split = true, -- You probably want this
		force_split = 2,
	},
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
	master = {
		new_status = "master",
		new_on_top = true,
	},
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
-- hl.config({
-- 	scrolling = {
-- 		fullscreen_on_one_column = true,
-- 		column_width = 1.0,
-- 	},
-- })
-- hl.window_rule({
-- 	name = "steam_width",
-- 	match = {
-- 		class = "steam",
-- 	},
-- 	scrolling_width = 1,
-- })
-- hl.window_rule({
-- 	name = "libre_width",
-- 	match = {
-- 		class = "librewolf",
-- 	},
-- 	scrolling_width = 1,
-- })
-- hl.window_rule({
-- 	name = "discord_width",
-- 	match = {
-- 		class = "discord",
-- 	},
-- 	scrolling_width = 1,
-- })

local suppressMaximizeRule = hl.window_rule({
	-- Ignore maximize requests from all apps. You'll probably like this.
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})
suppressMaximizeRule:set_enabled(true)

hl.window_rule({
	-- Fix some dragging issues with XWayland
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

hl.window_rule({
	match = { class = terminal },
	opacity = "0.9 override 0.4 override 1.0 override",
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
}) -- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
