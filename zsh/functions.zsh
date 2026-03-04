info() {
  printf "\033[0;32m%s\033[0m\n" "$1" >&2
}

error() {
  printf "\033[0;31m%s\033[0m\n" "$1" >&2
}

debug() {
  printf "\033[0;90m%s\033[0m\n" "$1" >&2
}

re-source-zsh-files() {
  source ~/.zshrc && echo "Sourced ~/.zshrc"
}
alias dz=re-source-zsh-files

reset-zsh() {
  exec zsh
}
alias dzz=reset-zsh
