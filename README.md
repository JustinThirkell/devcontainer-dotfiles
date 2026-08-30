# devcontainer-dotfiles

Personal dotfiles for use inside devcontainers at CarePatron. Brings shell config, git
aliases, Claude Code user config, and Powerlevel10k prompt config into every devcontainer
automatically.

The Carepatron workflow tooling (ClickUp CLI, the `cp_*` workflow functions) used to live
here. It now lives in the Carepatron-App repo under `.devcontainer/tooling/`, which the
container loads itself -- see that repo for anything `cp_new_task` / `clickup` related.

What remains is one developer's shell: prompt, aliases, exports, editor and multiplexer
config, plus personal Claude Code config. It is optional, and nothing in the container
depends on it.

## Layout

Every file here is in exactly one of two categories, and the directory it lives in tells
you which.

**`devcontainer/` is the payload.** A path under `devcontainer/` is installed at the same
path under the container's `$HOME`. Nothing else in the repo is installed anywhere.

```
devcontainer/.zshrc                  ->  ~/.zshrc
devcontainer/.claude/CLAUDE.md       ->  ~/.claude/CLAUDE.md
devcontainer/.zsh/config.zsh         ->  ~/.zsh/config.zsh
devcontainer/.config/git/config      ->  ~/.config/git/config
devcontainer/foo/bar/baz.conf        ->  ~/foo/bar/baz.conf
```

Adding a new dotfile means dropping it at the right path under `devcontainer/` and nothing
else -- `install.sh` has no per-file list to update.

**Everything at the repo root is either the installer or this repo's own config**, and is
never copied into the container. `install.sh` cannot live under `devcontainer/`: it is the
thing that performs the mirror, and anything in there would be installed into `$HOME`.

```
devcontainer-dotfiles/
│
├── devcontainer/            # ===== PAYLOAD: mirrored into the container's $HOME =====
│   ├── .zshrc               #   Main shell config
│   ├── .p10k.zsh            #   Powerlevel10k prompt configuration
│   ├── .ohmyzsh.config      #   Oh My Zsh settings -- read *before* oh-my-zsh.sh loads
│   ├── .tmux.conf           #   tmux: mouse mode, C-a prefix
│   ├── .config/git/config   #   Git aliases (bclean, bdone, fp, re, ri, ...)
│   ├── .zsh/                #   Shell topic files, sourced by .zshrc after Oh My Zsh
│   │   ├── aliases.zsh      #     j=just, gs=git status
│   │   ├── config.zsh       #     Shell options, history, keybindings
│   │   ├── cswap.zsh        #     claude-swap auto-rotation poller (started detached)
│   │   ├── exports.zsh      #     EDITOR, LANG, TZ, pagers
│   │   └── functions.zsh    #     _info/_error/_debug helpers, dz/dzz reload aliases
│   └── .claude/             #   Claude Code *user*-scope config
│       ├── CLAUDE.md        #     Per-turn workflow rules
│       ├── workflow-reference.md  # Deep background, read on demand (NOT loaded per turn)
│       ├── settings.json    #     Personal preferences (statusline, effortLevel, skillOverrides)
│       └── ccusage-statusline.sh  # statusLine wrapper around `ccusage statusline`
│
├── install.sh               # ===== MACHINERY: the installer, self-contained =====
│
├── README.md                # ===== THIS REPO'S OWN CONFIG (never installed) =====
├── biome.jsonc              #   Formatter for the JSON/JSONC in this repo
├── .editorconfig            #   Editor defaults for this repo
├── .gitignore
└── .vscode/settings.json    #   File associations + format-on-save for this repo
```

> [!NOTE]
> There is deliberately no `.claude/` at the repo root. The Claude Code config this repo
> *ships* lives at `devcontainer/.claude/`; working **on** this repo just uses whatever
> Claude Code config the host already has. Keeping the payload out of the root stops a
> pile of Carepatron workflow rules -- and any hook in `settings.json` -- from applying to
> sessions that are only editing dotfiles.

## Configuration

Point the container at this repo in the Carepatron-App devcontainer's `config.local`:

```
DOTFILES_REPOSITORY=youruser/devcontainer-dotfiles   # owner/repo shorthand or full URL
DOTFILES_TARGET_PATH=~/dotfiles                      # optional, defaults to ~/dotfiles
DOTFILES_INSTALL_COMMAND=install.sh                  # optional, defaults to install.sh
```

`.devcontainer/scripts/setup-dotfiles.sh` clones the repo into the container and runs the
install command. It is invoked last from `post-create-command.sh`, under the firewall jail,
because it is the only step that fetches and executes third-party code. The script is
idempotent: if the target path already exists it `git pull`s and re-runs `install.sh`.

> [!IMPORTANT]
> Do **not** use the editor's built-in `dotfiles.repository` / `dotfiles.targetPath` /
> `dotfiles.installCommand` settings. The container deliberately does not use them -- they
> are host-side *client* settings that can't be set from `devcontainer.json`, aren't passed
> by Zed, and don't exist at all for a terminal agent attaching to a running container. If
> you have `dotfiles.*` keys in your editor settings, remove them, or the two mechanisms
> race for the same target path. See the Carepatron-App devcontainer README for the full
> rationale.

### Secrets

There are none to configure. The container has no `remoteEnv` block and nothing is
forwarded from the host shell. Credentials like `CLICKUP_API_KEY` and `GH_TOKEN` stop at
the injecting egress proxy, which attaches them to the requests it carries -- the container
holds only non-authenticating placeholders and never reads the real values. Commit signing
uses a forwarded signing-only agent socket, so the key stays on the host.

Do not add a credential to this repo, to `containerEnv`, or to a file under
`devcontainer/`. If a host service needs authenticating to, the answer is a proxy
`secrets` entry scoped to that host -- see "Runbook: the egress proxy" in the
Carepatron-App devcontainer README.

### Devcontainer prerequisites

The **project's devcontainer** must provide the following. These are shared dependencies
that are much more efficient to install during docker build than at runtime:

| Tool                     | Why                                             |
|--------------------------|-------------------------------------------------|
| zsh                      | Shell                                           |
| Oh My Zsh                | Plugin/theme framework                          |
| Powerlevel10k            | Prompt theme                                    |
| zsh-syntax-highlighting  | Command syntax highlighting                     |
| git                      | Version control                                 |
| just                     | Optional -- `install.sh` generates its zsh completion if present |

`install.sh` itself needs nothing beyond bash and git -- it creates symlinks, generates one
completion file, and changes no global state. The workflow tooling's own prerequisites (Node, `gh`, `jq`) are the
Carepatron-App repo's concern now and are documented there.

## What happens at runtime

```
Container starts
  └─> post-create-command.sh (last step, inside the firewall jail)
       └─> setup-dotfiles.sh clones/pulls this repo to ~/dotfiles, runs install.sh
            ├─ Symlinks every file under devcontainer/ to the same path under $HOME
            ├─ Generates ~/.zsh/completions/_just (if just is on PATH)
            └─ Verifies git actually reads ~/.config/git/config

First terminal opened (zsh starts)
  └─> ~/.zshrc runs
       ├─ p10k instant prompt
       ├─ Sources ~/.ohmyzsh.config (theme, plugins, omz lib settings)
       ├─ Sources ~/.p10k.zsh (prompt config)
       ├─ Puts ~/.zsh/completions on fpath   <-- before oh-my-zsh; see Gotchas
       ├─ Loads Oh My Zsh (runs the session's single compinit)
       ├─ Sources ~/.zsh/*.zsh (aliases, config, cswap, exports, functions)
       └─ Sources zsh-syntax-highlighting (if installed)
```

The Carepatron workflow functions load separately, from the Carepatron-App repo: the
container's baked `/etc/zsh/zshrc` sources `.devcontainer/tooling/lib/load.zsh`, and
`.devcontainer/tooling/bin/` leads `PATH` for agents. Nothing in this repo is involved.

### Symlinks, not copies

`install.sh` symlinks, so editing a file in `~/dotfiles` takes effect on the next `dz` or
new shell with no reinstall. Three consequences worth knowing:

- Only *files* are linked, never directories, so a target directory that also holds state
  this repo doesn't own keeps it. `~/.claude/` retains `.credentials.json`,
  `history.jsonl`, `projects/` and `settings.local.json`; `~/.zsh/` retains the generated
  `completions/`.
- A program's own writes to a linked file -- Claude Code writing `settings.json` from
  `/config` -- go back into this repo, where they can be committed.
- If something replaces a link with a real file (`p10k configure` rewriting `~/.p10k.zsh`,
  say), the change lands outside the repo. Re-running `install.sh` restores the link, and
  the container does that on every start.

## Gotchas

**`fpath` must be extended before `oh-my-zsh.sh` is sourced.** Oh My Zsh runs the only
`compinit` of the session and stamps its dumpfile with an `#omz fpath:` footer it re-checks
on the next start. A directory added to `fpath` *after* that `compinit` needs a second
`compinit` to be indexed -- and that second run rewrites the dumpfile without the footer,
so the next shell's Oh My Zsh finds the footer missing, deletes the dump, and rebuilds it
cold. Forever, twice per shell. Measured cost of getting this wrong: 532ms vs 114ms per
shell start. The ordering in `.zshrc` is load-bearing; don't move the `fpath=` line into a
`.zsh/*.zsh` topic file, because those are sourced after Oh My Zsh.

**History config lives only in `devcontainer/.zsh/config.zsh`.** Oh My Zsh's
`lib/history.zsh` sets floors (`HISTSIZE` >= 50000, `SAVEHIST` >= 10000) before the topic
files load. Keep `SAVEHIST` == `HISTSIZE` or the file retains less than the shell holds.
`HISTFILESIZE` and `HISTCONTROL` are bash variables and do nothing in zsh.

**`.ohmyzsh.config` is sourced before Oh My Zsh; `.zsh/*.zsh` after.** Anything Oh My Zsh
*reads* at load time (`ZSH_THEME`, `plugins`, `HIST_STAMPS`, `zstyle ':omz:update'`) has to
go in `.ohmyzsh.config`. Anything that must override an Oh My Zsh default goes in a topic
file.

**`EDITOR` needs `--wait`.** Without it `code` returns immediately and git aborts any
commit or rebase that opens an editor.

**Git aliases work by being mirrored, not by being wired.** `~/.config/git/config` is a
global config file in git's own right -- `git help config`: "`$XDG_CONFIG_HOME/git/config`,
`~/.gitconfig` ... If both files exist, both files are read". So there is no
`include.path` to set, and `~/.gitconfig` still applies on top. Two env vars would
silently stop git reading it, and `install.sh` warns if either has: `GIT_CONFIG_GLOBAL`
(replaces both global config files) and `XDG_CONFIG_HOME` (moves the directory git looks
in). If you can't unset them, fall back to `~/.config/git/aliases` plus an explicit
`include.path`.

**`skillOverrides` takes exact names only.** Wildcards are rejected outright
(`wildcard-suffix names are not allowed; list each skill by its exact name`), and there is
no allow-list form in settings -- so the list has to name every skill you want off.

## Debugging

### Enable verbose logging

Set `DEVCONTAINER_DEBUG=true` to get detailed output from `install.sh`, including every
symlink it creates and where it points. Set it in the devcontainer's `config.local`, or in
`containerEnv` in `devcontainer.json`:

```json
{
  "containerEnv": {
    "DEVCONTAINER_DEBUG": "true"
  }
}
```

### Common issues

**ClickUp / `cp_*` workflow functions not working:**
- They are not part of these dotfiles any more -- see `.devcontainer/tooling/` in the
  Carepatron-App repo.
- The container holds only a placeholder credential; the real one is attached by the egress
  proxy. A 401 mentioning the placeholder means injection stopped, not a revoked token.

**p10k prompt looks broken (missing glyphs):**
- Install a Nerd Font on your **local machine** (not in the container).
  The terminal font renders locally. MesloLGS NF is recommended.
- Set it as the terminal font in Cursor/VS Code settings:
  `"terminal.integrated.fontFamily": "MesloLGS NF"`

**Shell startup feels slow:**
- Check `compinit` runs once, not twice: `zsh -i -x -c true 2>&1 | grep -c '> compinit'`.
- Check the completion dump is reused rather than rebuilt: run `ls -i ~/.zcompdump-*` in
  two fresh shells; a changing inode means it's being deleted and rebuilt each start.
  See Gotchas.

**zshrc not loading / old config:**
- Verify dotfiles were cloned: `ls ~/dotfiles/`
- Verify the link exists and points into the repo: `ls -l ~/.zshrc`
- Re-source: `dz` (alias for `source ~/.zshrc`)
- Full reset: `dzz` (alias for `exec zsh`)
