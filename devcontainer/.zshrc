# p10k instant prompt (keep at top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export DOTZSH=${DOTZSH:-$HOME/dotfiles}
export PROJECTS=${PROJECTS:-/workspace}
export USER=${USER:-$(whoami)}

export ZSH=$HOME/.oh-my-zsh
[[ -f "$HOME/.ohmyzsh.config" ]] && source "$HOME/.ohmyzsh.config"
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Extend fpath BEFORE oh-my-zsh loads -- this ordering is load-bearing.
#
# oh-my-zsh runs the session's only compinit, then stamps its dumpfile with an
# "#omz fpath:" footer that it re-checks on the next start.  A directory added to fpath
# *after* that compinit needs a second compinit to be indexed; that second run rewrites
# the dumpfile without the footer, so the next shell's oh-my-zsh finds the footer missing,
# deletes the dump, and rebuilds it cold -- forever, twice per shell.  Extending fpath
# here means one compinit indexes everything and the dump is genuinely cached.
# Measured on this config: 532ms -> 114ms per shell start.
#
# ~/.zsh/completions holds completions for tools that ship none and have no omz plugin;
# install.sh generates them there.  typeset -U stops `dz` (re-source) growing fpath.
typeset -U fpath FPATH
fpath=("$HOME/.zsh/completions" $fpath)

source "$ZSH/oh-my-zsh.sh"

# Source the topic files.  ~/.zsh/*.zsh is one level only, so ~/.zsh/completions/ (a
# directory of compdef stubs, not shell fragments) is skipped.  (N) so an empty or absent
# ~/.zsh yields nothing rather than "no matches found" at every prompt.
for file in ~/.zsh/*.zsh(N); do source "$file"; done

# zsh-syntax-highlighting (apt package location).  Sourced last, after the topic files
# have finished registering widgets and keybindings.
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
