# Claude Code: ~/.claude managed by Home Manager.
#   * skills   -> ~/.claude/skills/<name> are symlinks into pinned flake inputs (updated with `nix flake update`)
#   * MCP servers -> user-scope entries in ~/.claude.json (what `claude mcp add --scope user` writes), merged
#                 on every activation; the CLIs they run come from nixpkgs
#   * hooks    -> Caveman's session hooks (terse output mode, on from the first message of every session)
#   * status line -> the `claude-statusline` command (scripts/claude-statusline): model, context window,
#                 5-hour and 7-day usage with their reset times, refreshed every minute
#   * settings.json -> seeded once with the initial settings below; afterwards Claude Code owns
#                 the file (it writes to it from /config, /model, permission prompts, ...) and only the
#                 statusLine and hooks keys are re-applied on every activation
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  statusline = pkgs.writeScriptBin "claude-statusline" (builtins.readFile ../scripts/claude-statusline);

  statusLine = {
    type = "command";
    command = "claude-statusline";
    padding = 0;
    refreshInterval = 60; # the reset countdowns are time based
  };

  # --- Caveman: terse output, on by default --------------------------------------------------------
  # The caveman plugin turns itself on through a SessionStart hook that prints the skill's ruleset as
  # session context, so every session starts in caveman mode without typing /caveman. The same hook
  # scripts run here straight from the pinned flake input (no plugin marketplace, no self-updates):
  #   SessionStart     caveman-activate.js   emits the ruleset, records this session's mode
  #   SubagentStart    caveman-activate.js --subagent   hands the mode to subagents
  #   UserPromptSubmit caveman-mode-tracker.js   tracks "stop caveman" / "normal mode" / /caveman ultra
  # The scripts only read the repo and write small flag files under ~/.claude; nothing leaves the machine.
  # The default mode is read from ~/.config/caveman/config.json (seeded below; the hook ignores symlinked
  # config files, so it has to be a real file). Headless `claude -p` sessions stay in normal mode.
  caveman = inputs.caveman;
  cavemanHook =
    script: extraArgs: message: {
      type = "command";
      command = "command -v node >/dev/null 2>&1 || exit 0; CLAUDE_PLUGIN_ROOT=${caveman} exec node ${caveman}/src/hooks/${script} ${extraArgs}";
      timeout = 30;
      statusMessage = message;
    };
  hooks = {
    SessionStart = [ { hooks = [ (cavemanHook "caveman-activate.js" "" "Loading caveman mode...") ]; } ];
    SubagentStart = [
      { hooks = [ (cavemanHook "caveman-activate.js" "--subagent" "Loading caveman mode for subagent...") ]; }
    ];
    UserPromptSubmit = [ { hooks = [ (cavemanHook "caveman-mode-tracker.js" "" "Tracking caveman mode...") ]; } ];
  };
  cavemanConfig = pkgs.writeText "caveman-config.json" (builtins.toJSON { defaultMode = "caveman"; });

  # initial ~/.claude/settings.json, plus the status line and hooks
  settingsSeed = pkgs.writeText "claude-settings.json" (
    builtins.toJSON {
      permissions = {
        defaultMode = "auto";
        blockReadsOutsideWorkingDirectories = true;
      };
      model = "fable";
      modelSettings."claude-fable-5-1".effortLevel = "high";
      theme = "dark";
      editorMode = "vim";
      switchModelsOnFlag = true;
      autoContinueAtUsageLimit = true;
      inherit statusLine hooks;
    }
  );

  settingsPath = "${config.home.homeDirectory}/.claude/settings.json";
  claudeJsonPath = "${config.home.homeDirectory}/.claude.json";

  # --- MCP servers (user scope) ---------------------------------------------------------------------
  mcpServers = {
    # Maestro: inspects the live device/simulator, writes and runs YAML flows (`maestro mcp` ships in the CLI)
    maestro = {
      type = "stdio";
      command = "maestro";
      args = [ "mcp" ];
    };
    # Playwright on WebKit with an iPhone device profile: viewport, touch and user agent of iOS Safari,
    # runnable on Linux. nixpkgs' playwright-mcp is wrapped with matching browsers; the host override is
    # what the nixpkgs WebKit build asks for.
    playwright-ios = {
      type = "stdio";
      command = "playwright-mcp";
      args = [
        "--browser"
        "webkit"
        "--device"
        "iPhone 15"
      ];
      env.PLAYWRIGHT_HOST_PLATFORM_OVERRIDE = "ubuntu-24.04";
    };
    # Expo: EAS builds and workflows (list, run, logs, cancel, submit). Remote server with OAuth:
    # run /mcp in Claude Code once to sign in with the Expo account.
    expo = {
      type = "http";
      url = "https://mcp.expo.dev/mcp";
    };
  };

  # --- skills -------------------------------------------------------------------------------------
  # Repositories with a single SKILL.md at their root (or a sub-path): linked as ~/.claude/skills/<name>
  singleSkills = {
    apple-design = inputs.apple-design-skill;
    # Anthropic's Playwright-based local web app testing skill (server lifecycle helper, screenshots,
    # console logs); the rest of that repository is already available as the anthropic-skills plugin
    webapp-testing = "${inputs.anthropic-skills}/skills/webapp-testing";
    # Caveman's voice skills: /caveman (normal), /caveman ultra -> ultracave, /caveman wenyan -> megacave
    caveman = "${caveman}/skills/caveman";
    ultracave = "${caveman}/skills/ultracave";
    megacave = "${caveman}/skills/megacave";
  };

  # Repositories with skills/<name>/SKILL.md: every skill directory is linked under its own name
  skillCollections = [
    inputs.awesome-llm-observability # add-llm-evals, debug-agent-from-traces, estimate-llm-cost, ...
    inputs.e2e-agent-skills # playwright-automation-expert, playwright-cucumber-expert, selenium-cucumber-expert, appium-python-expert
    inputs.vibium # browser, check (both drive the vibium CLI)
  ];

  skillsOf =
    repo:
    lib.mapAttrs' (
      name: _: lib.nameValuePair ".claude/skills/${name}" { source = "${repo}/skills/${name}"; }
    ) (lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${repo}/skills"));

  skillFiles =
    lib.mapAttrs' (name: repo: lib.nameValuePair ".claude/skills/${name}" { source = repo; }) singleSkills
    // lib.foldl' (acc: repo: acc // skillsOf repo) { } skillCollections;

  jq = "${pkgs.jq}/bin/jq";
in
{
  home.packages = [
    statusline
    pkgs.jq # used by the status line
    pkgs.nodejs # runs the caveman hooks (also in dev.nix)

    # CLIs behind the MCP servers and skills
    pkgs.maestro # Maestro MCP (`maestro mcp`), flows, device studio; needs adb / a connected device
    pkgs.playwright-mcp # Playwright MCP, wrapped with nixpkgs' browsers (chromium, firefox, webkit)
    pkgs.eas-cli # EAS builds/submit from the terminal; the Expo MCP server covers the same from Claude
  ];

  home.file = skillFiles;

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="${settingsPath}"
    if [ ! -e "$settings" ]; then
      run mkdir -p "$(dirname "$settings")"
      run cp --no-preserve=mode "${settingsSeed}" "$settings"
    else
      # keep every key Claude Code wrote itself; (re)apply the status line and the caveman hook events
      # (hook events with other names, e.g. ones you add by hand, are kept)
      tmp=$(mktemp)
      if ${jq} --argjson sl '${builtins.toJSON statusLine}' --argjson hooks '${builtins.toJSON hooks}' \
           '.statusLine = $sl | .hooks = ((.hooks // {}) + $hooks)' "$settings" > "$tmp"; then
        if ! cmp -s "$tmp" "$settings"; then
          run cp --no-preserve=mode "$tmp" "$settings"
        fi
      fi
      rm -f "$tmp"
    fi

    # caveman: default mode (real file, see above) and the one-shot "set up my statusline" nudge marker,
    # pre-set because the status line here is our own
    cfg="${config.xdg.configHome}/caveman/config.json"
    if [ ! -e "$cfg" ]; then
      run mkdir -p "$(dirname "$cfg")"
      run cp --no-preserve=mode "${cavemanConfig}" "$cfg"
    fi
    nudge="${config.home.homeDirectory}/.claude/.caveman-nudge-shown"
    [ -e "$nudge" ] || run sh -c "echo 1 > '$nudge'"

    # user-scope MCP servers live in ~/.claude.json next to Claude Code's own state: merge the declared
    # servers over whatever is there (servers added with `claude mcp add` under other names are kept)
    claudejson="${claudeJsonPath}"
    [ -e "$claudejson" ] || { run mkdir -p "$(dirname "$claudejson")"; echo '{}' > "$claudejson"; }
    tmp=$(mktemp)
    if ${jq} --argjson servers '${builtins.toJSON mcpServers}' \
         '.mcpServers = ((.mcpServers // {}) + $servers)' "$claudejson" > "$tmp"; then
      if ! cmp -s "$tmp" "$claudejson"; then
        run cp --no-preserve=mode "$tmp" "$claudejson"
      fi
    fi
    rm -f "$tmp"
  '';
}
