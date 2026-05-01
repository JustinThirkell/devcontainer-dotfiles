  # Personal workflow (Justin)

  This file is installed by dotfiles in a devcontainer and describes shell workflow commands available in the devcontainer.
  These are zsh functions sourced from `~/dotfiles/cp/` and `~/dotfiles/clickup/`.

  ## Environment

  - `ISSUE_BRANCH_PREFIX=justin`
  - `GITHUB_DEFAULT_PR_REVIEWER=Carepatron/platform`
  - Branch format: `justin/CU-{taskid}-{slug}` (e.g. `justin/CU-86ewvt64k-unit-tests`)
  - PR title format: `[CU-{taskid}] {Capitalized title}` (e.g. `[CU-86ewvt64k] Unit tests`)

  ## Workflow commands

  ### `new` / `cp_new_task <title> <description> [--no-assignment] [--no-start]`

  Creates a ClickUp task and (by default) immediately starts it via `cp_start_task`.
  Use `--no-start` to create without starting.  Use `--no-assignment` to skip assigning.

  ### `start` / `cp_start_task <task-id>`

  Starts work on a ClickUp task:

  1. Fetches task name from ClickUp API.
  2. Creates and checks out branch `justin/CU-{taskid}-{slug}` (or checks out if it exists).
  3. Marks task as IN PROGRESS in ClickUp.
  4. Adds task to the current sprint.

  Accepts a task ID or a ClickUp URL (e.g. `https://app.clickup.com/t/86ewdbtbh`).

  ### `pr` / `cp_pr_task [--body DESCRIPTION] [--sr | --skip-ai-review]`

  Creates or updates a PR for the current branch:

  1. Pushes the current branch (sets upstream if needed).
  2. Extracts task ID from branch name.
  3. Fetches task name/description from ClickUp API.
  4. Generates PR title as `[CU-{taskid}] {Capitalized title}`.
  5. Creates a **draft** PR with reviewer `Carepatron/platform`, or updates an existing PR.
  6. Marks the ClickUp task as IN REVIEW.

  Use `--body` to provide a custom PR description; otherwise uses the ClickUp task description.
  Use `--sr` (alias of `--skip-ai-review`) to add the `skip-greptile` label so the Greptile AI reviewer bot skips this PR.

  #### When to use `--sr` / `--skip-ai-review`

  **Default to omitting `--sr`.**  Substantive code changes — even small ones — get the AI review.

  Add `--sr` only when an AI reviewer would have nothing useful to say:

  - Docs / markdown / comment-only changes.
  - Auto-generated code (regenerated TypeScript clients, OpenAPI artifacts, etc.).
  - Pure reformatting (mass CSharpier / Biome rerun, no logic changes).
  - Trivial config bumps (version pins, env var renames with no behaviour change).

  When in doubt, omit `--sr`.  A wasted Greptile run is cheaper than a missed review on real code.

  ### `cleanup` / `cp_cleanup_branches`

  Cleans up merged branches:

  1. Finds local branches whose remote tracking branch is gone.
  2. For each, extracts the task ID and marks the ClickUp task as DONE.
  3. Deletes the local branches (`git bclean`).

  ## ClickUp CLI (`clickup <command>`)

  Low-level wrapper around the ClickUp API (via `~/dotfiles/clickup/clickup.ts`):

  - `clickup whoami` — show ClickUp user info
  - `clickup get-task <id>` — fetch task details (JSON)
  - `clickup start-task <id>` — set status to IN PROGRESS
  - `clickup pr-task <id>` — set status to IN REVIEW
  - `clickup complete-task <id>` — set status to DONE
  - `clickup create-task <title> <description>` — create a task
  - `clickup add-task-to-current-sprint <id>` — move task to current sprint

  All commands accept `--debug` for verbose output.

  ## Commits must always be signed

  Every `git commit` must be signed.  No exceptions.

  - **Never** pass `--no-gpg-sign`, `-c commit.gpgsign=false`, `-c gpg.format=…` to bypass or alter signing — even "defensively" or "to skip a hook".
  - The devcontainer is pre-configured with SSH-key signing (`commit.gpgsign=true`, `gpg.format=ssh`, key at `~/.ssh/id_ed25519_signing`).  Trust it.  Don't probe it.
  - If a `git commit` fails *because of* signing (key not found, agent locked, etc.), **surface the error and stop** — do not retry with signing disabled.  Ask the operator to fix the signing setup.
  - This applies to every commit the agent makes: feature commits, fixup commits, amends, rebases.  Even on private branches.  Even on throwaway worktrees.  Even when the next step is going to squash-merge.

  Reason: signed commits are the audit trail.  An unsigned commit on a feature branch survives review noise and ends up referenced from PR comments, rollback investigations, and bisects long after merge — even when the squash-merge commit on master is signed.  Mixed-signature branches signal "agent did something weird here" and erode trust in *every* commit on the branch.

  ## PR creation — always use `pr`, never the `/pr-create` skill

  For any request that means "make a PR" — including "pr this", "commit and PR", "create a pull request", "open a PR", "make a draft PR", etc. — run the `pr` zsh alias (`cp_pr_task`) in the shell, not the `/pr-create` skill.

  Reason: `pr` does additional useful work the skill doesn't:

  - LLM-generated description from branch diff (when `--body` is omitted)
  - Auto-opens the PR in browser
  - Honours `--sr` / `--skip-ai-review` for Greptile bot skip
  - Marks the ClickUp task as IN REVIEW automatically

  ## Devcontainer worktree workflow

  When the user says "use devcontainer worktree workflow", "use the worktree workflow", "worktree this", or any close variant, follow the loop below for the requested task.  The motivation: each task lives in its own git worktree under `~/worktrees/`, so multiple parallel Claude Code sessions can work on different tasks without colliding on `/workspace`.

  Use the lower-level primitives (`clickup create-task`, `infer_branch_name`, `git worktree add`, `clickup start-task`) — **not** the higher-level `new` / `start` shortcuts.  The shortcuts bake in `/workspace`-checkout-and-branch assumptions that conflict with worktrees; the primitives compose cleanly.

  1. **Sync master.**  In `/workspace`, `git fetch origin && git checkout master && git pull --ff-only`.  Skip if `/workspace` is already on master and up to date.  Never pull while on a feature branch.
  2. **Create or resolve the task.**
     - If no task ID was provided: `clickup create-task "<title>" "<description>"`.  Captures task id + name from the returned JSON.  This is git-free (unlike `new` / `cp_new_task`, which calls `cp_start_task` and checks out a branch in `/workspace`).
     - If a task ID was provided: `clickup get-task <id>` to fetch the task name.
  3. **Resolve the branch name.**  `infer_branch_name <task_id> "<task_name>"` (defined in `~/dotfiles/cp/git.zsh`) — pure string function, no git side-effects.  Returns `${ISSUE_BRANCH_PREFIX}/CU-{taskid}-{slug}`.
  4. **Create the worktree.**  `mkdir -p ~/worktrees && git -C /workspace worktree add ~/worktrees/CU-{taskid}-{slug} -b <branch>`.  Single command creates the branch off the current `/workspace` HEAD (master, per step 1) **and** checks it out into the worktree.  `/workspace` itself stays on master — free for a parallel session to use.
  5. **Wire up `node_modules`.**  `ln -s /workspace/node_modules ~/worktrees/CU-{taskid}-{slug}/node_modules`.  The devcontainer's `node_modules` is a Docker volume mounted only at `/workspace/node_modules`, so a fresh worktree has no `node_modules` of its own.  Without the symlink, `yarn` commands fail with "Couldn't find the node_modules state file" and pre-commit hooks (lefthook) calling `./node_modules/.bin/biome` fail with "biome: not found".  Sharing the hoisted install is safe — never run `yarn install` from inside a worktree; do that in `/workspace`.
  6. **Mark task IN PROGRESS + sprint.**  `clickup start-task <id>` and `clickup add-task-to-current-sprint <id>`.  Both git-free.  (These are the bits `cp_start_task` does *after* its checkout; we run them directly.)
  7. **Code / test dev loop.**  Operate inside `~/worktrees/CU-{taskid}-{slug}/` using absolute paths.  TDD red/green per project standards.  ExecPlan reads and updates happen inside the worktree (the plan file is in-repo, so the worktree has its own copy).
  8. **Commit.**  Logical units; `[CU-{taskid}]` prefix in the message body, not the subject.
  9. **Open the PR.**  From inside the worktree: `pr` (or `pr --sr` for trivial / docs-only changes).  Per the "always use `pr`, never the `/pr-create` skill" section above.  `pr` works unchanged in a worktree — `git push` and `gh pr` are pwd-aware, and `clickup pr-task` is git-free.
  10. **Update the ExecPlan** if one applies — tick milestone checkboxes, add Surprises/Decisions.  Follow-up commit + `pr` updates the existing PR.
  11. **Leave the worktree in place** until the PR merges.  Cleanup post-merge is `git worktree remove ~/worktrees/CU-{taskid}-{slug}` — do not remove or `git branch -D` without explicit user approval.

  Constraints that apply throughout:

  - Never check out a feature branch in `/workspace` itself — that would block parallel sessions.  All feature work happens in worktrees.
  - Never run `yarn install` (or any other tool that mutates `node_modules`) from inside a worktree.  All worktrees share `/workspace/node_modules` via symlink, so an install from a worktree would race against `/workspace` and any other worktree session.
  - Never force-push, `reset --hard`, or `branch -D` without explicit approval.
  - Use absolute paths into the worktree directory in tool calls; do not rely on shell `cd` persistence assumptions.
  - `~/worktrees/` is per-devcontainer-instance state and is not in dotfiles.
