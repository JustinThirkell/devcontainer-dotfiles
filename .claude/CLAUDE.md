# Personal workflow (Justin)

This file is installed by dotfiles in a devcontainer and describes shell workflow commands available in the devcontainer.
These are zsh functions sourced from `~/dotfiles/cp/` and `~/dotfiles/clickup/`.

## Environment

- `ISSUE_BRANCH_PREFIX=justin`
- `GITHUB_DEFAULT_PR_REVIEWER=Carepatron/platform`
- Branch format: `justin/CU-{taskid}-{slug}` (e.g. `justin/CU-86ewvt64k-unit-tests`)
- PR title format: `[CU-{taskid}] {Capitalized title}` (e.g. `[CU-86ewvt64k] Unit tests`)

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
3. Symlinks each of four hard-coded `node_modules` paths into the worktree (defined inside `git_worktree_for_task_branch` so the list survives Claude Code's shell-snapshot restore — `CP_WORKTREE_NODE_MODULES_PATHS` overrides if set).  Currently four: `/workspace/node_modules`, `/workspace/ui/node_modules`, `/workspace/infra/stacks/public-api/node_modules`, `/workspace/public-api/console/node_modules` (the console SPA's bun project, so vite / vitest / playwright work in a worktree).

The function fails fast on conflict (existing worktree path, existing local branch) and prints a `cd ~/worktrees/<slug>` hint at the end.

After the worktree exists:

  1. **`cd ~/worktrees/CU-{taskid}-{slug}/`** and operate inside it using absolute paths.  TDD red/green and other conventions per public-api/design/development.md guidelines.  ExecPlan reads and updates happen inside the worktree (the plan file is in-repo, so the worktree has its own copy).
  2. **Commit.**  Logical units, signed, hooks must run (see signing + lefthook rules above).
  3. **Open the PR.**  From inside the worktree: for `public-api` work, `/public-api-pr` (no `--ai-review` unless the operator explicitly asked for it in the current request — see the "When to use `--ai-review`" rule above).  Per the "PR creation — for public-api, use `/public-api-pr`, never `/pr-create`" section below.  Everything works unchanged in a worktree — `git push` and `gh pr` are pwd-aware, and `clickup pr-task` is git-free.
  4. **Update the ExecPlan** if one applies — tick milestone checkboxes, add Surprises/Decisions.  Follow-up commit + `pr` updates the existing PR.
  5. **Leave the worktree in place** until the PR merges.  Post-merge, run `cleanup` (alias for `cp_cleanup_branches`) — it removes worktrees whose upstream is gone, marks the ClickUp task DONE, and deletes the local branch.  Don't manually `git worktree remove` or `git branch -D` without explicit user approval.

### Why this works (background)

A fresh worktree under `~/worktrees/...` has no `node_modules` of its own — but for two different reasons, depending on the path:

- `/workspace/node_modules` is a Docker named volume mounted **only** at `/workspace/node_modules`, so anywhere outside that exact path (including any `~/worktrees/...` directory) sees nothing there.
- `/workspace/ui/node_modules` and `/workspace/infra/stacks/public-api/node_modules` are **part of the host bind mount** (`/workspace` ↔ the macOS host project dir).  They aren't separate volumes; they only exist under `/workspace`.  Anything outside that subtree (again, including `~/worktrees/...`) sees nothing.

In both cases, the symlinks (wired up automatically by `--worktree`) fix it by pointing the worktree at the same files `/workspace` already uses.  Without the symlinks: `yarn` commands fail with "Couldn't find the node_modules state file"; pre-commit `eslint` (lefthook scoped to `ui/`) fails the same way; `npx jest` from `infra/stacks/public-api/` cannot find jest.

The "never run `yarn install`/`npm install` from inside a worktree" rule is about **concurrency, not isolation**: all worktrees and `/workspace` share **one** physical `node_modules` tree (via the symlinks and the bind mount), so two installs racing — one in `/workspace` and one in a worktree, or two worktrees at once — would corrupt that shared tree.  Do installs in `/workspace`, never concurrently with another session.  The one narrow exception: when the install needs to pick up a `.yarnrc.yml`/`package.json` change that only exists in the worktree's branch (e.g. testing a `supportedArchitectures` addition before merge).  In that case, confirm no other session is active and run it from the worktree once.

If a future master adds another yarn/npm project root, the same "state file" error will surface from the new path.  Fix it by adding the path to the `worktree_paths` default list inside `git_worktree_for_task_branch` in `~/dotfiles/cp/git.zsh` (or, for a one-off, export `CP_WORKTREE_NODE_MODULES_PATHS=(…)` before invoking the workflow).  To discover candidates: `find /workspace -maxdepth 4 -type d -name node_modules -not -path '*/node_modules/*'`.

### Constraints

- **Never check out a feature branch in `/workspace` itself** — that would block parallel sessions.  All feature work happens in worktrees.
- **Never run `yarn install`** (or any other tool that mutates `node_modules`) from inside a worktree, except for the narrow `.yarnrc.yml`/`package.json` testing exception described above.  Do installs in `/workspace`, never concurrently with another session.
- **Never force-push, `reset --hard`, or `branch -D`** without explicit approval.
- **Use absolute paths** into the worktree directory in tool calls; do not rely on shell `cd` persistence assumptions.
- `~/worktrees/` is per-devcontainer-instance state and is not in dotfiles.

## Implementing a plan (`implement @<...>.plan.md`)

When the user says **"implement @<path>.plan.md"** (or a close variant — "implement this plan", "build out @foo.plan.md", etc.), treat it as the standing public-api implementation kickoff and apply these defaults without needing them spelled out:

1. **Use the devcontainer worktree workflow** — `start --worktree <task-id>` (or `new --worktree`), per the [Devcontainer worktree workflow](#devcontainer-worktree-workflow) section above.  Operate inside the worktree using absolute paths.
   - Exception: if the user explicitly says to use the current branch / `/workspace` (e.g. "implement @plan using current branch"), honour that instead of creating a worktree.
2. **Implement per the plan and the repo standards** — red/green TDD with visible cycles, signed commits that run the pre-commit hooks, and keep the plan's Progress/checkboxes current as work lands (all per the repo's `AGENTS.md` / `public-api/design/development.md`).
3. **On completion, issue the PR with `/public-api-pr`** — the default review-and-ship route (silent draft -> fresh no-context `public-api-code-review` + CI loop -> converge -> un-draft + reviewer ping).  Use the skip route (`/public-api-pr` with "no review" / "quick pr" / `--skip-review`) only when the user asked for a quick PR.  Do not pass `--ai-review`/greptile unless the user explicitly asked (see the `--ai-review` rule above).

The point is that a terse "implement @foo.plan.md" should do the right thing end-to-end; the operator no longer needs to restate "using devcontainer workflow" or "use /public-api-pr" each time.  Naming the route explicitly in the prompt still works and overrides the default.

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

*Note:  Almost always you should use `/public-api-pr` instead of `pr` directly.*

### `/public-api-pr` for PR creation

*For public-api, use `/public-api-pr`, never `/pr-create`*

For any request that means "make a PR" — "pr this", "commit and PR", "create a pull request", "open a PR", "make a draft PR", etc. — on **`public-api`** work the agent issues it through **`/public-api-pr`**, not the repo-level **`/pr-create`** skill, and not by running the bare `pr` alias itself.

The distinction that matters: `/pr-create` is the generic, repo-level PR skill; **`/public-api-pr` is the public-api PR process** — it wraps the `pr` shell function (so the ClickUp IN REVIEW transition, the title/body, the reviewer assignment, and the browser-open all still happen) and adds the fresh no-context `/public-api-code-review` + CI loop on top.  For a quick PR with no self-review, invoke `/public-api-pr` with skip intent ("quick pr" / "no review" / `--skip-review`); that delegates to a bare `pr`.  Either way the agent goes through `/public-api-pr`, not `/pr-create` and not the raw alias.

- **Outside `public-api`** (e.g. `ui/`), `/public-api-pr` doesn't apply — fall back to the `pr` zsh alias (`cp_pr_task`) in the shell, still never `/pr-create`.

The bare `pr` alias stays the **operator's own** manual terminal route: if I (Justin) want a raw `pr`, I run it myself — I don't need to ask the agent.

Never use `/pr-create`: `pr` (and `/public-api-pr` on top of it) does useful work it doesn't — an LLM/ClickUp-sourced description, auto-opening the PR in the browser, `--ai-review`/greptile opt-in (only when explicitly asked — see the rule above), and the ClickUp IN REVIEW transition.

### ClickUp CLI (`clickup <command>`)

Low-level wrapper around the ClickUp API (via `~/dotfiles/clickup/clickup.ts`):

- `clickup whoami` — show ClickUp user info
- `clickup get-task <id>` — fetch task details (JSON)
- `clickup start-task <id>` — set status to IN PROGRESS
- `clickup pr-task <id>` — set status to IN REVIEW
- `clickup complete-task <id>` — set status to DONE
- `clickup create-task <title> <description>` — create a task
- `clickup add-task-to-current-sprint <id>` — move task to current sprint

All commands accept `--debug` for verbose output.

## Git commit rules

### Commits must always be signed

Every `git commit` must be signed.  No exceptions.

- **Never** pass `--no-gpg-sign`, `-c commit.gpgsign=false`, `-c gpg.format=…` to bypass or alter signing — even "defensively" or "to skip a hook".
- The devcontainer is pre-configured with SSH-key signing (`commit.gpgsign=true`, `gpg.format=ssh`, key at `~/.ssh/id_ed25519_signing`).  Trust it.  Don't probe it.
- If a `git commit` fails *because of* signing (key not found, agent locked, etc.), **surface the error and stop** — do not retry with signing disabled.  Ask the operator to fix the signing setup.
- This applies to every commit the agent makes: feature commits, fixup commits, amends, rebases.  Even on private branches.  Even on throwaway worktrees.  Even when the next step is going to squash-merge.

Reason: signed commits are the audit trail.  An unsigned commit on a feature branch survives review noise and ends up referenced from PR comments, rollback investigations, and bisects long after merge — even when the squash-merge commit on master is signed.  Mixed-signature branches signal "agent did something weird here" and erode trust in *every* commit on the branch.

### Commits must always run pre-commit hooks (lefthook)

Every `git commit` must run the repo's pre-commit hooks.  No exceptions.

- **Never** pass `--no-verify` / `-n` to `git commit`, `git merge`, `git rebase`, `git cherry-pick`, or `git revert` — even "defensively" or "just for this one fixup".
- **Never** set `LEFTHOOK=0`, `LEFTHOOK_QUIET=…`, `LEFTHOOK_SKIP_OUTPUT=…`, or otherwise tweak lefthook env vars to bypass jobs.  Don't use lefthook's per-job skip flags (`--exclude`, `--no-tty`, custom `LEFTHOOK_EXCLUDE`) either.
- If a pre-commit hook fails, **surface the full hook output and stop**.  Read what failed, fix the underlying issue, re-stage, and commit again.  Do not retry the same commit with hooks disabled.  Do not "work around" by amending after the fact.
- If a hook fails for reasons unrelated to your change (e.g. a broken `openapi-typegen` step, an esbuild platform mismatch, a stale codegen step), **stop and tell the operator**.  Bypassing is never the right fix — the next commit will hit the same wall, and meanwhile real check failures (formatting, non-ASCII, lint errors) slip through silently.
- This applies to every commit the agent makes: feature commits, fixup commits, amends, rebase pickups, cherry-picks.  Even on private branches.  Even on throwaway worktrees.  Even when the next step is going to squash-merge.

Reason: the repo's lefthook config (`lefthook.yml`) is the *only* place CI-equivalent format + lint + non-ASCII + codegen checks run before code leaves the devcontainer.  Skipping it once means the broken commit lands on the PR branch, CI fails, the operator has to context-switch to chase a failure that should have been caught locally, and the PR's review thread gets cluttered with fixup commits for trivial format diffs.  Previous incidents (e.g. PR #18816 — Biome format + non-ASCII both caught by local hooks if they had run) trace to exactly this bypass.  Worse, once `--no-verify` becomes the easy escape for "this hook is being annoying", it becomes muscle memory and every check silently degrades — the agent stops being a backstop and starts being a liability.

### Commit messages — never prefix with the `[CU-...]` task id

Git **commit message** subjects must **not** start with `[CU-{taskid}]` (or any ClickUp task id).  Write a plain, conventional subject line that describes the change (e.g. `HostEnvironment: introduce Backend + KestrelListenPort`).

The `[CU-{taskid}]` prefix belongs **only** to PR titles and branch names — and both are generated for you by the workflow commands, never hand-typed: `pr` (`cp_pr_task`) formats the PR title as `[CU-{taskid}] {Capitalized title}`, and `start` / `new` create the `justin/CU-{taskid}-{slug}` branch.  Leave the prefix to those commands; never add it to a `git commit` yourself.  This applies to every commit the agent makes: feature commits, fixup commits, amends, rebases.

Reason: `git log` on `master` *looks* like every commit is `[CU-...]`-prefixed, so an agent that pattern-matches the log will copy the prefix onto every feature-branch commit.  But that prefix is the **PR title** showing through — master is squash-merged and the squash commit inherits the PR title, which is the only reason the id appears in the log.  It is not a per-commit convention.  Hand-adding it is pure noise: the branch is already named `…/CU-{taskid}-…`, the PR already carries the id, and the squash-merge replaces the subject with the PR title anyway — so the prefix on a branch commit conveys nothing and just clutters review.

## Investigating CI failures

The devcontainer's `gh` is authenticated with a fine-grained PAT, and the **only** thing that genuinely doesn't work is the status-check *rollup* — GitHub does not allow `checks:read` on fine-grained PATs.

**Avoid:**

- `gh pr checks <pr-number>` — GraphQL `statusCheckRollup` -> "Resource not accessible by personal access token".  No workaround on a fine-grained PAT; use `gh run list` instead.

**These work (on completed runs):**

- `gh run view <run-id>` — shows the job list and per-job status.  Only its trailing `ANNOTATIONS` section 403s (the same `checks:read` gap) — ignore that one section.
- `gh run view <run-id> --log` and `gh run view --job <job-id> --log` — print the full logs.  (A `141` exit when you pipe to `head` is just SIGPIPE, not a failure.)

**Scriptable path (handy for filtering large logs):**

1. Find runs on the PR's branch (filter `conclusion == "failure"`; for the current HEAD only, also `headSha == $(git rev-parse HEAD)`):

   ```bash
   gh run list --branch "<branch>" --limit 10 \
     --json databaseId,headSha,status,conclusion,workflowName
   ```

2. List the jobs in a run to find the failing job id (`html_url` ends with `/job/<job-id>`):

   ```bash
   gh api "repos/<owner>/<repo>/actions/runs/<run-id>/jobs" \
     --jq '.jobs[] | {name, conclusion, html_url}'
   ```

3. Pull a job's raw log (often large — pipe to `tail` / `grep`):

   ```bash
   gh api "repos/<owner>/<repo>/actions/jobs/<job-id>/logs" 2>&1 | tail -80
   ```

Tip: get `<owner>/<repo>` via `gh repo view --json nameWithOwner -q .nameWithOwner`.

