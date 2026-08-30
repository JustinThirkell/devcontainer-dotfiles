# `--wait` is required: without it `code` returns immediately, so git sees an unmodified
# buffer and aborts any commit/rebase that needs an editor.
export EDITOR='code --wait'
export VISUAL='code --wait'

export NODE_REPL_HISTORY=~/.node_history
export NODE_REPL_HISTORY_SIZE='32768'
export NODE_REPL_MODE='sloppy'

export PYTHONIOENCODING='UTF-8'

# Shell history lives in zsh/config.zsh, not here.

export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'
export TZ='Pacific/Auckland'

# Keep man output in scrollback rather than on the alt screen.
export MANPAGER='less -X'

# Disable AWS CLI v2's default pager (less on the alt screen) so output stays
# in scrollback and is pipeable/redirectable.
export AWS_PAGER=''
