# Hyprland user side. The compositor and its portal come from programs.hyprland (modules/nixos/desktop.nix);
# the Lua configuration is used unchanged from dotfiles/hypr, except autostart.lua, which now hands the
# session to systemd instead of starting every daemon itself (see the comment block in that file).
{
  config,
  pkgs,
  lib,
  dotfiles,
  ...
}:

let
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  # ~/.config/hypr/* -> ~/nixos-config/dotfiles/hypr/* (editable in place, Hyprland reloads on save).
  # Linked file by file rather than as one directory so that .luarc.json can be generated here and
  # noctalia.lua, which Noctalia rewrites from its colour template, can be a plain file (seeded in home.nix).
  xdg.configFile = {
    "hypr/hyprland.lua".source = link "hypr/hyprland.lua";
    "hypr/configs".source = link "hypr/configs";
    # Lua stubs for lua-language-server, from the installed Hyprland
    "hypr/.luarc.json".text = builtins.toJSON {
      workspace.library = [ "${pkgs.hyprland}/share/hypr/stubs" ];
    };
  };

  # Started from autostart.lua once Hyprland is up. Binding graphical-session.target to it is what starts
  # noctalia, hyprpolkitagent and udiskie (all WantedBy=graphical-session.target) with the compositor's
  # environment, and stops them again when Hyprland exits.
  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland compositor session";
      Documentation = [ "man:systemd.special(7)" ];
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };

  home.packages = with pkgs; [
    hyprshot # Print -> region screenshot to ~/Pictures/Screenshots
    hyprpicker
    hypridle
    brightnessctl # autostart: brightnessctl set 100%
    wl-clipboard
    hyprpolkitagent
  ];
}
