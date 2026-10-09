# Desktop programs: kitty, fastfetch, nemo, Noctalia, the polkit agent, udiskie, wallpapers, and the
# helper commands the Noctalia configuration calls.
#
# User services bound to graphical-session.target (started by hyprland-session.target from autostart.lua):
#   hyprpolkitagent -> systemd.user.services.hyprpolkitagent
#   noctalia        -> programs.noctalia.systemd (upstream Home Manager module)
#   udiskie         -> services.udiskie
{
  config,
  pkgs,
  lib,
  inputs,
  dotfiles,
  ...
}:

let
  # scripts/<name> installed as a command on PATH (the per-user profile is on PATH for user services too,
  # so Noctalia can call them by bare name from config.toml)
  script = name: pkgs.writeScriptBin name (builtins.readFile (../scripts + "/${name}"));
in
{
  xdg.configFile."kitty".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/kitty";
  xdg.configFile."fastfetch".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/fastfetch";

  # The starred wallpapers (dotfiles/wallpapers, the 13 favourites from Noctalia's settings) are linked
  # into ~/Pictures/Wallpapers, Noctalia's wallpaper directory. The directory itself stays a normal one,
  # so other wallpapers can be dropped in next to them.
  home.file = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "Pictures/Wallpapers/${name}" {
      source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/wallpapers/${name}";
    }
  ) (lib.filterAttrs (_: type: type == "regular") (builtins.readDir ../dotfiles/wallpapers));

  # Noctalia shell (package from the noctalia flake input, 5.x). ~/.config/noctalia (config.toml,
  # user-templates.toml, templates/) and ~/.local/state/noctalia (settings.toml, state.toml) are seeded
  # in home.nix, since Noctalia writes to both at runtime.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
  };

  # Noctalia plugins, pinned through flake inputs. ~/.local/share/noctalia/plugins is Noctalia's built-in
  # read-only "local" source: each sub-directory with a plugin.toml is discovered, and the plugin is enabled
  # by its id in settings.toml ([plugins] enabled). Updates come with `nix flake update`, not from
  # Noctalia's own git fetches ([plugins] auto_update = "none").
  #   nix-monitor (avivbintangaringga/nix-monitor): compares the running nixpkgs revision with the
  #   nixos-unstable branch, shows NixOS/Home Manager generations and store size, and runs `nixos-update`
  #   from its Update button
  xdg.dataFile."noctalia/plugins/nix-monitor".source = "${inputs.noctalia-community-plugins}/nix-monitor";

  systemd.user.services.hyprpolkitagent = {
    Unit = {
      Description = "Hyprland polkit authentication agent";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # plain `udiskie` = automount + notifications, no tray icon
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "never";
  };

  home.packages = with pkgs; [
    kitty
    nemo # fileManager in hypr/configs/programs.lua

    # commands:
    #   p10reload.sh   post_hook of Noctalia's p10k colour template (makes running shells re-read ~/.p10k.zsh)
    #   nixos-update   `nix flake update` + `nixos-rebuild switch` in a terminal
    (script "p10reload.sh")
    (script "nixos-update")
    psmisc # killall, used by p10reload.sh
  ];
}
