# p10k instant prompt (keep at top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export DOTZSH=${DOTZSH:-$HOME/.dotfiles}
export PROJECTS=${PROJECTS:-/workspace}
export USER=${USER:-$(whoami)}

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
[[ -f ~/.secrets.local ]] && source ~/.secrets.local

export ZSH=$HOME/.oh-my-zsh
[[ -f "$HOME/.ohmyzsh.config" ]] && source "$HOME/.ohmyzsh.config"
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
source "$ZSH/oh-my-zsh.sh"

# Source topic files from dotfiles subdirectories.
# Single-depth glob avoids clickup/node_modules and root-level config files.
typeset -U config_files
config_files=($DOTZSH/*/*.zsh)

for file in ${(M)config_files:#*/path.zsh}; do source "$file"; done
for file in ${${config_files:#*/path.zsh}:#*/completion.zsh}; do source "$file"; done
for file in ${(M)config_files:#*/completion.zsh}; do source "$file"; done
unset config_files

# zsh-syntax-highlighting (apt package location)
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

compinit -C
