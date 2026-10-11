# System configuration (ThinkPad P53: i7-9850H, UHD 630 + Quadro T1000, AX200 Wi-Fi).
# The per-user configuration lives in ../home. User and host names come from ../vars.nix, the disks from
# ./disks.nix.
{
  config,
  pkgs,
  lib,
  inputs,
  vars,
  ...
}:

let
  disks = import ./disks.nix;

  # keeps a single "NixOS" entry in the UEFI boot menu (see the script); run after every GRUB install
  efiEntries = pkgs.writeScript "nixos-efi-entries" (builtins.readFile ../scripts/nixos-efi-entries);
  efiEntriesPath = lib.makeBinPath [
    pkgs.efibootmgr
    pkgs.util-linux
    pkgs.coreutils
    pkgs.gnused
  ];
in
{
  imports = [
    ./hardware-configuration.nix
    ../modules/nixos/desktop.nix
    ../modules/nixos/services.nix
    ../modules/nixos/nvidia.nix
    ../modules/nixos/first-boot.nix
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

  # Bootloader: GRUB (UEFI) on the NixOS disk's own ESP, mounted at /boot/efi; kernels and grub.cfg stay in
  # /boot on the root filesystem. The other disk (Artix, disks.nix `protected`) is never written to: its ESP
  # keeps its own GRUB and UEFI entry, and the menu below only chainloads it.
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      # UEFI boot menu entry "NixOS" (\EFI\NixOS\grubx64.efi). The default id would be "NixOS-boot-efi",
      # derived from efiSysMountPoint, and only mirroredBoots can change it, hence the override of the
      # single mirroredBoots entry the module derives from `device`.
      mirroredBoots = lib.mkForce [
        {
          path = "/boot";
          devices = [ "nodev" ];
          efiSysMountPoint = "/boot/efi";
          efiBootloaderId = "NixOS";
        }
      ];
      # os-prober would mount the other disk's partitions to look for systems; the fixed entry below finds
      # Artix's GRUB by file instead (read-only, no mounting) and adds it exactly once
      useOSProber = false;
      extraEntries = ''
        insmod part_gpt
        insmod fat
        insmod search
        insmod chain
        if search --no-floppy --file --set=artix_esp /EFI/artix/grubx64.efi; then
          menuentry "Artix Linux" {
            set root=$artix_esp
            chainloader /EFI/artix/grubx64.efi
          }
        fi
      '';
      # grub-install registers "NixOS" in the firmware; drop stale or duplicate NixOS entries (never other
      # systems' entries or anything on another disk)
      extraInstallCommands = ''
        PATH=${efiEntriesPath}:$PATH ${pkgs.bash}/bin/bash ${efiEntries} --esp-mount /boot/efi --label NixOS || true
      '';
      configurationLimit = 20; # keep the boot menu tidy; older generations are still gc'd
    };
  };

  # The protected disks (Artix) are invisible to udisks: udiskie does not automount them at login and nemo
  # does not list them. Mount one by hand if you need it: sudo mount -o ro /dev/disk/by-label/ROOT /mnt
  services.udev.extraRules = lib.concatMapStrings (d: ''
    SUBSYSTEM=="block", ENV{ID_SERIAL}=="*${d.serial}*", ENV{UDISKS_IGNORE}="1"
  '') disks.protected;

  # Intel AX200 Wi-Fi / Bluetooth firmware (hardware-configuration.nix is generated and does not set it)
  hardware.enableRedistributableFirmware = true;

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
    efibootmgr # inspect the UEFI boot entries (efibootmgr -v)
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
