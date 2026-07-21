# Justin workflow reference (background / rationale)

Read this on demand - it is NOT part of the per-turn `~/.claude/CLAUDE.md`.  It holds the full "why" behind the terse rules in CLAUDE.md, moved here so it doesn't cost tokens on every turn.  Install alongside CLAUDE.md as `~/dotfiles/.claude/workflow-reference.md`.

## Worktree: why the node_modules symlinks are needed

A fresh worktree under `~/worktrees/...` has no node_modules of its own, for two different reasons:

- `/workspace/node_modules` is a Docker named volume mounted **only** at that exact path - invisible anywhere outside it (including any worktree).
- `/workspace/ui/node_modules` and `/workspace/infra/stacks/public-api/node_modules` are part of the host bind mount; they exist only under `/workspace`.

The `--worktree` symlinks point the worktree at the same files `/workspace` uses.  Without them: `yarn` -> "Couldn't find the node_modules state file"; pre-commit eslint (lefthook scoped to ui/) fails the same way; `npx jest` from infra/stacks/public-api/ cannot find jest.  Current symlinked paths: `/workspace/node_modules`, `/workspace/ui/node_modules`, `/workspace/infra/stacks/public-api/node_modules`, `/workspace/public-api/console/node_modules`.

## Worktree: the never-`yarn install`-in-a-worktree rule (concurrency, not isolation)

All worktrees and `/workspace` share ONE physical node_modules tree (via symlinks + bind mount).  Two installs racing - `/workspace` + a worktree, or two worktrees - would corrupt it.  Do installs in `/workspace`, never concurrently with another session.  Narrow exception: when the install must pick up a `.yarnrc.yml` / `package.json` change that exists only on the worktree's branch (e.g. testing a `supportedArchitectures` addition pre-merge) - confirm no other session is active and run it from the worktree once.

`~/worktrees/` is per-devcontainer-instance state and is not in dotfiles.

## Worktree: why `new --worktree` is the default (never ask "new or reuse?")

"use devcontainer workflow" and "implement @<plan>" must be autonomous through task creation.  The only disambiguator is whether the *current request* supplies an explicit task id / ClickUp URL: yes -> `start --worktree <id>`; no -> `new --worktree`, full stop.  A plan/design file, a milestone or PR-split being continued, and prior/merged/related ClickUp tasks are context, not a task id - treating them as a reason to reuse an old task or to raise a "which task?" HITL prompt stalls exactly the workflow the operator asked to run autonomously (and the related tasks are typically already merged/closed anyway).  This is the same failure mode as the old `--ai-review` "substantive changes" carve-out: given any wiggle room the agent invents a "but this looks related" exception and deviates from the default.  There is no such exception.  Erring toward a fresh task is cheap (a stray empty task is trivially cleaned up via `cleanup`); stopping to ask burns a turn on a decision the operator has repeatedly signalled they don't want to make.

`pr` (and `/public-api-pr` on top of it) does work `/pr-create` doesn't: an LLM/ClickUp-sourced description, auto-open in the browser, `--ai-review`/greptile opt-in (only when explicitly asked), and the ClickUp IN REVIEW transition.

## `--ai-review` - full rationale

Greptile only reviews PRs carrying the `greptile` label, and runs are expensive; the operator opts in per PR.  The agent does not get to judge "substantive enough".  A previous wording carved out a "substantive changes" exception that the agent leaned on to opt in unilaterally - exactly the wrong default.  Opt-in via explicit instruction, full stop.  The operator can add the label after the fact; erring toward "no flag" is cheap to undo, erring toward "flag added" wastes a run.

## Git commit rules - full rationale

**Signing.**  Signed commits are the audit trail.  An unsigned commit on a feature branch survives review noise and ends up referenced from PR comments, rollback investigations, and bisects long after merge - even when the squash-merge on master is signed.  Mixed-signature branches signal "agent did something weird here" and erode trust in every commit on the branch.

**Hooks.**  The repo's `lefthook.yml` is the only place CI-equivalent format + lint + non-ASCII + codegen checks run before code leaves the devcontainer.  Skipping once = the broken commit lands on the PR branch, CI fails, the operator context-switches to chase a failure that should have been caught locally, and the review thread gets cluttered with fixup commits for trivial format diffs (e.g. PR #18816 - Biome format + non-ASCII, both catchable locally).  Once `--no-verify` becomes the easy escape, every check silently degrades.

**No `[CU-]` in commit subjects.**  `git log` on master looks fully `[CU-]`-prefixed, so a pattern-matching agent copies the prefix onto every branch commit.  But that prefix is the PR title showing through the squash-merge - not a per-commit convention.  The branch is already `.../CU-{id}-...`, the PR carries the id, and squash-merge replaces the subject with the PR title anyway, so the prefix on a branch commit conveys nothing and just clutters review.

## Workflow commands - full flag reference

### `new` / `cp_new_task <title> [description] [--no-assignment] [--no-start] [--worktree]`

Creates a ClickUp task and (by default) starts it via `cp_start_task`.

- `--no-start`: create without starting.
- `--no-assignment`: skip assigning.
- `--worktree`: worktree workflow instead of checking out in the current repo; `/workspace` stays put.  Devcontainer-only.  Cannot combine with `--no-start`.

### `start` / `cp_start_task <task-id> [--worktree]`

1. Fetch task name from ClickUp.  2. Create/checkout `justin/CU-{taskid}-{slug}` (or checkout if it exists).  3. Mark IN PROGRESS.  4. Add to current sprint.  Accepts a task id or a ClickUp URL.

- `--worktree`: replaces step 2 with a fresh worktree off origin/master.

### `cleanup` / `cp_cleanup_branches`

1. Find local branches whose remote tracking branch is gone.  2. Mark each one's ClickUp task DONE.  3. `git worktree remove`.  4. `git bclean` (delete the local branches).

### `pr` / `cp_pr_task [--body DESCRIPTION] [--ai-review|-ar|--greptile] [--no-slack] [--channel CHANNEL_ID]`

1. Push (set upstream if needed).  2. Extract task id from branch.  3. Fetch task name/description.  4. Title `[CU-{taskid}] {Capitalized title}`.  5. Draft PR, reviewer Carepatron/platform, or update existing.  6. Mark IN REVIEW.  7. Post "PR please\n<url>" to `$SLACK_PR_NOTIFY_DEFAULT_CHANNEL` (needs `SLACK_APP_PR_NOTIFY_TOKEN`; skipped if unset).

- `--body`: custom PR description (else the ClickUp description).  `--no-slack`: skip Slack (do not pass defensively - opt-in only, like `--ai-review`).  `--channel`: override destination for one invocation.

On UPDATE, the body is only overwritten when an explicit `--body` was passed (clobber-guard - the body may have been hand-edited or authored by `/public-api-pr`); the title is always refreshed.  Prefer `/public-api-pr` over the bare `pr`.

### ClickUp CLI (`clickup <command>`)

`whoami` / `get-task <id>` / `start-task <id>` / `pr-task <id>` / `complete-task <id>` / `create-task <title> <desc>` / `add-task-to-current-sprint <id>`.  All accept `--debug`.

## Investigating CI failures - full scriptable path

Only the status-check rollup is broken: `gh pr checks` -> "Resource not accessible by personal access token" (`checks:read` ungrantable on fine-grained PATs).  These work on completed runs:

- `gh run view <run-id>` - job list and per-job status (ignore the trailing ANNOTATIONS 403).
- `gh run view <run-id> --log` and `gh run view --job <job-id> --log` - full logs (a 141 exit on `| head` is just SIGPIPE).

Scriptable path:

1. `gh run list --branch "<branch>" --limit 10 --json databaseId,headSha,status,conclusion,workflowName` (filter `conclusion == "failure"`; for current HEAD only, also `headSha == $(git rev-parse HEAD)`).
2. `gh api "repos/<owner>/<repo>/actions/runs/<run-id>/jobs" --jq '.jobs[] | {name, conclusion, html_url}'` (html_url ends with `/job/<job-id>`).
3. `gh api "repos/<owner>/<repo>/actions/jobs/<job-id>/logs" 2>&1 | tail -80`.

Get `<owner>/<repo>` via `gh repo view --json nameWithOwner -q .nameWithOwner`.
