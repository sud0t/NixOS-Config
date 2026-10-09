# ~/.zshrc, installed through Home Manager (home/zsh.nix). The two `@name@` placeholders in the
# source lines below are replaced with the nixpkgs store paths of powerlevel10k and zinit at build time;
# everything else is the original .zshrc.

# if statement so fastfetch only appears if terminal width is ideal
# if [[ $(tput cols) -gt 71 && $(tput lines) -gt 20 ]]; then
# fastfetch -c examples/8.jsonc
# fi

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# was: source ~/.plevel10k/powerlevel10k.zsh-theme
source "@powerlevel10k@/share/zsh-powerlevel10k/powerlevel10k.zsh-theme"

# Include things I want visible to path
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/Scripts:$PATH"

# zinit itself comes from nixpkgs (no git clone needed); plugins and snippets still live in
# ~/.local/share/zinit, the same place as before
typeset -gA ZINIT
ZINIT[HOME_DIR]="$HOME/.local/share/zinit"
source "@zinit@/share/zinit/zinit.zsh"


# Zinit zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Zinit snippets (oh my zsh)
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found
zinit snippet OMZP::eza
zinit snippet OMZP::grc
zinit snippet OMZP::colorize
zinit snippet OMZP::colored-man-pages

# Load completions
autoload -U compinit && compinit
zinit cdreplay -q

# History settings
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu no
zstyle 'fzf-tab:complete:cd*' fzf-preview 'ls --color $realpath'
zstyle 'fzf-tab:complete:ls*' fzf-preview 'ls --color $realpath'
zstyle 'fzf-tab:complete:__zoxide_z*' fzf preview 'ls --color $realpath'
ZSH_COLORIZE_STYLE="colorful"

# Aliases
alias ls="eza --color=always --group-directories-first --icons=always"
alias la="eza -la --color=always --group-directories-first --icons=always"
alias vim="nvim"
alias svim="sudoedit"
alias rebuild="nixos-rebuild switch --sudo --flake ~/nixos-config"
alias rm="rm -i"
alias venv="source .venv/bin/activate"

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"

# Shell paths
export GOPATH="$HOME/.go"
export SUDO_EDITOR="nvim"
export VISUAL="nvim"
export EDITOR="nvim"


# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
