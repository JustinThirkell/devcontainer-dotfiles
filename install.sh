#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTFILES_DIR/common.sh"

info_log "Installing dotfiles from $DOTFILES_DIR"
debug_log "HOME=$HOME"
debug_log "USER=${USER:-$(whoami)}"
debug_log "DEBUG_DEVCONTAINER=${DEBUG_DEVCONTAINER:-false}"

# ---- Copy config files into $HOME ----
info_log "Copying config files into \$HOME"

for file in zshrc:.zshrc p10k.zsh:.p10k.zsh ohmyzsh.config:.ohmyzsh.config zshrc.local:.zshrc.local; do
  src="${file%%:*}"
  dst="$HOME/${file##*:}"
  if [[ -f "$DOTFILES_DIR/$src" ]]; then
    cp "$DOTFILES_DIR/$src" "$dst"
    debug_log "Copied $src -> $dst"
  else
    warn_log "Source file not found: $DOTFILES_DIR/$src"
  fi
done

# ---- Claude Code user config ----
# Mirror the ENTIRE dotfiles .claude/ tree into ~/.claude so new files are picked up
# automatically without editing this script -- e.g. CLAUDE.md, workflow-reference.md (the
# deep background trimmed out of CLAUDE.md so it does NOT load into model context every
# turn), a future agents/ dir, output styles, etc.
#
# settings.json here is personal *preferences* only (status line, effortLevel,
# skillOverrides, ...).  Sandbox *policy* (bypassPermissions, the rtk hook, connectors
# disabled) is machine-scoped and baked into the image at
# /etc/claude-code/managed-settings.json -- do NOT duplicate policy in dotfiles.  Claude
# Code deep-merges the managed (machine) and user scopes.
info_log "Installing Claude Code user config"

CLAUDE_SRC_DIR="$DOTFILES_DIR/.claude"
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

if [[ -d "$CLAUDE_SRC_DIR" ]]; then
  # Trailing "/." copies the directory's *contents* (recursively, via -a) into ~/.claude,
  # overwriting only the files present in dotfiles -- runtime state (.credentials.json,
  # history, memory, settings.local.json) is left untouched because it isn't in the source.
  cp -a "$CLAUDE_SRC_DIR/." "$CLAUDE_DIR/"
  debug_log "Copied $CLAUDE_SRC_DIR/ -> $CLAUDE_DIR/"
  if [ "${DEBUG:-false}" = "true" ]; then
    find "$CLAUDE_SRC_DIR" -type f -printf '%P\n' | while read -r rel; do
      debug_log "  .claude/$rel -> $CLAUDE_DIR/$rel"
    done
  fi
else
  warn_log "Source dir not found: $CLAUDE_SRC_DIR"
fi

# ---- Git aliases ----
info_log "Configuring git aliases via include.path"

ALIAS_PATH="$DOTFILES_DIR/gitconfig.aliases"
# Log existing include.path entries for debugging
debug_log "Existing include.path entries:"
git config --global --get-all include.path 2>/dev/null | while read -r p; do debug_log "  $p"; done || debug_log "  (none)"
# Add our aliases path if not already included (--add avoids overwriting existing entries)
if ! git config --global --get-all include.path 2>/dev/null | grep -qxF "$ALIAS_PATH"; then
  git config --global --add include.path "$ALIAS_PATH"
  debug_log "Added git include.path = $ALIAS_PATH"
else
  debug_log "git include.path already contains $ALIAS_PATH, skipping"
fi

# ---- ClickUp CLI dependencies ----
info_log "Installing ClickUp CLI dependencies"

if command -v npm &>/dev/null; then
  cd "$DOTFILES_DIR/clickup" && npm install --no-fund --no-audit
  cd "$DOTFILES_DIR"
  info_log "ClickUp CLI dependencies installed"
else
  warn_log "npm not found -- skipping ClickUp CLI dependency install"
  warn_log "ClickUp/CP workflow functions will not work without Node.js"
fi

# ---- Summary ----
info_log "Dotfiles installed successfully"

if [ "${DEBUG:-false}" = "true" ]; then
  debug_log "--- Installed config files ---"
  for f in ~/.zshrc ~/.p10k.zsh ~/.ohmyzsh.config ~/.zshrc.local; do
    if [[ -f "$f" ]]; then
      debug_log "  $f ($(wc -c < "$f") bytes)"
    else
      debug_log "  $f MISSING"
    fi
  done
  if [[ -d "$CLAUDE_SRC_DIR" ]]; then
    find "$CLAUDE_SRC_DIR" -type f -printf '%P\n' | while read -r rel; do
      f="$CLAUDE_DIR/$rel"
      if [[ -f "$f" ]]; then
        debug_log "  $f ($(wc -c < "$f") bytes)"
      else
        debug_log "  $f MISSING"
      fi
    done
  fi
  debug_log "git include.path = $(git config --global --get include.path 2>/dev/null || echo 'NOT SET')"
  debug_log "DOTZSH will resolve to: ${DOTZSH:-$HOME/dotfiles}"
fi
