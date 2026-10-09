#!/usr/bin/env bash
#
# install.sh — set up this configuration on a fresh NixOS install.
#
# Run it as root, for the user who will own the desktop. Either of these, from anywhere (a USB stick, a clone):
#     sudo bash /run/media/$USER/USB/nixos-config/install.sh        # the user is taken from sudo
#     bash /path/to/nixos-config/install.sh --user alice            # from a root login
#
# Run it from tty2 or later (Ctrl+Alt+F2): the new configuration starts the Noctalia greeter on tty1 the
# moment it is activated. From tty1 the script builds with `nixos-rebuild boot` instead and asks you to
# reboot; afterwards finish with `sudo ~/nixos-config/install.sh --skip-build` from a terminal.
#
# What it does, in order:
#   1. copies the repository to ~<user>/nixos-config, owned by the user (the path home/home.nix links the
#      dotfiles from), and makes sure it is a git repository with everything staged (flakes only see
#      files known to git)
#   2. writes vars.nix with the user and the hostname you choose
#   3. generates the hardware configuration for this machine and lets you compare it with the one in host/
#      (mount points, disk UUIDs, kernel modules) before building
#   4. `nixos-rebuild switch --flake ~<user>/nixos-config#<hostname>` (flakes are enabled for this run
#      even if the fresh install has not enabled them yet). The configuration itself puts the user in
#      wheel (sudo), networkmanager, video, input, kvm, libvirtd and wireshark; the script checks that
#      afterwards
#   5. one-time user setup that cannot be declared in Nix, run as the user: zinit plugins, Neovim plugins +
#      Mason tools, rustup toolchain, the vibium CLI, the nix-index database, optional LibreWolf profile
#
# Options:
#   --user NAME             the user to set up (default: the user who ran sudo)
#   --hostname NAME         hostname for this machine (default: the current one, asked for interactively)
#   -y, --yes               answer yes to every question (non-interactive; never reboots by itself)
#   --reboot                reboot when done without asking
#   --boot                  `nixos-rebuild boot` instead of `switch` (activate on next reboot)
#   --librewolf DIR         copy an old ~/.config/librewolf profile directory into place
#   --use-generated-hw      take the generated hardware-configuration.nix without asking
#   --skip-build            skip the nixos-rebuild (useful to re-run the user setup)
#   --skip-user-setup       skip the user setup
#   --skip-nix-index        do not build the nix-index database (takes several minutes)
#   -h, --help              this text

set -euo pipefail

SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-}"
HOST=""

YES=0
REBOOT=0
BUILD_ACTION="switch"
LIBREWOLF_PROFILE=""
USE_GENERATED_HW=0
SKIP_BUILD=0
SKIP_USER_SETUP=0
SKIP_NIX_INDEX=0
USER_SETUP_LATER=0

# groups the configuration gives the user (host/configuration.nix); checked after activation
EXPECTED_GROUPS="wheel networkmanager video input kvm libvirtd wireshark"

# ----------------------------------------------------------------------------- helpers

c_info=$'\033[1;34m' c_ok=$'\033[1;32m' c_warn=$'\033[1;33m' c_err=$'\033[1;31m' c_off=$'\033[0m'
info() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_warn" "$c_off" "$*"; }
die()  { printf '%serror:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

# ask "question" [default y|n] -> 0 for yes
ask() {
  local prompt="$1" default="${2:-n}" answer
  if [ "$YES" = 1 ]; then return 0; fi
  if [ "$default" = y ]; then prompt="$prompt [Y/n] "; else prompt="$prompt [y/N] "; fi
  read -r -p "$prompt" answer || true
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

# flakes + nix-command for every nix/nixos-rebuild call in this script, whatever the system has configured
export NIX_CONFIG="experimental-features = nix-command flakes"

# run a command as the target user, with the user's home and the profiles the new system installs on PATH
as_user() {
  runuser -u "$TARGET_USER" -- env \
    HOME="$USER_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" NIX_CONFIG="$NIX_CONFIG" \
    PATH="/etc/profiles/per-user/$TARGET_USER/bin:/run/current-system/sw/bin:$PATH" \
    "$@"
}

# git as the user (so no root-owned files land in the checkout); a fresh system may not have git yet,
# in which case a temporary one comes from nixpkgs
git_u() {
  if command -v git >/dev/null 2>&1; then
    as_user git -C "$TARGET" "$@"
  else
    as_user nix shell nixpkgs#git -c git -C "$TARGET" "$@"
  fi
}

# ----------------------------------------------------------------------------- arguments

while [ $# -gt 0 ]; do
  case "$1" in
    --user) [ $# -ge 2 ] || die "--user needs a name"; TARGET_USER="$2"; shift ;;
    --hostname) [ $# -ge 2 ] || die "--hostname needs a name"; HOST="$2"; shift ;;
    -y|--yes) YES=1 ;;
    --reboot) REBOOT=1 ;;
    --boot) BUILD_ACTION="boot" ;;
    --librewolf) [ $# -ge 2 ] || die "--librewolf needs a directory"; LIBREWOLF_PROFILE="$2"; shift ;;
    --use-generated-hw) USE_GENERATED_HW=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --skip-user-setup) SKIP_USER_SETUP=1 ;;
    --skip-nix-index) SKIP_NIX_INDEX=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

# ----------------------------------------------------------------------------- preflight

info "Preflight checks"
[ -e /etc/NIXOS ] || die "this is not a NixOS system"
[ "$(id -u)" = 0 ] || die "run this as root: sudo bash $0  (the user is taken from sudo), or --user NAME from a root login"
[ -n "$TARGET_USER" ] || die "no target user: run through sudo, or pass --user NAME"
[ "$TARGET_USER" != root ] || die "the target user must be a normal user, not root (pass --user NAME)"
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist on this system"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -d "$USER_HOME" ] || die "home directory of $TARGET_USER not found ($USER_HOME)"
TARGET="$USER_HOME/nixos-config"
[ -f "$SOURCE/flake.nix" ] || die "no flake.nix next to this script ($SOURCE)"
command -v nix >/dev/null || die "nix not found in PATH"
command -v runuser >/dev/null || die "runuser not found"
ok "NixOS, root, setting up user $TARGET_USER ($USER_HOME)"
if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx wheel; then
  ok "$TARGET_USER is already in wheel (sudo)"
else
  info "$TARGET_USER is not in wheel yet; the configuration adds wheel and the other groups on activation"
fi

# ----------------------------------------------------------------------------- 1. repository

info "Repository at $TARGET"
if [ "$SOURCE" != "$TARGET" ]; then
  if [ -e "$TARGET" ]; then
    warn "$TARGET already exists"
    # never destructive under -y: an existing checkout may hold local edits
    if [ "$YES" = 0 ] && ask "Replace it with the contents of $SOURCE? (deletes $TARGET)" n; then
      rm -rf "$TARGET"
      cp -a "$SOURCE" "$TARGET"
    else
      info "keeping the existing $TARGET (re-run from there to use it: sudo $TARGET/install.sh)"
    fi
  else
    cp -a "$SOURCE" "$TARGET"
  fi
  ok "copied to $TARGET"
else
  ok "already running from $TARGET"
fi
chown -R "$TARGET_USER:" "$TARGET"
chmod +x "$TARGET/install.sh" "$TARGET"/scripts/* 2>/dev/null || true

if [ ! -d "$TARGET/.git" ]; then
  git_u init -q
  ok "initialised git repository"
fi

# ----------------------------------------------------------------------------- 2. names

info "User and host names (vars.nix)"
current_host="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo nixos)"
if [ -z "$HOST" ]; then
  if [ "$YES" = 1 ]; then
    HOST="$current_host"
  else
    read -r -p "Hostname for this machine [$current_host]: " HOST || true
    HOST="${HOST:-$current_host}"
  fi
fi
[[ "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "invalid hostname: $HOST"
cat > "$TARGET/vars.nix" <<EOF
# Machine-specific names, written by install.sh on $(date +%F). Edit by hand if they change.
{
  username = "$TARGET_USER";
  hostname = "$HOST";
}
EOF
chown "$TARGET_USER:" "$TARGET/vars.nix"
ok "user $TARGET_USER, hostname $HOST"
git_u add -A
ok "all files staged (flakes only see files known to git)"

# ----------------------------------------------------------------------------- 3. hardware configuration

info "Hardware configuration"
HW="$TARGET/host/hardware-configuration.nix"
GENERATED="$(mktemp)"
trap 'rm -f "$GENERATED"' EXIT
nixos-generate-config --show-hardware-config > "$GENERATED" 2>/dev/null \
  || die "nixos-generate-config failed"

hw_facts() { grep -E 'fileSystems\.|swapDevices|device =|by-uuid|by-label|fsType|kernelModules' "$1"; }
if diff -q <(hw_facts "$HW") <(hw_facts "$GENERATED") >/dev/null; then
  ok "host/hardware-configuration.nix matches this machine"
else
  warn "host/hardware-configuration.nix differs from what nixos-generate-config produced for this machine:"
  diff -u "$HW" "$GENERATED" | sed 's/^/    /' || true
  if [ "$USE_GENERATED_HW" = 1 ] || ask "Use the generated hardware-configuration.nix? (recommended if the disks changed)" y; then
    cp "$GENERATED" "$HW"
    chown "$TARGET_USER:" "$HW"
    git_u add host/hardware-configuration.nix
    ok "replaced host/hardware-configuration.nix with the generated one"
  else
    warn "keeping the repository's host/hardware-configuration.nix"
  fi
fi

# ----------------------------------------------------------------------------- 4. build

if [ "$SKIP_BUILD" = 0 ]; then
  # The new configuration starts greetd (the Noctalia greeter) on tty1 as soon as it is activated. If this
  # script is running on tty1, a `switch` would paint the greeter over this console mid-run.
  if [ "$BUILD_ACTION" = switch ] && [ "$(tty 2>/dev/null)" = /dev/tty1 ]; then
    warn "running on tty1: the new configuration takes over tty1 with the login screen when activated"
    if [ "$YES" = 1 ] || ! ask "Activate now anyway? (No = build for the next boot and stop; recommended)" n; then
      BUILD_ACTION="boot"
    fi
  fi

  info "Building the configuration ($BUILD_ACTION; this downloads and compiles a lot the first time)"
  nixos-rebuild "$BUILD_ACTION" --flake "$TARGET#$HOST" \
    || die "nixos-rebuild failed; fix the error above and re-run (sudo $TARGET/install.sh --skip-user-setup)"

  if [ "$BUILD_ACTION" = boot ]; then
    ok "configuration $HOST built and set as the default boot entry (not activated yet)"
    SKIP_USER_SETUP=1
    USER_SETUP_LATER=1
  else
    ok "system switched to $HOST"
    hash -r
    # group membership comes from users.users.<name>.extraGroups in host/configuration.nix
    missing=""
    for g in $EXPECTED_GROUPS; do
      id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx "$g" || missing="$missing $g"
    done
    if [ -z "$missing" ]; then
      ok "$TARGET_USER is in: $EXPECTED_GROUPS (wheel = sudo)"
    else
      warn "$TARGET_USER is missing groups:$missing (check users.users.$TARGET_USER in host/configuration.nix)"
    fi
    # a session that was already open keeps its old group list; new logins get the new one
    info "open shells of $TARGET_USER need a new login to pick up the new groups"
  fi
else
  warn "skipping nixos-rebuild (--skip-build)"
fi

# ----------------------------------------------------------------------------- 5. user setup

if [ "$SKIP_USER_SETUP" = 0 ]; then
  info "One-time user setup (as $TARGET_USER)"

  # zsh: zinit clones its plugins and OMZ snippets on the first interactive start
  if [ -f "$USER_HOME/.zshrc" ] && as_user sh -c 'command -v zsh' >/dev/null 2>&1; then
    as_user zsh -i -c 'exit' </dev/null >/dev/null 2>&1 || true
    ok "zinit plugins installed (~/.local/share/zinit)"
  else
    warn "zsh or ~/.zshrc not present yet; plugins will install on the first shell start"
  fi

  # Neovim: lazy.nvim plugins, then the Mason packages from nvim/lua/plugins/mason.lua
  if as_user sh -c 'command -v nvim' >/dev/null 2>&1; then
    as_user nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || warn "lazy.nvim sync reported errors (run :Lazy sync in nvim)"
    as_user nvim --headless "+MasonToolsInstallSync" +qa >/dev/null 2>&1 || warn "Mason install reported errors (run :MasonToolsInstall in nvim)"
    ok "Neovim plugins and Mason tools installed"
  else
    warn "nvim not in PATH; start it once by hand so lazy.nvim and Mason can fetch their packages"
  fi

  # Rust: rust.lua asks rustup for rust-analyzer
  if as_user sh -c 'command -v rustup' >/dev/null 2>&1; then
    if as_user rustup show active-toolchain >/dev/null 2>&1; then
      ok "rustup toolchain already set"
    elif as_user rustup default stable >/dev/null 2>&1; then
      ok "rustup: stable toolchain installed"
    else
      warn "rustup default stable failed; run it later"
    fi
    as_user rustup component add rust-analyzer >/dev/null 2>&1 || true
  fi

  # npm globals (prefix ~/.local, see home/dev.nix): the vibium CLI for the Claude Code browser/check skills
  if as_user sh -c 'command -v npm' >/dev/null 2>&1; then
    if [ -x "$USER_HOME/.local/bin/vibium" ]; then
      ok "vibium already installed"
    elif as_user env NPM_CONFIG_PREFIX="$USER_HOME/.local" npm install -g vibium >/dev/null 2>&1; then
      ok "vibium installed (npm -g, ~/.local/bin)"
    else
      warn "npm install -g vibium failed; run it later"
    fi
  fi

  # Pictures/Screenshots for hyprshot (xdg user dirs are created by Home Manager on activation)
  as_user mkdir -p "$USER_HOME/Pictures/Screenshots"

  # LibreWolf profile from the old machine
  if [ -n "$LIBREWOLF_PROFILE" ]; then
    if [ -e "$USER_HOME/.config/librewolf" ]; then
      warn "$USER_HOME/.config/librewolf exists; not overwriting it with $LIBREWOLF_PROFILE"
    elif [ -d "$LIBREWOLF_PROFILE" ]; then
      mkdir -p "$USER_HOME/.config"
      cp -a "$LIBREWOLF_PROFILE" "$USER_HOME/.config/librewolf"
      rm -f "$USER_HOME/.config/librewolf"/librewolf/*/.parentlock "$USER_HOME/.config/librewolf"/librewolf/*/lock 2>/dev/null || true
      chown -R "$TARGET_USER:" "$USER_HOME/.config/librewolf"
      ok "LibreWolf profile copied to ~/.config/librewolf"
    else
      warn "$LIBREWOLF_PROFILE is not a directory; LibreWolf profile not imported"
    fi
  fi

  # command-not-found database for the shell (programs.nix-index)
  if [ "$SKIP_NIX_INDEX" = 0 ] && as_user sh -c 'command -v nix-index' >/dev/null 2>&1; then
    if ask "Build the nix-index database now? (command-not-found suggestions; takes a few minutes)" y; then
      if as_user nix-index >/dev/null 2>&1; then
        ok "nix-index database built"
      else
        warn "nix-index failed; run it again later"
      fi
    fi
  fi
elif [ "$USER_SETUP_LATER" = 1 ]; then
  warn "user setup postponed: after rebooting and logging in, open a terminal and run: sudo $TARGET/install.sh --skip-build"
else
  warn "skipping user setup (--skip-user-setup)"
fi

# ----------------------------------------------------------------------------- done

cat <<EOF

${c_ok}Done.${c_off}

  Configuration:   $TARGET  (rebuild with: nixos-rebuild switch --sudo --flake $TARGET, the 'rebuild' alias, or nixos-update)
  Names:           user $TARGET_USER, host $HOST (vars.nix)
  Groups:          $EXPECTED_GROUPS (declared in host/configuration.nix; wheel gives sudo)
  Ollama models:   pulled by the ollama-model-loader service in the background
                   (watch with: journalctl -fu ollama-model-loader)
  Claude Code:     MCP servers maestro, playwright-ios and expo are registered; run /mcp inside
                   Claude Code once to sign in to the Expo server (OAuth)
  Obsidian vault:  expected at ~/Obsidian/Personal (copy it from the old machine)
  LibreWolf:       ${LIBREWOLF_PROFILE:-no profile imported; pass --librewolf <old ~/.config/librewolf> to import one}

Reboot to start the Noctalia greeter, keyd and the nvidia driver from the new configuration.
EOF

if [ "$SKIP_BUILD" = 0 ]; then
  if [ "$REBOOT" = 1 ]; then
    reboot
  elif [ "$YES" = 0 ] && ask "Reboot now?" "$([ "$BUILD_ACTION" = boot ] && echo y || echo n)"; then
    reboot
  fi
fi
