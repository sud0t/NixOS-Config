# Desktop stack: Hyprland, the greetd/noctalia login screen, audio, portals, keyboard remaps, fonts, Qt theming.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Hyprland. The configuration is the Lua one (dotfiles/hypr/hyprland.lua), linked into
  # ~/.config/hypr by home/hyprland.nix; Hyprland >= 0.55 loads hyprland.lua in preference to hyprland.conf.
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  xdg.portal = {
    enable = true;
    # programs.hyprland already adds xdg-desktop-portal-hyprland; the gtk portal covers file choosers and settings
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Login: greetd running the Noctalia greeter on VT 1 (greetd's default)
  services.displayManager.noctalia-greeter.enable = true;

  # Audio: PipeWire with WirePlumber as the session manager. Everything runs as socket-activated systemd
  # user units from login, so sound works before Hyprland is up and survives a compositor restart.
  security.rtkit.enable = true; # realtime priority for the audio threads
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true; # 32-bit ALSA clients (Steam / Wine games)
    pulse.enable = true; # pipewire-pulse: PulseAudio clients (browsers, Electron apps, Discord, Slack)
    jack.enable = true; # pipewire-jack
    wireplumber = {
      enable = true;
      # Bluetooth audio: better codecs and HFP/mSBC for headset microphones, hardware volume
      extraConfig."10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
            "hsp_hs"
            "hsp_ag"
            "hfp_hf"
            "hfp_ag"
          ];
        };
      };
    };
  };

  # polkit; the agent (hyprpolkitagent) is a user service in home/desktop.nix
  security.polkit.enable = true;

  # Backends for udiskie (automount) and nemo (trash, mounts, dconf settings)
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  programs.dconf.enable = true;

  # Keyboard remaps, all keyboards:
  #   Right Shift -> Super (the Windows key, Hyprland's mainMod)
  #   Caps Lock   -> Escape when tapped, Control while held (overload); use "esc" for a plain Escape key
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        rightshift = "leftmeta";
        capslock = "overload(control, esc)";
      };
    };
  };

  # Fonts:
  #   Hack Nerd Font          kitty (font_family), the p10k prompt (nerdfont-v3 glyphs), the Claude Code status line
  #   JetBrainsMono Nerd Font second monospace Nerd Font
  #   Symbols Nerd Font       glyph fallback for any other font (fontconfig picks it up for missing icons)
  # plus Adwaita (kitty italics) and fallbacks so CJK text, symbols and emoji in browsers/Slack/Obsidian
  # render instead of showing boxes
  fonts = {
    fontconfig.enable = true;
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.hack
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      adwaita-fonts
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  # dbus-broker instead of the reference dbus daemon: lower latency for the D-Bus-heavy desktop
  # (portals, noctalia, udiskie, bluetooth)
  services.dbus.implementation = "broker";

  # Qt theming through qt6ct (QT_QPA_PLATFORMTHEME=qt6ct in hypr/configs/environment.lua). The qt module
  # installs qt5ct + qt6ct and, more importantly, puts the Qt plugin directories on QT_PLUGIN_PATH so Qt
  # applications can find the platform-theme plugin at all; the Hyprland env then selects qt6ct.
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    xdg-utils
    xdg-user-dirs

    # audio tools: wpctl (XF86AudioMicMute bind), pw-top/pw-cli, alsamixer/aplay, a mixer GUI
    wireplumber
    pipewire
    alsa-utils
    pwvucontrol
    playerctl # the commented-out XF86Audio{Next,Prev,Play,Pause} binds in binds.lua need it
  ];
}
