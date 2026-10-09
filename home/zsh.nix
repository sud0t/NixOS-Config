# zsh: the original ~/.zshrc (dotfiles/zsh/.zshrc) with powerlevel10k and zinit taken from nixpkgs
# instead of ~/.plevel10k and a git clone. ~/.p10k.zsh is seeded in home.nix because Noctalia
# regenerates it from its colour template.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.zsh = {
    enable = true;
    # the .zshrc runs compinit itself (after zinit has loaded zsh-completions)
    enableCompletion = false;
    # zinit loads zsh-autosuggestions / zsh-syntax-highlighting
    autosuggestion.enable = false;
    syntaxHighlighting.enable = false;

    # same values as the History block in the .zshrc, so Home Manager's own HIST* lines agree with it
    history = {
      size = 5000;
      save = 5000;
      path = "${config.home.homeDirectory}/.zsh_history";
      append = true;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
      saveNoDups = true;
      findNoDups = true;
    };

    initContent =
      lib.replaceStrings
        [ "@powerlevel10k@" "@zinit@" ]
        [ "${pkgs.zsh-powerlevel10k}" "${pkgs.zinit}" ]
        (builtins.readFile ../dotfiles/zsh/.zshrc);
  };

  # command-not-found handler for a flake-based system (the OMZ command-not-found snippet in the .zshrc
  # finds no distro handler on NixOS). Run `nix-index` once to build the database.
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    # aliases / shell integrations in the .zshrc
    eza
    zoxide
    fzf
    grc # OMZP::grc
    # OMZP::colorize needs pygmentize: it comes from the python environment in nvim.nix (a second copy of
    # pygments here would collide on bin/pygmentize)
    git # zinit clones plugins and OMZ snippets into ~/.local/share/zinit
    fastfetch
  ];
}
