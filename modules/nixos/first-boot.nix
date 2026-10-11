# One-time user setup on the first boot after install.sh (scripts/nixos-first-boot): zinit plugins, Neovim
# plugins + Mason tools, rustup toolchain, vibium CLI, nix-index database. Runs in the background as the
# user once the network is up and Home Manager has linked the dotfiles; retries until every step has
# succeeded once, then never starts again (marker: ~/.local/state/nixos-config/first-boot.done).
{
  config,
  pkgs,
  lib,
  vars,
  ...
}:

let
  firstBoot = pkgs.writeScriptBin "nixos-first-boot" (builtins.readFile ../../scripts/nixos-first-boot);
  home = config.users.users.${vars.username}.home;
in
{
  # also a command, to re-run it by hand
  environment.systemPackages = [ firstBoot ];

  systemd.services.nixos-first-boot = {
    description = "One-time user setup for ${vars.username} (zinit, Neovim plugins, Mason, rustup, vibium, nix-index)";
    # Type=simple: multi-user.target (and the login screen) does not wait for it
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "nix-daemon.socket"
      "home-manager-${vars.username}.service"
    ];
    restartIfChanged = false;
    # services do not get the login environment: nix-index needs `nixpkgs` on NIX_PATH (nix.nixPath)
    environment.NIX_PATH = lib.concatStringsSep ":" config.nix.nixPath;
    unitConfig = {
      ConditionPathExists = "!${home}/.local/state/nixos-config/first-boot.done";
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Type = "simple";
      User = vars.username;
      Group = "users";
      ExecStart = "${pkgs.bash}/bin/bash ${firstBoot}/bin/nixos-first-boot";
      Restart = "on-failure";
      RestartSec = "2min";
      # stays out of the way of the desktop
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
}
