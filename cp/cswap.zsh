# claude-swap (cswap) - background multi-account rotation for Claude Code.
#
# The `cswap` binary is baked into the devcontainer image (opt-in, inert
# by default).  This fragment starts ONE `cswap auto` poller per container - not per
# shell - so multiple terminals don't spawn duplicate loops.  It stays off until you
# opt in with CSWAP_AUTO=1 *and* have registered at least one account.
#
# One-time setup (see .devcontainer/README.md "Multi-account rotation (cswap)"):
#   cswap add                       # after logging in to Claude Code with account A
#   cswap add                       # after /login with account B
#   echo 'export CSWAP_AUTO=1' >> ~/.zshrc.local   # then open a new shell
#
# Verify:  cswap --list   (usage + reset per account)
#          cswap --status (active account)
#          tail -f ~/.claude/cswap-auto.log   (poller output)
# Disable: unset CSWAP_AUTO (or set to 0) and kill the running poller:
#          pkill -u "$UID" -f 'cswap auto'

_cswap_start_auto() {
  # Interactive shells only; opt-in only.
  [[ -o interactive ]] || return 0
  [[ "${CSWAP_AUTO:-0}" == "1" ]] || return 0
  command -v cswap >/dev/null 2>&1 || return 0

  # Singleton across shells: if a poller is already running for this user, do nothing.
  pgrep -u "$UID" -f 'cswap auto' >/dev/null 2>&1 && return 0

  # Belt-and-braces: only start once an account is registered, so we don't crash-loop
  # a respawn on every new shell before `cswap add` has been run.  `cswap --status`
  # exits non-zero when there is no active account.
  cswap --status >/dev/null 2>&1 || return 0

  # Detach from the shell (zsh `&!` = background + disown) so it survives shell exit.
  nohup cswap auto >"${HOME}/.claude/cswap-auto.log" 2>&1 &!
}

_cswap_start_auto
