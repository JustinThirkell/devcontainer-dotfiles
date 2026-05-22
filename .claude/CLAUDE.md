# Personal workflow (Justin)

This file is installed by dotfiles in a devcontainer and describes shell workflow commands available in the devcontainer.
These are zsh functions sourced from `~/dotfiles/cp/` and `~/dotfiles/clickup/`.

## Environment

- `ISSUE_BRANCH_PREFIX=justin`
- `GITHUB_DEFAULT_PR_REVIEWER=Carepatron/platform`
- Branch format: `justin/CU-{taskid}-{slug}` (e.g. `justin/CU-86ewvt64k-unit-tests`)
- PR title format: `[CU-{taskid}] {Capitalized title}` (e.g. `[CU-86ewvt64k] Unit tests`)

## Workflow commands

### `new` / `cp_new_task <title> [description] [--no-assignment] [--no-start] [--worktree]`

Creates a ClickUp task and (by default) immediately starts it via `cp_start_task`.

- `--no-start` creates the task without starting work on it.
- `--no-assignment` skips assigning the task.
- `--worktree` uses the [devcontainer worktree workflow](#devcontainer-worktree-workflow): instead of checking out the branch in the current repo, creates a fresh git worktree under `~/worktrees/CU-<id>-<slug>` off `origin/master` and wires up the standard node_modules symlinks.  `/workspace` stays on its current branch.  Devcontainer-only.  Cannot be combined with `--no-start`.

### `start` / `cp_start_task <task-id> [--worktree]`

Starts work on a ClickUp task:

1. Fetches task name from ClickUp API.
2. Creates and checks out branch `justin/CU-{taskid}-{slug}` (or checks out if it exists).
3. Marks task as IN PROGRESS in ClickUp.
4. Adds task to the current sprint.

Accepts a task ID or a ClickUp URL (e.g. `https://app.clickup.com/t/86ewdbtbh`).

- `--worktree` replaces step 2 with the [devcontainer worktree workflow](#devcontainer-worktree-workflow): creates a fresh worktree off `origin/master` instead of checking out in the current repo.  Devcontainer-only.

### `pr` / `cp_pr_task [--body DESCRIPTION] [--ai-review | -ar | --greptile] [--no-slack] [--channel CHANNEL_ID]`

Creates or updates a PR for the current branch:

1. Pushes the current branch (sets upstream if needed).
2. Extracts task ID from branch name.
3. Fetches task name/description from ClickUp API.
4. Generates PR title as `[CU-{taskid}] {Capitalized title}`.
5. Creates a **draft** PR with reviewer `Carepatron/platform`, or updates an existing PR.
6. Marks the ClickUp task as IN REVIEW.
7. By default, posts a "PR please\n<url>" Slack message to `$SLACK_PR_NOTIFY_DEFAULT_CHANNEL` (set in `~/.zshrc.local`).  Requires `SLACK_APP_PR_NOTIFY_TOKEN` (see `cp/slack.zsh`).  If neither the env var nor `--channel` is set, the Slack step is silently skipped.

Use `--body` to provide a custom PR description; otherwise uses the ClickUp task description.
Use `--ai-review` (aliases: `-ar`, `--greptile`) to add the `greptile` label so the Greptile AI reviewer bot reviews this PR.
Use `--no-slack` to skip the Slack notification.
Use `--channel <id>` to override the destination channel/DM for a single invocation (otherwise uses `$SLACK_PR_NOTIFY_DEFAULT_CHANNEL`).

#### When to use `--ai-review` / `-ar` / `--greptile`

**Never pass `--ai-review` (or its aliases `-ar`, `--greptile`) unless the operator has explicitly asked for it in the current request.**

Greptile only reviews PRs that carry the `greptile` label, and Greptile runs are expensive — the operator opts in deliberately, per PR.  The agent does not get to judge "this change feels substantive enough, I'll add `--ai-review`".  That judgment is the operator's, not the agent's.

Rules:

- Default: `pr` with no AI-review flag.  This applies to **every** PR — feature work, infrastructure changes, migrations, security-sensitive code, anything.  "Substantive" is not a trigger.
- Add `--ai-review` **only** when the operator's message in the current request contains an explicit instruction to do so.  Examples that count as explicit: "pr with greptile", "pr --ai-review", "use ai review", "add the greptile label", "open this with greptile".
- Examples that do **not** count as explicit: "this is a big change" (operator describing scope, not requesting review), "make sure this is reviewed carefully" (ambiguous — ask), "pr this" (no review flag mentioned — default to no flag).
- If the operator's intent is ambiguous, ask before adding the flag.  Do not infer.
- The operator can always add the `greptile` label to an existing PR after the fact.  Erring toward "no flag" is cheap to undo; erring toward "flag added" wastes a Greptile run.

Reason this rule is strict: previous wording carved out an "add it for substantive changes" exception that the agent leaned on to opt in unilaterally, which is exactly the wrong default.  The operator wants `--ai-review` to be opt-in via explicit instruction, full stop.

### `cleanup` / `cp_cleanup_branches`

Cleans up merged branches:

1. Finds local branches whose remote tracking branch is gone.
2. For each, extracts the task ID and marks the ClickUp task as DONE.
3. Removes worktrees for the gone branches (`git worktree remove`).
4. Deletes the local branches (`git bclean`).

## Investigating CI failures

  The devcontainer's `gh` token lacks perms for status-check rollups and check-run annotations, so several common commands either return 403 or
  fail silently with no output.  Skip the broken ones and use the API-direct path below.

  **Don't use** (will 403 or return nothing — no point retrying):

  - `gh pr checks <pr-number>` — GraphQL rollup, 403s on every status context.
  - `gh run view <run-id>` — 403 fetching annotations.
  - `gh run view <run-id> --log` / `--log-failed` — silent (no output, no error).
  - `gh run view --job <job-id> --log` — same silent failure.

  **Use instead:**

  1. **Find failing runs on the PR's branch.**
     gh run list --branch  --limit 10
  Tab-separated columns:
  `status\tconclusion\tworkflow\tjob\tbranch\tevent\trun-id\tduration\tcreated-at`.  Filter rows where
  `conclusion = failure`.
  
  2. **List jobs inside the failing run** to identify the failing job and its id:
     gh api repos///actions/runs//jobs
       --jq '.jobs[] | {name, conclusion, html_url}'
  The `html_url` ends with `/job/<job-id>`.
  
  3. **Pull the failing job's raw log** (often large — pipe to `tail`/`grep`):
     gh api repos///actions/jobs//logs 2>&1 | tail -80 

  Tip: get `<owner>/<repo>` via `gh repo view --json nameWithOwner -q .nameWithOwner`.

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

## Commits must always run pre-commit hooks (lefthook)

Every `git commit` must run the repo's pre-commit hooks.  No exceptions.

- **Never** pass `--no-verify` / `-n` to `git commit`, `git merge`, `git rebase`, `git cherry-pick`, or `git revert` — even "defensively" or "just for this one fixup".
- **Never** set `LEFTHOOK=0`, `LEFTHOOK_QUIET=…`, `LEFTHOOK_SKIP_OUTPUT=…`, or otherwise tweak lefthook env vars to bypass jobs.  Don't use lefthook's per-job skip flags (`--exclude`, `--no-tty`, custom `LEFTHOOK_EXCLUDE`) either.
- If a pre-commit hook fails, **surface the full hook output and stop**.  Read what failed, fix the underlying issue, re-stage, and commit again.  Do not retry the same commit with hooks disabled.  Do not "work around" by amending after the fact.
- If a hook fails for reasons unrelated to your change (e.g. a broken `openapi-typegen` step, an esbuild platform mismatch, a stale codegen step), **stop and tell the operator**.  Bypassing is never the right fix — the next commit will hit the same wall, and meanwhile real check failures (formatting, non-ASCII, lint errors) slip through silently.
- This applies to every commit the agent makes: feature commits, fixup commits, amends, rebase pickups, cherry-picks.  Even on private branches.  Even on throwaway worktrees.  Even when the next step is going to squash-merge.

Reason: the repo's lefthook config (`lefthook.yml`) is the *only* place CI-equivalent format + lint + non-ASCII + codegen checks run before code leaves the devcontainer.  Skipping it once means the broken commit lands on the PR branch, CI fails, the operator has to context-switch to chase a failure that should have been caught locally, and the PR's review thread gets cluttered with fixup commits for trivial format diffs.  Previous incidents (e.g. PR #18816 — Biome format + non-ASCII both caught by local hooks if they had run) trace to exactly this bypass.  Worse, once `--no-verify` becomes the easy escape for "this hook is being annoying", it becomes muscle memory and every check silently degrades — the agent stops being a backstop and starts being a liability.

## PR creation — always use `pr`, never the `/pr-create` skill

For any request that means "make a PR" — including "pr this", "commit and PR", "create a pull request", "open a PR", "make a draft PR", etc. — run the `pr` zsh alias (`cp_pr_task`) in the shell, not the `/pr-create` skill.

Reason: `pr` does additional useful work the skill doesn't:

- LLM-generated description from branch diff (when `--body` is omitted)
- Auto-opens the PR in browser
- Honours `--ai-review` / `-ar` / `--greptile` for Greptile bot opt-in (only when the operator explicitly asks — see the rule above)
- Marks the ClickUp task as IN REVIEW automatically

## Devcontainer worktree workflow

When the user says "use devcontainer worktree workflow", "use the worktree workflow", "worktree this", or any close variant, use the `--worktree` flag on `new` (for a brand-new task) or `start` (for an existing task ID).  The motivation: each task lives in its own git worktree under `~/worktrees/`, so multiple parallel Claude Code sessions can work on different tasks without colliding on `/workspace`.

```zsh
# Brand-new task — creates ClickUp task + worktree + branch + symlinks + IN PROGRESS + sprint:
new --worktree "Task title" [description]

# Existing task ID:
start --worktree <task-id>
```

Behind the scenes (in `~/dotfiles/cp/{git,workflow}.zsh`), the `--worktree` flag routes through `git_worktree_for_task_branch`, which:

1. `git -C /workspace fetch origin` (so the worktree is rooted at fresh master, not whatever HEAD `/workspace` happens to be on).
2. `git -C /workspace worktree add ~/worktrees/CU-{taskid}-{slug} -b ${ISSUE_BRANCH_PREFIX}/CU-{taskid}-{slug} origin/master`.
3. Symlinks each path in `CP_WORKTREE_NODE_MODULES_PATHS` (defined in `cp/git.zsh`) into the worktree.  Currently three: `/workspace/node_modules`, `/workspace/ui/node_modules`, `/workspace/infra/stacks/public-api/node_modules`.

The function fails fast on conflict (existing worktree path, existing local branch) and prints a `cd ~/worktrees/<slug>` hint at the end.

After the worktree exists:

  1. **`cd ~/worktrees/CU-{taskid}-{slug}/`** and operate inside it using absolute paths.  TDD red/green and other conventions per public-api/design/development.md guidelines.  ExecPlan reads and updates happen inside the worktree (the plan file is in-repo, so the worktree has its own copy).
  2. **Commit.**  Logical units, signed, hooks must run (see signing + lefthook rules above).
  3. **Open the PR.**  From inside the worktree: run `pr` (no `--ai-review` unless the operator explicitly asked for it in the current request — see the "When to use `--ai-review`" rule above).  Per the "always use `pr`, never the `/pr-create` skill" section above.  `pr` works unchanged in a worktree — `git push` and `gh pr` are pwd-aware, and `clickup pr-task` is git-free.
  4. **Update the ExecPlan** if one applies — tick milestone checkboxes, add Surprises/Decisions.  Follow-up commit + `pr` updates the existing PR.
  5. **Leave the worktree in place** until the PR merges.  Post-merge, run `cleanup` (alias for `cp_cleanup_branches`) — it removes worktrees whose upstream is gone, marks the ClickUp task DONE, and deletes the local branch.  Don't manually `git worktree remove` or `git branch -D` without explicit user approval.

### Why this works (background)

A fresh worktree under `~/worktrees/...` has no `node_modules` of its own — but for two different reasons, depending on the path:

- `/workspace/node_modules` is a Docker named volume mounted **only** at `/workspace/node_modules`, so anywhere outside that exact path (including any `~/worktrees/...` directory) sees nothing there.
- `/workspace/ui/node_modules` and `/workspace/infra/stacks/public-api/node_modules` are **part of the host bind mount** (`/workspace` ↔ the macOS host project dir).  They aren't separate volumes; they only exist under `/workspace`.  Anything outside that subtree (again, including `~/worktrees/...`) sees nothing.

In both cases, the symlinks (wired up automatically by `--worktree`) fix it by pointing the worktree at the same files `/workspace` already uses.  Without the symlinks: `yarn` commands fail with "Couldn't find the node_modules state file"; pre-commit `eslint` (lefthook scoped to `ui/`) fails the same way; `npx jest` from `infra/stacks/public-api/` cannot find jest.

The "never run `yarn install`/`npm install` from inside a worktree" rule is about **concurrency, not isolation**: all worktrees and `/workspace` share **one** physical `node_modules` tree (via the symlinks and the bind mount), so two installs racing — one in `/workspace` and one in a worktree, or two worktrees at once — would corrupt that shared tree.  Do installs in `/workspace`, never concurrently with another session.  The one narrow exception: when the install needs to pick up a `.yarnrc.yml`/`package.json` change that only exists in the worktree's branch (e.g. testing a `supportedArchitectures` addition before merge).  In that case, confirm no other session is active and run it from the worktree once.

If a future master adds another yarn/npm project root, the same "state file" error will surface from the new path.  Fix it by adding the path to `CP_WORKTREE_NODE_MODULES_PATHS` in `~/dotfiles/cp/git.zsh`.  To discover candidates: `find /workspace -maxdepth 4 -type d -name node_modules -not -path '*/node_modules/*'`.

### Constraints

- **Never check out a feature branch in `/workspace` itself** — that would block parallel sessions.  All feature work happens in worktrees.
- **Never run `yarn install`** (or any other tool that mutates `node_modules`) from inside a worktree, except for the narrow `.yarnrc.yml`/`package.json` testing exception described above.  Do installs in `/workspace`, never concurrently with another session.
- **Never force-push, `reset --hard`, or `branch -D`** without explicit approval.
- **Use absolute paths** into the worktree directory in tool calls; do not rely on shell `cd` persistence assumptions.
- `~/worktrees/` is per-devcontainer-instance state and is not in dotfiles.
