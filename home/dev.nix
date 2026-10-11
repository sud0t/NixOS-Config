# Development toolchains: Node.js/npm, TypeScript (and React tooling), Rust, Go.
# Project-level dependencies (react, vite, cargo crates, ...) stay in each project; what is here is the
# global tooling plus the language servers/formatters the Neovim config (astrocommunity typescript-all-in-one
# and rust packs) and Mason expect.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.sessionVariables = {
    # `npm install -g ...` lands in ~/.local (bin on PATH through the .zshrc); the Nix profile itself is
    # read-only
    NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.local";

    # Playwright (python package in nvim.nix, npm `playwright` in projects): browsers downloaded by
    # `playwright install` do not run on NixOS, so point every Playwright at nixpkgs' prebuilt
    # chromium/firefox/webkit of the matching version instead
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE = "ubuntu-24.04"; # what nixpkgs' WebKit build identifies as
  };

  home.packages = with pkgs; [
    # Node.js / npm (also npx, corepack)
    nodejs
    pnpm
    yarn

    # TypeScript + React: tsc, the TypeScript language servers nvim uses, prettier/eslint for projects
    # that do not vendor them. Start a React app with `npm create vite@latest` (react / react-ts templates).
    typescript
    typescript-language-server
    vtsls
    prettier
    eslint

    # Rust: rustup manages the toolchains (nixos-first-boot runs `rustup default stable` and adds rust-analyzer);
    # rust.lua asks `rustup which rust-analyzer`. pkg-config for crates that link system libraries.
    rustup
    pkg-config

    # Go (GOPATH=~/.go in the .zshrc)
    go
  ];
}
