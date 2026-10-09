# Applications from other-apps.txt plus the ones the dumped configs belong to.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.packages = with pkgs; [
    slack # 1. Slack
    notion-app-enhanced # 2. Notion: the only Linux Notion desktop build in nixpkgs (official client is macOS/Windows only)
    claude-code # 3. Claude Code (was the native installer in ~/.local/bin/claude)
    librewolf # 4. Librewolf (browser profile is migrated by hand, see README)
    google-chrome # 5. Google Chrome

    # dumped configs
    obsidian # vault list + custom dictionary seeded in home.nix; vault at ~/Obsidian/Personal
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "librewolf.desktop";
      "x-scheme-handler/https" = "librewolf.desktop";
      "text/html" = "librewolf.desktop";
    };
  };
}
