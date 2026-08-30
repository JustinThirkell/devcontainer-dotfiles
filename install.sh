#!/bin/bash
set -euo pipefail

# ---- Logging ----------------------------------------------------------------
# Inlined from the old common.sh: this script was its only consumer once the workflow
# tooling moved to Carepatron-App, so the root now holds one machinery file, not two.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  COLOR_DEBUG='\033[0;90m'
  COLOR_INFO='\033[0;32m'
  COLOR_WARN='\033[0;33m'
  COLOR_ERROR='\033[0;31m'
  COLOR_RESET='\033[0m'
else
  COLOR_DEBUG='' COLOR_INFO='' COLOR_WARN='' COLOR_ERROR='' COLOR_RESET=''
fi

# Single source of truth: set DEVCONTAINER_DEBUG=true to enable debug logging.
DEBUG=${DEVCONTAINER_DEBUG:-false}

# %s for the message rather than `echo -e`, so a backslash in a path is never eaten.
_log() { printf '%b[%s] [dotfiles]%b %s\n' "$1" "$2" "$COLOR_RESET" "${*:3}" >&2; }

# `|| return 0` first, so a debug_log call is never the failing command under `set -e`.
debug_log() { [ "$DEBUG" = "true" ] || return 0; _log "$COLOR_DEBUG" DEBUG "$@"; }
info_log()  { _log "$COLOR_INFO"  INFO  "$@"; }
warn_log()  { _log "$COLOR_WARN"  WARN  "$@"; }
error_log() { _log "$COLOR_ERROR" ERROR "$@"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info_log "Installing dotfiles from $DOTFILES_DIR"
debug_log "HOME=$HOME"
debug_log "USER=${USER:-$(whoami)}"
debug_log "DEVCONTAINER_DEBUG=${DEVCONTAINER_DEBUG:-false}"

# Everything this script installs, for the debug summary at the end.
LINKED=()

# Symlink rather than copy, so editing a file in this repo takes effect on the next `dz`
# or new shell with no reinstall.  The container's setup-dotfiles.sh re-runs this script
# on every start, so a link something replaced with a real file self-heals.
#
# -s symlink, -f replace an existing file (including one left by an older copy-based
# install), -n treat an existing symlink-to-directory as a file rather than descending
# into it.
link_into_home() {
  local rel="$1" dst="$2"
  local src="$DOTFILES_DIR/$rel"
  if [[ ! -e "$src" ]]; then
    warn_log "Source not found, skipping: $src"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  LINKED+=("$dst")
  debug_log "Linked $dst -> $src"
}

# ---- devcontainer/ -> $HOME -------------------------------------------------
# One rule, no per-file list: a path under devcontainer/ is installed at the same path
# under $HOME.  devcontainer/.zshrc -> ~/.zshrc, devcontainer/.claude/CLAUDE.md ->
# ~/.claude/CLAUDE.md, devcontainer/foo/bar/baz.conf -> ~/foo/bar/baz.conf.  Adding a new
# dotfile means dropping it in the right place under devcontainer/ and nothing else.
#
# Only files are linked, never directories, so a target directory that also holds state
# this repo doesn't own keeps it: ~/.claude/ retains .credentials.json, history.jsonl,
# projects/ and settings.local.json, and ~/.zsh/ retains the generated completions/ below.
#
# Linking rather than copying means a program's own writes to a linked file (Claude Code
# writing settings.json from /config) land back in this repo, where they can be committed.
info_log "Linking devcontainer/ into \$HOME"

DEVCONTAINER_DIR="$DOTFILES_DIR/devcontainer"
if [[ -d "$DEVCONTAINER_DIR" ]]; then
  while IFS= read -r rel; do
    link_into_home "devcontainer/$rel" "$HOME/$rel"
  done < <(cd "$DEVCONTAINER_DIR" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' | sort)
else
  error_log "Source dir not found: $DEVCONTAINER_DIR"
  exit 1
fi

# ---- Shell completions ------------------------------------------------------
# For tools that ship no zsh completion of their own and have no oh-my-zsh plugin.
# .zshrc puts this directory on fpath *before* oh-my-zsh loads, so oh-my-zsh's single
# compinit indexes it -- see the comment in devcontainer/.zshrc; the ordering is
# load-bearing.  Generated, not linked, so it isn't committed.
info_log "Installing shell completions"

COMPLETIONS_DIR="$HOME/.zsh/completions"
mkdir -p "$COMPLETIONS_DIR"

# `just --completions zsh` emits a stub that re-invokes the binary to enumerate the
# recipes of whichever justfile is in scope, so it needs no regenerating when just is
# upgraded or a recipe is added.
if command -v just >/dev/null 2>&1; then
  just --completions zsh > "$COMPLETIONS_DIR/_just"
  debug_log "Generated $COMPLETIONS_DIR/_just from $(just --version)"
else
  warn_log "just not on PATH - skipping its zsh completion"
fi

# ---- Git aliases ------------------------------------------------------------
# The alias file lands at ~/.config/git/aliases via the mirror above, and is pulled in with
# include.path.  It is deliberately NOT ~/.config/git/config: devcontainer.json points
# GIT_CONFIG_GLOBAL at that exact path, making it the container's OWN global config -- the
# file configure-git-user.sh (user.name/email), configure-git-signing.sh (SSH signing key,
# gpg.format, commit.gpgsign) and sandbox-host-bridges.sh (insteadOf, credential helper)
# write into.  This script runs last in post-create, so shadowing that path with a symlink
# would wipe all of it, and because those writes are re-applied on every attach their later
# `git config --global` calls would follow the link into this repo.
#
# And because GIT_CONFIG_GLOBAL is set, git does NOT additionally auto-read
# ~/.config/git/config as its XDG global, so include.path is required, not optional.
info_log "Configuring git aliases via include.path"

# Tilde form, not an absolute path into the clone: git expands it, so the global config
# carries no dependency on where this repo happens to live.
ALIAS_PATH='~/.config/git/aliases'

# `|| true` because --get-all exits non-zero when the key is unset, and this script runs
# under `set -e`.
existing_includes="$(git config --global --get-all include.path 2>/dev/null || true)"
if [[ -n "$existing_includes" ]]; then
  debug_log "Existing include.path entries:"
  while IFS= read -r p; do debug_log "  $p"; done <<< "$existing_includes"
else
  debug_log "Existing include.path entries: (none)"
fi

if ! grep -qxF "$ALIAS_PATH" <<< "$existing_includes"; then
  git config --global --add include.path "$ALIAS_PATH"
  debug_log "Added git include.path = $ALIAS_PATH"
else
  debug_log "git include.path already contains $ALIAS_PATH, skipping"
fi

# Assert it actually took, rather than assuming: a wrong GIT_CONFIG_GLOBAL or an unreadable
# alias file both fail silently otherwise.
if git config --get alias.bdone >/dev/null 2>&1; then
  debug_log "git alias.bdone resolves"
else
  warn_log "git is not reading ~/.config/git/aliases - aliases (bdone, fp, re, ri, ...) unavailable."
  warn_log "  GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL:-<unset>} (include.path was written to this file)"
fi

# ---- Summary ----------------------------------------------------------------
info_log "Dotfiles installed successfully"

if [ "${DEBUG:-false}" = "true" ]; then
  debug_log "--- Installed files (${#LINKED[@]}) ---"
  for f in "${LINKED[@]}"; do
    if [[ -e "$f" ]]; then
      debug_log "  $f -> $(readlink "$f" 2>/dev/null || echo '(not a link)') ($(wc -c < "$f" | tr -d ' ') bytes)"
    else
      debug_log "  $f MISSING (dangling link?)"
    fi
  done
  debug_log "git alias source: $(git config --show-origin --get alias.bdone 2>/dev/null | cut -f1 || echo 'NOT READ')"
  debug_log "git include.path = $(git config --global --get-all include.path 2>/dev/null | tr '\n' ' ' || echo 'NOT SET')"
  debug_log "DOTZSH will resolve to: ${DOTZSH:-$HOME/dotfiles}"
fi
