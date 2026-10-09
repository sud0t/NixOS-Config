# System services: networking, bluetooth, power management, time sync, virtualisation, wireshark, ollama.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # battery level of connected devices (shown by Noctalia) and faster reconnects
    settings.General = {
      Experimental = true;
      FastConnectable = true;
    };
  };

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.timesyncd.enable = true;

  virtualisation.libvirtd.enable = true;

  # packet captures without root (the user is in the wireshark group)
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  # Ollama for the Neovim AI plugins (codecompanion, minuet, review.lua), as a system service with the
  # environment they expect: flash attention and an 8-bit KV cache keep more layers on the 4 GB GPU, models
  # stay loaded for 30 min. Models live in /var/lib/ollama/models; loadModels pulls the ones in use.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-vulkan; # pkgs.ollama-cuda is the CUDA build for the same GPU (compiles locally, not cached)
    environmentVariables = {
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_KEEP_ALIVE = "30m";
      OLLAMA_VULKAN = "1";
    };
    loadModels = [
      "qwen2.5-coder:7b" # codecompanion chat (nvim/lua/plugins/codecompanion.lua)
      "qwen2.5-coder:1.5b-base" # minuet inline completion (nvim/lua/plugins/minuet.lua)
      "qwen3:4b-instruct" # <Leader>AR review (nvim/lua/user/review.lua)
      "llama3.1:8b"
    ];
  };
}
