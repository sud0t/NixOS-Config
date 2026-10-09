{
  description = "NixOS + Home Manager: Hyprland (Lua config), Noctalia, Neovim, Claude Code";

  inputs = {
    # nixos-unstable: current Hyprland (0.56.x) and tooling
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia 5.x (the `noctalia msg ...` CLI, config.toml templates and the plugin API the configs use).
    # nixpkgs still carries 4.7.x, so the shell comes from upstream's flake.
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Code skills (plain repositories, linked into ~/.claude/skills by home/claude.nix)
    apple-design-skill = {
      url = "github:dickwu/apple-design-skill"; # SKILL.md at the root
      flake = false;
    };
    awesome-llm-observability = {
      url = "github:ContextJet-ai/awesome-llm-observability"; # skills/<name>/SKILL.md (26 skills)
      flake = false;
    };
    e2e-agent-skills = {
      url = "github:jmr85/e2e-agent-skills"; # skills/<name>/SKILL.md (playwright, selenium, appium)
      flake = false;
    };
    vibium = {
      url = "github:VibiumDev/vibium"; # skills/{browser,check}/SKILL.md; needs the vibium CLI (npm)
      flake = false;
    };
    anthropic-skills = {
      url = "github:anthropics/skills"; # only skills/webapp-testing is linked (see home/claude.nix)
      flake = false;
    };
    caveman = {
      url = "github:JuliusBrussee/caveman"; # terse output mode: skills + the session hooks that turn it on
      flake = false;
    };

    # Noctalia community plugins, pinned here instead of auto-updated by Noctalia's git source;
    # only nix-monitor is linked (see home/desktop.nix)
    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      noctalia,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # user and host names come from vars.nix (written by install.sh, or edited by hand)
      raw = import ./vars.nix;
      vars = {
        username =
          if raw.username != "" then
            raw.username
          else
            throw "vars.nix: `username` is empty. Run install.sh, or set username (and hostname) in vars.nix.";
        hostname = if raw.hostname != "" then raw.hostname else "nixos";
      };
    in
    {
      # `nixos-rebuild switch --flake ~/nixos-config` picks the output named after the machine's hostname
      nixosConfigurations.${vars.hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs vars; };
        modules = [
          { nixpkgs.overlays = [ noctalia.overlays.default ]; }
          ./host/configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = { inherit inputs vars; };
              sharedModules = [ noctalia.homeModules.default ];
              users.${vars.username} = import ./home/home.nix;
            };
          }
        ];
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
