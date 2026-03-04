#!/bin/bash
# Shared logging utilities for dotfiles install scripts.
# Source this at the top of any script:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Only initialize logging if not already initialized
if [ -z "${COLOR_DEBUG:-}" ]; then
  if [ -t 2 ] && [ "${NO_COLOR:-}" = "" ]; then
    COLOR_DEBUG='\033[0;90m'
    COLOR_INFO='\033[0;32m'
    COLOR_WARN='\033[0;33m'
    COLOR_ERROR='\033[0;31m'
    COLOR_RESET='\033[0m'
  else
    COLOR_DEBUG=''
    COLOR_INFO=''
    COLOR_WARN=''
    COLOR_ERROR=''
    COLOR_RESET=''
  fi

  # Single source of truth: set DEBUG_DEVCONTAINER=true to enable debug logging
  DEBUG=${DEBUG_DEVCONTAINER:-false}

  debug_log() {
    if [ "${DEBUG:-false}" = "true" ]; then
      echo -e "${COLOR_DEBUG}[DEBUG] [dotfiles]${COLOR_RESET} $*" >&2
    fi
  }

  info_log() {
    echo -e "${COLOR_INFO}[INFO] [dotfiles]${COLOR_RESET} $*" >&2
  }

  warn_log() {
    echo -e "${COLOR_WARN}[WARN] [dotfiles]${COLOR_RESET} $*" >&2
  }

  error_log() {
    echo -e "${COLOR_ERROR}[ERROR] [dotfiles]${COLOR_RESET} $*" >&2
  }
fi
