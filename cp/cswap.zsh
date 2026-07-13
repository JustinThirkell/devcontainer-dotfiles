# claude-swap (cswap) - background multi-account rotation for Claude Code.
#
# The `cswap` binary is baked into the devcontainer image, and its account
# store (~/.local/share/claude-swap) is persisted via a named volume, so registered
# accounts survive rebuilds.  This fragment starts ONE `cswap auto` poller per
# container - not per shell - so multiple terminals don't spawn duplicate loops.
#
# Auto-rotation is ON by default here (CSWAP_AUTO=1) but only actually starts once at
# least one account is registered.  To turn it off: `export CSWAP_AUTO=0`.
#
# One-time setup (see .devcontainer/README.md "Multi-account rotation (cswap)"):
#   cswap add            # after logging in to Claude Code with account A
#   cswap add            # after /login with account B
# Verify:  cswap list    (usage + reset per account)
#          cswap status  (active account)
#          tail -f ~/.local/share/claude-swap/claude-swap.log
# Stop the poller: pkill -u "$UID" -f 'cswap auto'

# ON by default; override with `export CSWAP_AUTO=0` before this fragment is sourced.
: "${CSWAP_AUTO:=1}"

_cswap_start_auto() {
  # Interactive shells only; respect the opt-out.
  [[ -o interactive ]] || return 0
  [[ "${CSWAP_AUTO}" == "1" ]] || return 0
  command -v cswap >/dev/null 2>&1 || return 0

  # Singleton across shells: if a poller is already running for this user, do nothing.
  pgrep -u "$UID" -f 'cswap auto' >/dev/null 2>&1 && return 0

  # Only start once an account is registered, so we don't crash-loop a respawn on
  # every new shell before `cswap add` has been run.  `cswap status` exits non-zero
  # when there is no active account.
  cswap status >/dev/null 2>&1 || return 0

  # Detach from the shell (zsh `&!` = background + disown) so it survives shell exit.
  nohup cswap auto >"${HOME}/.local/share/claude-swap/cswap-auto.log" 2>&1 &!
}

_cswap_start_auto
