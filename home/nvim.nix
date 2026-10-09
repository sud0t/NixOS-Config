# Neovim (AstroNvim) with everything the configuration in dotfiles/nvim reaches for.
# The config directory is linked in place, so lazy.nvim keeps managing plugins under ~/.local/share/nvim
# and :Lazy update still rewrites lazy-lock.json in the repository.
#
# Mason (plugins/mason.lua) downloads prebuilt binaries; they run on NixOS thanks to programs.nix-ld in the
# system configuration. The same tools are also installed from nixpkgs below, so the language servers,
# formatters and debuggers work even before Mason has fetched anything.
{
  config,
  pkgs,
  lib,
  dotfiles,
  ...
}:

let
  # Python packages Neovim's python3 provider needs: pynvim itself, molten's kernel client, debugpy for
  # nvim-dap-python, plus the jupytext CLI (was `pipx install jupytext`) and pygmentize for the shell.
  pythonPackages =
    ps: with ps; [
      pynvim
      jupyter-client
      ipykernel
      jupytext
      debugpy
      ipython
      pygments # `pygmentize`, used by the OMZ colorize plugin in the .zshrc
      playwright # Python Playwright for the webapp-testing skill (browsers: PLAYWRIGHT_BROWSERS_PATH in dev.nix)
    ];

  # `python3` on PATH (kitty's SUPER+SHIFT+Q python terminal, jupytext, ipython, molten's kernels)
  python = pkgs.python3.withPackages pythonPackages;

  # nixpkgs' plain `neovim` wrapper ships with withPython3 = false, which sets
  # vim.g.loaded_python3_provider = 0 and would turn the provider off for good (astrocore.lua keeps it on
  # because molten is a Python remote plugin). Build the wrapper with the provider and the same packages.
  neovim = pkgs.neovim.override {
    withPython3 = true;
    extraPython3Packages = pythonPackages;
    withNodeJs = false; # loaded_node_provider = 0 in astrocore.lua
    withRuby = false;
  };
in
{
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    SUDO_EDITOR = "nvim";
  };

  home.packages =
    [
      neovim
      python
    ]
    ++ (with pkgs; [
      # build tools for treesitter parsers (auto_install = true) and native plugins
      # (nodejs for Mason's npm-based servers and the local-lua-debugger adapter comes from dev.nix)
      gcc
      gnumake
      tree-sitter
      git
      ripgrep
      fd
      lazygit
      gdu
      bottom
      unzip
      wget
      curl

      # language servers (mason.lua ensure_installed)
      lua-language-server
      bash-language-server
      basedpyright
      hyprls
      vscode-langservers-extracted # html-lsp, json-lsp
      lemminx
      # formatters
      stylua
      biome
      shfmt
      ruff # astrocommunity.pack.python.ruff
      # Rust (rustup) and the TypeScript servers come from dev.nix
      # Lua interpreters for the local-lua-debugger configurations in plugins/dap.lua ("lua5.4", "luajit").
      # luajit also installs bin/lua, so lua5_4 is reached through the wrapper only (both in the profile
      # would collide on bin/lua and fail the Home Manager build)
      (writeShellScriptBin "lua5.4" ''exec ${lua5_4}/bin/lua "$@"'')
      luajit
      # image.nvim (magick_cli processor) for molten plots
      imagemagick
    ]);
}
