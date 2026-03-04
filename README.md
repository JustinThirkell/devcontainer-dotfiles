# dotfiles-justin

Personal dotfiles for use inside devcontainers at CarePatron. Brings ClickUp CLI,
CP workflow functions, git aliases, and Powerlevel10k prompt config into every
devcontainer automatically.

## Overview

```
dotfiles-justin/
├── install.sh              # Entrypoint -- runs automatically at container start
├── common.sh               # Shared logging utilities (debug_log, info_log, etc.)
├── zshrc                   # Main shell config (copied to ~/.zshrc)
├── zshrc.local             # Non-secret env vars (ClickUp IDs, PR reviewer, etc.)
├── p10k.zsh                # Powerlevel10k prompt configuration
├── ohmyzsh.config          # Oh My Zsh settings (theme, plugins)
├── gitconfig.aliases       # Git aliases (bclean, bdone, fp, re, ri, etc.)
├── secrets.local.example   # Documents required secrets (not committed)
├── zsh/
│   ├── functions.zsh       # info/error/debug helpers, dz/dzz reload aliases
│   ├── exports.zsh         # EDITOR, HISTSIZE, LANG, TZ, etc.
│   └── config.zsh          # Shell options, history, keybindings
├── clickup/
│   ├── functions.zsh       # Zsh wrappers: clickup, clickup_start-task, etc.
│   ├── clickup.ts          # ClickUp CLI entrypoint (TypeScript)
│   ├── clickup-client.ts   # ClickUp API client
│   ├── package.json        # Node dependencies (tsx, typescript)
│   └── tsconfig.json
└── cp/
    ├── workflow.zsh        # cp_new_task, cp_start_task, cp_pr_task, cp_cleanup_branches
    ├── git.zsh             # infer_branch_name, git_checkout_task_branch, git_pr_task_branch
    └── aliases.zsh         # CP_DIR, cpa alias
```

## Configuration

### 1. Point your editor at this dotfiles repo

In your **Cursor or VS Code user settings** (`settings.json` -- user-level, not workspace):

```json
{
  "dotfiles.repository": "github.com/youruser/dotfiles-justin",
  "dotfiles.targetPath": "~/.dotfiles",
  "dotfiles.installCommand": "install.sh"
}
```

This tells the devcontainer runtime to clone this repo into `~/.dotfiles` inside
every container and run `install.sh`. It applies to all devcontainers you open --
your teammates don't need to know about it.

### 2. Forward secrets via remoteEnv

Secrets must never be committed. Instead, forward them from your host machine
into the container using `remoteEnv` in your **user** `settings.json`:

```json
{
  "remoteEnv": {
    "CLICKUP_API_KEY": "${localEnv:CLICKUP_API_KEY}",
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  }
}
```

This requires the env vars to be set on your **host machine** (e.g., in
`~/.secrets.local` on macOS, sourced by your shell profile). The devcontainer
runtime reads them from the host environment and injects them into the container.

See `secrets.local.example` for the full list of required variables.

### 3. Devcontainer prerequisites

The **project's devcontainer** (Dockerfile or devcontainer features) must provide
the following. These are shared infrastructure, not personal config:

| Tool                     | Why                                    |
|--------------------------|----------------------------------------|
| zsh                      | Shell                                  |
| Oh My Zsh                | Plugin/theme framework                 |
| Powerlevel10k            | Prompt theme                           |
| zsh-syntax-highlighting  | Command syntax highlighting            |
| Node.js + npm            | Runs the ClickUp TypeScript CLI        |
| git                      | Version control                        |
| gh                       | GitHub CLI (used by `cp_pr_task`)       |
| jq                       | JSON parsing in workflow functions     |

## What happens at runtime

When a devcontainer starts with dotfiles configured:

```
Container starts
  └─> Devcontainer runtime clones this repo to ~/.dotfiles
       └─> Runs install.sh
            ├─ Sources common.sh (logging utilities)
            ├─ Copies zshrc, p10k.zsh, ohmyzsh.config, zshrc.local into $HOME
            ├─ Sets git include.path -> gitconfig.aliases (by reference)
            └─ Runs npm install in clickup/ directory

First terminal opened (zsh starts)
  └─> ~/.zshrc runs
       ├─ p10k instant prompt
       ├─ Sources ~/.zshrc.local (ClickUp IDs, env vars)
       ├─ Sources ~/.secrets.local (if present -- typically via remoteEnv)
       ├─ Sources ~/.ohmyzsh.config (sets theme, plugins)
       ├─ Sources ~/.p10k.zsh (prompt config)
       ├─ Loads Oh My Zsh
       ├─ Globs ~/.dotfiles/*/*.zsh and sources all topic files:
       │    ├─ zsh/functions.zsh, exports.zsh, config.zsh
       │    ├─ clickup/functions.zsh
       │    └─ cp/workflow.zsh, git.zsh, aliases.zsh
       └─ Sources zsh-syntax-highlighting (if installed)
```

## Debugging

### Enable verbose logging

Set `DEBUG_DEVCONTAINER=true` to get detailed output from `install.sh`. You can
set this in the project's `devcontainer.json`:

```json
{
  "containerEnv": {
    "DEBUG_DEVCONTAINER": "true"
  }
}
```

Or pass it via your user settings:

```json
{
  "remoteEnv": {
    "DEBUG_DEVCONTAINER": "true"
  }
}
```

With debug enabled, `install.sh` logs every file copy, git config change, and
prints a summary of all installed config files with their sizes.

### Common issues

**ClickUp functions not working:**
- Check that `CLICKUP_API_KEY` is set: `echo $CLICKUP_API_KEY`
- Check that npm dependencies are installed: `ls ~/.dotfiles/clickup/node_modules/.bin/tsx`
- Re-run install: `~/.dotfiles/install.sh`

**p10k prompt looks broken (missing glyphs):**
- Install a Nerd Font on your **local machine** (not in the container).
  The terminal font renders locally. MesloLGS NF is recommended.
- Set it as the terminal font in Cursor/VS Code settings:
  `"terminal.integrated.fontFamily": "MesloLGS NF"`

**gh commands fail with auth errors:**
- Forward `GH_TOKEN` via `remoteEnv` (see above), or
- Run `gh auth login` inside the container

**zshrc not loading / old config:**
- Verify dotfiles were cloned: `ls ~/.dotfiles/`
- Verify zshrc was copied: `head -5 ~/.zshrc` (should show p10k instant prompt)
- Re-source: `dz` (alias for `source ~/.zshrc`)
- Full reset: `dzz` (alias for `exec zsh`)
