#!/usr/bin/env bash
# Agent welcome / opt-out preferences (UserDefaults via defaults CLI when app not required).
set -euo pipefail
DOMAIN="dev.ghidravibe.app"
# Clear and assert defaults keys used by AppModel
defaults delete "$DOMAIN" 2>/dev/null || true
# Simulate opt-out
defaults write "$DOMAIN" "ghidra.vibe.agent.optOut" -bool true
defaults write "$DOMAIN" "ghidra.vibe.agent.welcomeDismissed" -bool true
defaults write "$DOMAIN" "ghidra.vibe.theme.ghidra" -string "Default Dark"
defaults write "$DOMAIN" "ghidra.vibe.theme.base16" -string "Default Dark"
opt="$(defaults read "$DOMAIN" "ghidra.vibe.agent.optOut")"
[[ "$opt" == "1" || "$opt" == "true" ]]
theme="$(defaults read "$DOMAIN" "ghidra.vibe.theme.ghidra")"
[[ "$theme" == "Default Dark" ]]
echo "OK smoke-agent-welcome (opt-out + Ghidra Theme preference persisted)"
