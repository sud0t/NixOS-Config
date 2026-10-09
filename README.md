# NixOS + Home Manager

Hyprland (Lua config), Noctalia, kitty, zsh with powerlevel10k, AstroNvim, Claude Code. The user and host
names are not baked in: they live in `vars.nix`, which `install.sh` writes from the running system.

```
flake.nix                      inputs: nixpkgs (unstable), home-manager, noctalia (5.x), skill repos; output named after the hostname
vars.nix                       { username, hostname } — written by install.sh, or edit by hand
install.sh                     fresh-install setup script (see Install)
host/
  configuration.nix            boot, users, locale, nix settings, nix-ld, laptop optimisations
  hardware-configuration.nix   disks (UUIDs from this laptop) and firmware
modules/nixos/
  desktop.nix                  hyprland, greetd + noctalia-greeter, pipewire, portals, keyd, fonts, qt
  services.nix                 networkmanager, bluetooth, power-profiles-daemon, libvirtd, wireshark, ollama
  nvidia.nix                   intel + nvidia PRIME offload, VA-API
home/
  home.nix                     user, xdg dirs, one-time seeding of runtime-written files
  zsh.nix                      the .zshrc with p10k/zinit from nixpkgs
  hyprland.nix                 ~/.config/hypr links, hyprland-session.target, hypr tools
  desktop.nix                  kitty, fastfetch, nemo, noctalia, polkit agent, udiskie, wallpapers, helper commands
  nvim.nix                     neovim + every tool the AstroNvim config uses
  dev.nix                      node/npm, pnpm, yarn, TypeScript + language servers, prettier/eslint, rustup, go
  apps.nix                     Slack, Notion, Claude Code, Librewolf, Google Chrome, Obsidian
  claude.nix                   ~/.claude: skills from flake inputs, MCP servers, status line, seeded settings.json
scripts/                       p10reload.sh, nixos-update, claude-statusline (installed as commands on PATH)
dotfiles/                      hypr kitty nvim fastfetch noctalia noctalia-state obsidian wallpapers zsh
```

## Install

As root, for the user who will own the desktop, on a fresh NixOS install (from a USB stick, a clone, anywhere):

```sh
sudo bash /path/to/nixos-config/install.sh                      # user taken from sudo; asks for the hostname
sudo bash /path/to/nixos-config/install.sh -y --hostname mybox --librewolf /path/to/old/.config/librewolf
bash /path/to/nixos-config/install.sh --user alice               # from a root login
```

Run it from **tty2 or later** (Ctrl+Alt+F2, log in there): the new configuration starts the Noctalia
greeter on tty1 the moment it is activated. From tty1 the script builds with `nixos-rebuild boot` instead,
asks you to reboot, and you finish with `sudo ~/nixos-config/install.sh --skip-build` from a terminal in
the new session.

`install.sh` copies the repository to `~/nixos-config` owned by the user, writes `vars.nix` with the user
name and the chosen hostname, stages everything in git (as the user), compares the hardware configuration
with this machine's (mount points, UUIDs, kernel modules), runs `nixos-rebuild switch --flake
~/nixos-config#<hostname>` (flakes are enabled for the run), checks that the user ended up in `wheel` (sudo),
`networkmanager`, `video`, `input`, `kvm`, `libvirtd` and `wireshark` as `host/configuration.nix` declares,
then runs the user setup as the user: zinit plugins, Neovim plugins and Mason tools, the rustup toolchain,
the vibium CLI, the nix-index database, and optionally an old LibreWolf profile. `--help` lists the
options; `--skip-build` re-runs only the user setup; `--boot` builds for the next reboot; `-y` never
reboots on its own (add `--reboot`). Reboot afterwards.

The same steps by hand:

1. Install NixOS, then put this directory at **`~/nixos-config`** (it is a git repository with everything
   staged; keep it one, since a flake in a plain directory is copied to the Nix store on every rebuild).
   The path is hard-wired: `home/home.nix` links `~/.config/{hypr,kitty,nvim,fastfetch}` into
   `~/nixos-config/dotfiles` so those configs stay editable in place.
2. Set `username` and `hostname` in `vars.nix` (`username` must match the user running Home Manager; an
   empty `hostname` means `nixos`). `git add vars.nix`.
3. Compare `host/hardware-configuration.nix` with `sudo nixos-generate-config --show-hardware-config`
   and replace it if the disks changed.
4. Build:

   ```sh
   sudo nixos-rebuild switch --flake ~/nixos-config#<hostname>
   ```

   Once the system hostname matches `vars.nix`, plain `--flake ~/nixos-config` (or the `rebuild` alias, or
   the `nixos-update` command, which also updates the flake inputs) works.
5. First login: run `nix-index` once (command-not-found database), start `nvim` once so lazy.nvim and
   Mason fetch their plugins, and run `rustup default stable` for the Rust tooling.
6. Browser profile: copy an old `~/.config/librewolf` into place before the first LibreWolf start if you
   want its history, extensions and logins back.

## How the configs are wired

| Dotfiles                          | On NixOS                            | Method                                            |
| --------------------------------- | ----------------------------------- | ------------------------------------------------- |
| `hypr/`                           | `~/.config/hypr/*`                  | out-of-store symlinks (edit in place); `.luarc.json` generated with the Hyprland Lua stubs; `noctalia.lua` copied once (Noctalia rewrites it) |
| `kitty/`                          | `~/.config/kitty`                   | out-of-store symlink                              |
| `nvim/`                           | `~/.config/nvim`                    | out-of-store symlink (lazy-lock.json stays live)  |
| `fastfetch/`                      | `~/.config/fastfetch`               | out-of-store symlink                              |
| `noctalia/`                       | `~/.config/noctalia`                | copied once (colour templates)                    |
| `noctalia-state/settings.toml`    | `~/.local/state/noctalia/settings.toml` | copied once, home path filled in (bar, theme, lock screen, wallpaper dir, 13 starred wallpapers) |
| `noctalia-state/state.toml`       | `~/.local/state/noctalia/state.toml`| copied once                                       |
| flake input (community-plugins)   | `~/.local/share/noctalia/plugins/nix-monitor` | store symlink (Noctalia's local plugin source) |
| `wallpapers/` (13 starred)        | `~/Pictures/Wallpapers/<file>`      | out-of-store symlinks; the directory stays writable for more |
| generated                         | `~/.config/obsidian/obsidian.json`  | copied once (vault list: `~/Obsidian/Personal`)   |
| `obsidian/Custom Dictionary.txt`  | `~/.config/obsidian/…`              | copied once                                       |
| `zsh/.zshrc`                      | `~/.zshrc`                          | Home Manager `programs.zsh` (store paths filled)  |
| `zsh/.p10k.zsh`                   | `~/.p10k.zsh`                       | copied once (Noctalia regenerates it)             |

"Copied once" files are only created if missing, so later changes made by the applications are never
overwritten by a rebuild. The helper scripts in `scripts/` are installed as commands, so the Noctalia
configuration calls `p10reload.sh` by bare name and nothing depends on the home directory's path.

## How the session is put together

* **`hypr/configs/autostart.lua`** does not start daemons. PipeWire, the xdg portals, the polkit agent,
  Noctalia, udiskie and Ollama are systemd units:
  * pipewire → `services.pipewire`; portals → `xdg.portal` (D-Bus activated);
  * hyprpolkitagent, noctalia, udiskie → user services bound to `graphical-session.target`;
  * ollama → `services.ollama` (system service) with the `OLLAMA_*` environment the Neovim plugins expect;
  * the hook only exports the session environment, starts `hyprland-session.target`, runs
    `brightnessctl set 100%` and `snappy-switcher --daemon`.
* Login: greetd with the Noctalia greeter. Keyboard: keyd (`rightshift → leftmeta`,
  `capslock → overload(control, esc)`). Networking, bluetooth, power-profiles-daemon, libvirtd and
  timesyncd are enabled in `modules/nixos/services.nix`.
* `.zshrc`: powerlevel10k and zinit are sourced from nixpkgs (plugins still install into
  `~/.local/share/zinit`); a `rebuild` alias runs `nixos-rebuild switch --sudo --flake ~/nixos-config`
  (built as you, sudo only for the activation).
* `hypr/.luarc.json` is generated by Home Manager with the installed Hyprland's Lua stubs.
* `QT_QPA_PLATFORMTHEME=qt6ct` works because the NixOS `qt` module puts the Qt plugin directories on
  `QT_PLUGIN_PATH`; without it no Qt app could load the qt6ct platform theme.
* `kitty/kitty.conf` holds only the active settings.

## Claude Code

`home/claude.nix` manages `~/.claude`:

* **Skills** are flake inputs (`flake = false`) linked to `~/.claude/skills/<name>`:
  * [dickwu/apple-design-skill](https://github.com/dickwu/apple-design-skill) → `apple-design`
  * [ContextJet-ai/awesome-llm-observability](https://github.com/ContextJet-ai/awesome-llm-observability) → its
    26 `skills/*` (evals, guardrails, tracing, cost, ...)
  * [jmr85/e2e-agent-skills](https://github.com/jmr85/e2e-agent-skills) → `playwright-automation-expert`,
    `playwright-cucumber-expert`, `selenium-cucumber-expert`, `appium-python-expert`
  * [VibiumDev/vibium](https://github.com/VibiumDev/vibium) → `browser`, `check`; they drive the `vibium`
    CLI, which is an npm package (`install.sh` runs `npm install -g vibium` into `~/.local`)
  * [anthropics/skills](https://github.com/anthropics/skills) → only `webapp-testing` (Python Playwright
    testing of local web apps; the rest of that repo is the anthropic-skills plugin)

  A repository with `SKILL.md` at its root goes in `singleSkills` (a sub-path works too), one with
  `skills/<name>/` in `skillCollections` (every skill directory is linked automatically). `nix flake update`
  pulls newer versions.
* **MCP servers** (user scope, merged into `~/.claude.json` on every activation; entries added with
  `claude mcp add` under other names are kept):
  * `maestro` → `maestro mcp` (nixpkgs `maestro`): inspect a connected device/emulator, write and run flows.
  * `playwright-ios` → nixpkgs `playwright-mcp` on WebKit with the "iPhone 15" device profile, so a web
    app can be driven with iOS Safari's viewport, touch events and user agent on Linux.
  * `expo` → `https://mcp.expo.dev/mcp` (remote, OAuth): EAS builds and workflows. Run `/mcp` in Claude
    Code once to sign in. `eas-cli` is installed for the same from the terminal.
* **Playwright on NixOS**: downloaded browsers do not run here, so `PLAYWRIGHT_BROWSERS_PATH` points at
  nixpkgs' prebuilt chromium/firefox/webkit (`home/dev.nix`). Projects should pin the `playwright`
  npm package to the version nixpkgs ships (`playwright-mcp` and the Python package already match).
* **Status line** (`scripts/claude-statusline`, installed as the `claude-statusline` command): model,
  context window (bar, %, tokens), 5-hour and 7-day usage percentages, and when each window resets
  (clock time plus countdown). Colour turns yellow at 50 % and red at 80 %. It re-runs every minute so
  the countdowns stay current. Usage fields come from Claude Code's `rate_limits` data, which exists for
  claude.ai Pro/Max sessions after the first response; until then they show "—".
* **Caveman** ([JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman), pinned flake input):
  terse output mode, on from the first message of every interactive session. Its own session hooks do
  the switching, run straight from the pinned source (no plugin marketplace, no self-updates):
  `SessionStart` prints the ruleset as session context, `SubagentStart` hands it to subagents,
  `UserPromptSubmit` tracks mode changes. Say `stop caveman` or `normal mode` to turn it off for a
  session, `/caveman ultra` for the extreme variant. The default mode lives in
  `~/.config/caveman/config.json` (`"caveman"`; set `"off"` to disable by default). The hooks need
  `node` (installed) and write only small flag files under `~/.claude`. Headless `claude -p` sessions
  are left in normal mode by the hook itself.
* **settings.json** is seeded once (auto permission mode, Fable at high effort, dark theme, vim editor
  mode). Claude Code keeps writing to it as usual; only the `statusLine` key and the caveman `hooks`
  events are re-applied on every activation.

## Development toolchains

`home/dev.nix`: Node.js (node, npm, npx, corepack), pnpm, yarn, TypeScript (`tsc`), the
`typescript-language-server` and `vtsls` servers the Neovim TypeScript pack uses, prettier, eslint, rustup
(`install.sh` sets the stable toolchain and adds rust-analyzer), pkg-config, Go. React projects are started
per project (`npm create vite@latest` with the `react-ts` template); nothing React-specific is global.
`npm install -g` uses the prefix `~/.local`, so global npm binaries land in `~/.local/bin`, which the
`.zshrc` already puts on PATH.

## Audio

PipeWire + WirePlumber are declared in `modules/nixos/desktop.nix` (`services.pipewire`: ALSA incl.
32-bit, PulseAudio compatibility, JACK, WirePlumber) with rtkit for realtime priority. They start as
socket-activated systemd user units at login. WirePlumber gets a Bluetooth profile (SBC-XQ, mSBC, hardware
volume, HFP roles) and BlueZ runs with `Experimental = true` so Noctalia can show device battery levels.
`wpctl`, `pw-top`, `alsamixer` and `pwvucontrol` are installed for checking things; `playerctl` is there
for the media-key binds if you uncomment them. VA-API hardware video decoding on the Intel GPU is enabled
in `modules/nixos/nvidia.nix` (`intel-media-driver`, `LIBVA_DRIVER_NAME=iHD`).

## Optimisations

Standard NixOS laptop settings; none change how the desktop behaves.

* **Boot/power:** zram swap (25 % of RAM, disk swap stays as fallback), weekly `fstrim`, `thermald`,
  `fwupd`, journal capped at 500 MB / one month, GRUB menu limited to 20 generations.
* **nvidia:** `powerManagement.enable` (suspend/resume services, preserved video memory). Runtime D3 stays
  off on purpose: Hyprland keeps the nvidia DRM device open.
* **Nix:** weekly store optimisation and GC, `warn-dirty = false` (the repo is an uncommitted git tree by
  design), `fallback` + `log-lines`, the system's nixpkgs registered as `nixpkgs` so `nix shell nixpkgs#…`
  and `nix-shell -p` reuse it instead of downloading another one, NixOS manual build skipped.
* **Desktop:** `NIXOS_OZONE_WL=1` so Slack/Obsidian/Notion/Chrome run on Wayland rather than XWayland
  (same intent as the `ELECTRON_OZONE_PLATFORM_HINT` already in `environment.lua`), dbus-broker,
  Noto + emoji fallback fonts, Home Manager restarts changed user services on activation.
* **Media:** PipeWire/WirePlumber Bluetooth codec profile, BlueZ experimental features (battery levels),
  VA-API on the Intel GPU.

## Things to know

* **Notion**: nixpkgs' only Linux Notion desktop client is `notion-app-enhanced` (Notion repackaged with the
  notion-enhancer). If you'd rather use the web app, drop it and use Chrome.
* **Ollama models** live in `/var/lib/ollama/models`; `services.ollama.loadModels` pulls `qwen2.5-coder:7b`,
  `qwen2.5-coder:1.5b-base`, `qwen3:4b-instruct` and `llama3.1:8b` on first start. The package is
  `ollama-vulkan`; `ollama-cuda` is the alternative (long local build).
* **Mason** binaries run through `programs.nix-ld`. The same language servers/formatters are installed from
  nixpkgs too, so Neovim works even if a Mason download fails.
* **`GTK_THEME=Nord`** in `environment.lua` names a theme that is not installed; GTK falls back to the
  default. Add `pkgs.nordic` and change the value to `Nordic` if you want it.
* **`snappy-switcher`** is not packaged in nixpkgs; the autostart line fails silently and the `ALT+TAB`
  binds use Noctalia's window switcher anyway.
* **GPU numbering**: `AQ_DRM_DEVICES=/dev/dri/card0:/dev/dri/card1` assumes the Intel GPU is `card0`.
  Check `ls -l /dev/dri/by-path` after the first boot and swap the order if Hyprland comes up on the nvidia card.
* **Maestro** needs a target: `adb` for Android, or a real/cloud iOS device. Nothing on Linux provides an
  iOS Simulator.
* **Noctalia nix-monitor plugin** (bar widget next to the tray): compares the running nixpkgs revision
  (`nixos-version --hash`) with the tip of `nixos-unstable` (`git ls-remote` against GitHub, hourly), shows
  NixOS and Home Manager generation counts plus store/closure size, and its Update button runs
  `nixos-update` in a terminal. The plugin code comes from the `noctalia-community-plugins` flake input
  (reviewed: no sudo, no network beyond that `git ls-remote`, only reads plus files under its own state
  directory); Noctalia's background plugin updates are off (`auto_update = "none"`), so `nix flake update`
  is the only way its code changes. The Clean button runs `nix-collect-garbage -d` as your user, which
  deletes old Home Manager generations: hide it with `hide_clean_button` if you'd rather not have that one
  click away.
