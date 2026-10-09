# System configuration (Dell laptop: i7-9850H, UHD 630 + Quadro T1000, AX200 Wi-Fi).
# The per-user configuration lives in ../home. User and host names come from ../vars.nix.
{
  config,
  pkgs,
  lib,
  inputs,
  vars,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../modules/nixos/desktop.nix
    ../modules/nixos/services.nix
    ../modules/nixos/nvidia.nix
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # the repository is a dirty git tree by design (nothing is committed); silence the warning per rebuild
    warn-dirty = false;
    # keep going with the binary cache if one download fails, more context on build errors
    fallback = true;
    log-lines = 50;
  };
  # deduplicate identical store files weekly (same effect as auto-optimise-store, without slowing every build)
  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  # `nix shell nixpkgs#foo`, `nix-shell -p foo` and `nix run nixpkgs#foo` use the nixpkgs this system is
  # built from: no extra nixpkgs downloads/evaluations and the same package versions as the system
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];
  # skips building the NixOS manual on every rebuild (man pages are still installed)
  documentation.nixos.enable = false;

  # nvidia driver, Slack, Google Chrome, Claude Code, Notion, Obsidian
  nixpkgs.config.allowUnfree = true;

  # Bootloader: GRUB on the ESP at /boot/efi, with os-prober for the Windows install on nvme0n1
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = true;
      configurationLimit = 20; # keep the boot menu (and the ESP) tidy; older generations are still gc'd
    };
  };

  # Compressed swap in RAM in front of the swap partition (20 GB RAM; zram gets the higher priority,
  # the disk swap stays as the fallback)
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # NVMe: discard unused blocks weekly instead of mounting with `discard`
  services.fstrim.enable = true;
  # Intel thermal/turbo management on the laptop
  services.thermald.enable = true;
  # firmware updates (`fwupdmgr update`)
  services.fwupd.enable = true;
  # cap the journal so logs cannot fill the root filesystem
  services.journald.settings.Journal = {
    SystemMaxUse = "500M";
    MaxRetentionSec = "1month";
  };

  networking.hostName = vars.hostname;

  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.${vars.username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    # wheel: sudo; networkmanager: manage connections; video/input: the Wayland session; kvm + libvirtd: VMs;
    # wireshark: packet captures
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
      "kvm"
      "libvirtd"
      "wireshark"
    ];
  };

  # Login shell; the actual zsh configuration is Home Manager's (home/zsh.nix)
  programs.zsh.enable = true;
  # With flakes there is no programs.sqlite for the channel-based handler; the shell uses nix-index instead
  programs.command-not-found.enable = false;

  # Electron apps from nixpkgs (Slack, Obsidian, Notion, Google Chrome, ...) start on Wayland instead of
  # XWayland: sharp on the HiDPI/scaled outputs, working clipboard and screen sharing through the portal.
  # Same intent as ELECTRON_OZONE_PLATFORM_HINT=auto in hypr/configs/environment.lua, applied by the
  # nixpkgs wrappers for apps that predate that hint.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    unzip
    vim
    pciutils
    usbutils
  ];

  # Lets binaries that were not built for NixOS run (Mason-installed language servers/debuggers in Neovim,
  # anything downloaded by pipx/npm/cargo).
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
      curl
      libxml2
      icu
    ];
  };

  system.stateVersion = "26.05";
}
