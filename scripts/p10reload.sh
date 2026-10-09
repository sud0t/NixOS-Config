#!/usr/bin/env bash
# post_hook of the Noctalia p10k colour template (noctalia/user-templates.toml, noctalia/config.toml):
# makes every running zsh re-read ~/.p10k.zsh.

killall -USR1 zsh 2>/dev/null
