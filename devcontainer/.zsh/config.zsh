export LSCOLORS="exfxcxdxbxegedabagacad"
export CLICOLOR=true

# ---- History ----------------------------------------------------------------
# Single home for history config.  oh-my-zsh's lib/history.zsh runs earlier and raises
# HISTSIZE to a floor of 50000 and SAVEHIST to 10000; these lines are sourced after it
# and win.  Keep SAVEHIST == HISTSIZE, or the file silently retains less than the shell
# holds in memory.  Do not re-add HISTFILESIZE/HISTCONTROL -- those are bash, inert here.
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

setopt SHARE_HISTORY        # share history between concurrent sessions (implies INC_APPEND_HISTORY)
setopt EXTENDED_HISTORY     # timestamp each entry
setopt HIST_IGNORE_ALL_DUPS # stronger than omz's HIST_IGNORE_DUPS: drop older dupes anywhere
setopt HIST_REDUCE_BLANKS
setopt NO_BANG_HIST         # disable history expansion when ! is typed

# ---- Shell options ----------------------------------------------------------
setopt NO_BG_NICE # don't nice background tasks
setopt NO_HUP
setopt LOCAL_OPTIONS # allow functions to have local options
setopt LOCAL_TRAPS   # allow functions to have local traps
setopt PROMPT_SUBST
setopt COMPLETE_IN_WORD
setopt IGNORE_EOF
unsetopt CORRECT

# LIST_BEEP is unset in ohmyzsh.config (its only home).

# don't expand aliases _before_ completion has finished
#   like: git comm-[tab]
#setopt complete_aliases

# ---- Keybindings ------------------------------------------------------------
# Up/Down are deliberately absent: oh-my-zsh's lib/key-bindings.zsh already autoloads
# and binds up-line-or-beginning-search / down-line-or-beginning-search, and does it for
# emacs, viins and vicmd plus the terminfo sequences -- more thoroughly than a local
# emacs-only bindkey would.
bindkey '^[^[[D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[[5D' beginning-of-line
bindkey '^[[5C' end-of-line
bindkey '^[[3~' delete-char

ulimit -n 4096
