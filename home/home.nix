# Home Manager configuration for the user named in vars.nix.
#
# Every configuration file lives in ../dotfiles. Two kinds of links are used:
#   * directories you edit by hand (hypr, kitty, nvim, fastfetch) are out-of-store symlinks into
#     ~/nixos-config/dotfiles, so editing them works exactly as before and needs no rebuild;
#   * files the applications write to at runtime (noctalia config and state, hypr/noctalia.lua, obsidian's
#     vault list and dictionary, ~/.p10k.zsh) are copied in once on the first activation and never touched again.
# Both rely on this repository being checked out at ~/nixos-config (change `dotfiles` below otherwise).
{
  config,
  pkgs,
  lib,
  vars,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/nixos-config/dotfiles";

  # Noctalia's real settings (bar layout, theme, launcher pins, lock screen, wallpaper directory and the
  # starred wallpapers) live in ~/.local/state/noctalia, not ~/.config; the wallpaper paths carry the home
  # directory, so @home@ is filled in here
  noctaliaSettings = pkgs.writeText "noctalia-settings.toml" (
    lib.replaceStrings [ "@home@" ] [ config.home.homeDirectory ] (
      builtins.readFile ../dotfiles/noctalia-state/settings.toml
    )
  );

  # Obsidian's vault registry (was ~/.config/obsidian/obsidian.json with an absolute /home/... path)
  obsidianVaults = pkgs.writeText "obsidian.json" (
    builtins.toJSON {
      vaults."62f92fff07be910e" = {
        path = "${config.home.homeDirectory}/Obsidian/Personal";
        ts = 1783970141513;
        open = true;
      };
    }
  );
in
{
  imports = [
    ./zsh.nix
    ./hyprland.nix
    ./desktop.nix
    ./nvim.nix
    ./dev.nix
    ./apps.nix
    ./claude.nix
  ];

  _module.args.dotfiles = dotfiles;

  home = {
    username = vars.username;
    homeDirectory = "/home/${vars.username}";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;

  # restart/stop user services (noctalia, hyprpolkitagent, udiskie) whose units changed on activation,
  # instead of only printing a suggestion
  systemd.user.startServices = "sd-switch";

  xdg.enable = true;
  # standard user directories (~/Pictures/Screenshots is where hyprshot saves)
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };

  # Runtime-written files: seeded once, then owned by the applications
  home.activation.seedDotfileState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    seed() {
      # seed <source> <destination>: copy once, never overwrite
      if [ -e "$1" ] && [ ! -e "$2" ]; then
        run mkdir -p "$(dirname "$2")"
        run cp -a --no-preserve=ownership,mode "$1" "$2"
        run chmod -R u+w "$2"
      fi
    }
    seed "${dotfiles}/noctalia"                          "${config.xdg.configHome}/noctalia"
    seed "${noctaliaSettings}"                           "${config.xdg.stateHome}/noctalia/settings.toml"
    seed "${dotfiles}/noctalia-state/state.toml"         "${config.xdg.stateHome}/noctalia/state.toml"
    seed "${dotfiles}/hypr/noctalia.lua"                 "${config.xdg.configHome}/hypr/noctalia.lua"
    seed "${obsidianVaults}"                             "${config.xdg.configHome}/obsidian/obsidian.json"
    seed "${dotfiles}/obsidian/Custom Dictionary.txt"    "${config.xdg.configHome}/obsidian/Custom Dictionary.txt"
    seed "${dotfiles}/zsh/.p10k.zsh"                     "${config.home.homeDirectory}/.p10k.zsh"
  '';
}
