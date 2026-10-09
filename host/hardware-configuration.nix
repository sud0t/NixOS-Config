# Written from this laptop's lsblk/lspci output. After installing NixOS, run
#   sudo nixos-generate-config --show-hardware-config
# and compare: the UUIDs below are the current ones, but re-generate this file if the disks are repartitioned.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # nvme1n1: ESP (A94E-BE3F) / swap / ext4 root. nvme0n1 holds the Windows install (os-prober picks it up).
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b3b54dbd-1764-42e6-b1d3-fd25b9a9d1fa";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/A94E-BE3F";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/c9722d97-ffa4-457b-aeed-08406ec5441c"; }
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # Intel AX200 Wi-Fi / Bluetooth firmware
  hardware.enableRedistributableFirmware = true;
}
