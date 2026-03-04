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

# ---- Git aliases ----
info_log "Configuring git aliases via include.path"

git config --global include.path "$DOTFILES_DIR/gitconfig.aliases"
debug_log "Set git include.path = $DOTFILES_DIR/gitconfig.aliases"

# ---- ClickUp CLI dependencies ----
info_log "Installing ClickUp CLI dependencies"

if command -v npm &>/dev/null; then
  (cd "$DOTFILES_DIR/clickup" && npm install --no-fund --no-audit 2>&1)
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
  debug_log "git include.path = $(git config --global --get include.path 2>/dev/null || echo 'NOT SET')"
  debug_log "DOTZSH will resolve to: ${DOTZSH:-$HOME/.dotfiles}"
fi
