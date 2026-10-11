# Hybrid graphics: Intel UHD 630 (00:02.0) drives the displays, Quadro T1000 (01:00.0) is available for
# offload and Ollama. hypr/configs/environment.lua hands both cards to Hyprland, Intel first
# (AQ_DRM_DEVICES=/dev/dri/igpu:/dev/dri/dgpu, the stable names created below).
{
  config,
  pkgs,
  lib,
  ...
}:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # VA-API on the Intel iGPU (Coffee Lake): hardware video decoding in LibreWolf/Chrome/Obsidian
    extraPackages = with pkgs; [
      intel-media-driver
      libvdpau-va-gl
    ];
  };
  # make VA-API pick the Intel driver (the nvidia one needs the dGPU awake)
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  services.xserver.videoDrivers = [ "nvidia" ];

  # card0/card1 are numbered in driver load order, which differs between boots and systems (on this laptop
  # Artix gets the nvidia card as card0). Fixed names by PCI address instead; AQ_DRM_DEVICES is
  # colon-separated, so the /dev/dri/by-path names (which contain colons) cannot be used there.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:00:02.0", SYMLINK+="dri/igpu"
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/dgpu"
  '';

  hardware.nvidia = {
    modesetting.enable = true;
    # nvidia-suspend/resume/hibernate services and preserved video memory: reliable suspend/resume with the
    # dGPU in use. finegrained (runtime D3, dGPU fully off) stays off because Hyprland holds the nvidia DRM
    # device open (AQ_DRM_DEVICES in environment.lua), which would keep waking it.
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    # proprietary kernel module (the open module also supports Turing if you want to switch)
    open = false;
    nvidiaSettings = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true; # `nvidia-offload <program>`
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
