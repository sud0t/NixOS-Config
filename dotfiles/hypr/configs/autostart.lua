-------------------
---- AUTOSTART ----
-------------------
--
-- On NixOS the desktop daemons are systemd units rather than processes started from here:
--   pipewire, pipewire-pulse, wireplumber   -> services.pipewire (socket-activated user units)
--   xdg-desktop-portal(-hyprland / -gtk)    -> xdg.portal / programs.hyprland (D-Bus activated)
--   hyprpolkitagent, noctalia, udiskie      -> user services WantedBy graphical-session.target (home/desktop.nix)
--   ollama (+ OLLAMA_* environment)         -> services.ollama system service (modules/nixos/services.nix)
-- What remains here is the hand-off to systemd and the one-shot commands that are not daemons.

hl.on("hyprland.start", function()
	-- Give the session environment (WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE, ...) to D-Bus and to the
	-- systemd user manager, then start hyprland-session.target, which binds graphical-session.target and
	-- with it the user services above.
	hl.exec_cmd(
		"dbus-update-activation-environment --systemd --all"
			.. " && systemctl --user stop hyprland-session.target"
			.. " && systemctl --user start hyprland-session.target"
	)

	-- Other desktop/QoL stuff
	hl.exec_cmd("snappy-switcher --daemon") -- not packaged in nixpkgs; harmless when missing
	hl.exec_cmd("brightnessctl set 100%")
end)
