# Justin workflow reference (background / rationale)

Read this on demand - it is NOT part of the per-turn `~/.claude/CLAUDE.md`.  It holds the full "why" behind the terse rules in CLAUDE.md, moved here so it doesn't cost tokens on every turn.  Installed alongside CLAUDE.md as `~/.claude/workflow-reference.md`.

For what a command *does*, `.devcontainer/tooling/README.md` in the Carepatron-App repo is authoritative - it sits beside the code, under review, and behind the 300-odd checks in `.devcontainer/test/verify-static.sh`.  What is here is the part that file cannot hold: my preferences, and the reasoning behind them.

## Credentials: there are none in the container

`CLICKUP_API_KEY`, `SLACK_APP_PR_NOTIFY_TOKEN` and `GH_TOKEN` are all set to the literal string `placeholder-the-egress-proxy-replaces-this-header`.  `api.clickup.com`, `slack.com` and `api.github.com` are steered to an injecting egress proxy that attaches the real credential on the way out, from the host.

A placeholder has to be *present* because each of these tools refuses to send a request while it believes it is unauthenticated - `gh` fails before the proxy can attach anything, `clickup` exits on an unset key, `slack_post_message` returns early on an empty token.  It must not be a real one, so that if it ever reaches an API the resulting 401 is unambiguous: injection stopped.

The practical rule for an agent: a 401 from any of the three is an infrastructure fault to report, not a credential to chase.  There is nothing in the container to rotate, and nothing to set.

## Worktree: why the node_modules symlinks are needed

A fresh worktree under `~/worktrees/...` has no node_modules of its own, for two different reasons:

- `/workspace/node_modules` is a Docker named volume mounted **only** at that exact path - invisible anywhere outside it (including any worktree).
- The rest (`ui/`, `infra/stacks/`, `public-api/`) are part of the host bind mount; they exist only under `/workspace`.

The `--worktree` symlinks point the worktree at the same files `/workspace` uses.  Without them: `yarn` -> "Couldn't find the node_modules state file"; pre-commit eslint (lefthook scoped to ui/) fails the same way; `npx jest` from an infra stack cannot find jest; pre-commit `generate > openapi-typegen` (any commit staging `openapi/`) writes all ~105 files then dies in `rtkq-postprocess` with "Cannot find module .../ui/types/carepatron-api/node_modules/cross-env/dist/bin/cross-env.js", and its `set -eu` turns that into a blocked commit.

`git_worktree_for_task_branch` treats a missing source as fatal and refuses rather than half-wiring, because a worktree short of one link fails later inside yarn or eslint against a state file rather than against the link.  On failure it prints the exact `mkdir -p && ln -s` for each one it could not create.

**`ui/types/carepatron-api/node_modules` is still missing from `worktree_paths`** even though it exists under `/workspace`, so the openapi-typegen failure above is live.  It bites on any commit that stages `openapi/**` - which includes merging an `origin/master` that moved `openapi/carepatron-api-v1.json`, not just deliberate openapi work.  Link it by hand after creating a worktree, or add it to the list:

```bash
ln -s /workspace/ui/types/carepatron-api/node_modules "$WT/ui/types/carepatron-api/node_modules"
```

## Worktree: the never-`yarn install`-in-a-worktree rule (concurrency, not isolation)

All worktrees and `/workspace` share ONE physical node_modules tree (via symlinks + bind mount).  Two installs racing - `/workspace` + a worktree, or two worktrees - would corrupt it.  Do installs in `/workspace`, never concurrently with another session.  Narrow exception: when the install must pick up a `.yarnrc.yml` / `package.json` change that exists only on the worktree's branch (e.g. testing a `supportedArchitectures` addition pre-merge) - confirm no other session is active and run it from the worktree once.

`~/worktrees/` is per-devcontainer-instance state and is not in dotfiles.  It is also not merely a convention: the baked `settings/gitconfig-system` exempts `~/worktrees/*` from git's ownership check and scopes fsmonitor to the gitdirs underneath it, and neither entry matches by prefix - so a worktree created anywhere else is refused on any ownership hiccup while the checkout beside it is fine.  `CP_WORKTREE_ROOT` exists to move it on a host seat, which has no baked gitconfig to disagree with; it is unset in the container and should stay that way.

## Worktree: why `new --worktree` is the default (never ask "new or reuse?")

"use devcontainer workflow" and "implement @<plan>" must be autonomous through task creation.  The only disambiguator is whether the *current request* supplies an explicit task id / ClickUp URL: yes -> `start --worktree <id>`; no -> `new --worktree`, full stop.  A plan/design file, a milestone or PR-split being continued, and prior/merged/related ClickUp tasks are context, not a task id - treating them as a reason to reuse an old task or to raise a "which task?" HITL prompt stalls exactly the workflow the operator asked to run autonomously (and the related tasks are typically already merged/closed anyway).  This is the same failure mode as the old `--ai-review` "substantive changes" carve-out: given any wiggle room the agent invents a "but this looks related" exception and deviates from the default.  There is no such exception.  Erring toward a fresh task is cheap (a stray empty task is trivially cleaned up); stopping to ask burns a turn on a decision the operator has repeatedly signalled they don't want to make.

`cp_pr_task` (and `/public-api-pr` on top of it) does work `/pr-create` doesn't: an LLM/ClickUp-sourced description, auto-open in the browser, `--ai-review`/greptile opt-in (only when explicitly asked), and the ClickUp IN REVIEW transition.  `/pr-create` and `/pr-review` are both set to `"off"` in my `skillOverrides`, so they cannot be invoked at all - the rule is enforced by configuration now rather than by instruction.

## `--ai-review` - full rationale

Greptile only reviews PRs carrying the `greptile` label, and runs are expensive; the operator opts in per PR.  The agent does not get to judge "substantive enough".  A previous wording carved out a "substantive changes" exception that the agent leaned on to opt in unilaterally - exactly the wrong default.  Opt-in via explicit instruction, full stop.  The operator can add the label after the fact; erring toward "no flag" is cheap to undo, erring toward "flag added" wastes a run.

## Git commit rules - full rationale

**Signing.**  Signed commits are the audit trail.  An unsigned commit on a feature branch survives review noise and ends up referenced from PR comments, rollback investigations, and bisects long after merge - even when the squash-merge on master is signed.  Mixed-signature branches signal "agent did something weird here" and erode trust in every commit on the branch.  The private key never reaches the container: it lives in a signing-only agent on the host, forwarded over a socket, and `configure-git-signing.sh` makes a real commit and requires `%G?` to be `G` before the container finishes starting.  There is no key-source setting and no off switch to reach for.

**Hooks.**  The repo's `lefthook.yml` is the only place CI-equivalent format + lint + non-ASCII + codegen checks run before code leaves the devcontainer.  Skipping once = the broken commit lands on the PR branch, CI fails, the operator context-switches to chase a failure that should have been caught locally, and the review thread gets cluttered with fixup commits for trivial format diffs (e.g. PR #18816 - Biome format + non-ASCII, both catchable locally).  Once `--no-verify` becomes the easy escape, every check silently degrades.

**No `[CU-]` in commit subjects.**  `git log` on master looks fully `[CU-]`-prefixed, so a pattern-matching agent copies the prefix onto every branch commit.  But that prefix is the PR title showing through the squash-merge - not a per-commit convention.  The branch is already `.../CU-{id}-...`, the PR carries the id, and squash-merge replaces the subject with the PR title anyway, so the prefix on a branch commit conveys nothing and just clutters review.

**Pushing `.github/workflows/`.**  Plain `git push` handles it.  This used to be the one thing the container could not do - pushes went over SSH on a deploy key, and GitHub bars deploy keys from workflow files regardless of write access - and a `git_push_via_pat` / `gp-workflows` helper existed to route that one push over HTTPS.  That helper is **deleted**, and `verify-static.sh` asserts it stays deleted: it has nothing left to escape now that pushes travel over HTTPS with a proxy-attached PAT carrying `Workflows: write`, and it would actively break, because it supplied its own credential via `gh auth git-credential` - which in this container is the `GH_TOKEN` placeholder.  A rejection on a workflow push is that PAT's permission, not the transport.

## Workflow commands - the parts that surprise

Flags and behaviour are in `.devcontainer/tooling/README.md` and behind `--help` on every command.  What follows is only what is easy to get wrong.

### `cp_new_task <title> [description] [--no-assignment] [--no-start] [--worktree]`

`--worktree` cannot be combined with `--no-start`, and is devcontainer-only in the sense that it wants a checkout with node_modules beside it; `/workspace` stays put either way.

### `cp_start_task <task-id> [--worktree]`

Fetch name from ClickUp, create/checkout `justin/CU-{taskid}-{slug}`, mark IN PROGRESS, add to the current sprint.  Accepts a task id or a ClickUp URL.  `--worktree` replaces the checkout with a fresh worktree off `origin/master`.

### `cp_pr_task [--body DESCRIPTION] [--ai-review|-ar|--greptile] [--no-slack] [--channel CHANNEL_ID]`

Push (setting upstream when unset), extract the task id from the branch, fetch the name/description, title `[CU-{taskid}] {Capitalized title}`, open or update a draft PR with reviewer `$GITHUB_DEFAULT_PR_REVIEWER`, mark IN REVIEW, then post "PR please\n<url>" to `$SLACK_PR_NOTIFY_DEFAULT_CHANNEL`.

Three behaviours worth knowing:

- **On an update it does not notify at all.**  If the PR already existed it returns before the Slack step, independent of `--no-slack`.  So re-running `pr` to refresh a title does not double-ping - and `/public-api-pr` relies on this, opening the PR silently and leaving the ping to `cp_pr_mark_ready_for_review`.
- **An unset channel is a hard failure, not a quiet skip.**  Once it has decided a notification was wanted, `require_local_config SLACK_PR_NOTIFY_DEFAULT_CHANNEL` returns non-zero rather than reporting success with nobody told.  (This is a change - it used to pass silently unless `--debug`.)
- **The body is clobber-guarded on update.**  It is only overwritten when an explicit `--body` was passed, because it may have been hand-edited or authored by `/public-api-pr`.  The title is always refreshed.  The body otherwise comes from the ClickUp description captured at task-creation time, so it is stale whenever the design pivoted mid-work - fix that with `gh pr edit --body-file`.

`--no-slack` is opt-in only; do not pass it defensively, same rule as `--ai-review`.

### `cp_pr_mark_ready_for_review [--note <text>]`

Flips the draft PR to ready and sends the "PR please" ping.  `--note` appends Slack mrkdwn after a blank line, which is how `/public-api-pr` inlines its pre-review summary so the reviewer sees the result in the same DM as the nudge.

It checks the channel and the token *before* flipping, because `gh pr ready` does not roll back and pinging is the whole point - checking afterwards would leave a PR advertised as ready with nobody told.  Renamed from `cp_pr_ship`, whose name implied merge/deploy.  No alias: the controller skill calls the function directly.

### `cp_cleanup_branches` and `cp_cleanup_aborted_prs [--yes]`

Two different situations, and the first does not cover the second.

`cp_cleanup_branches` works from `git gone` - local branches whose remote upstream is already deleted, i.e. the aftermath of a **merge**.  It marks each task DONE, removes the worktree, and deletes the local branch.

`cp_cleanup_aborted_prs` handles a PR **closed without merging**, which leaves the branch on origin and the task short of DONE.  It deletes the head branch on origin and deletes the matching ClickUp task.  Dry-run by default; `--yes` does both, and is forwarded to `clickup delete-task` as its confirmation.  It skips the currently checked-out branch.

### ClickUp CLI (`clickup <command>`)

`whoami` / `get-task <id>` / `start-task <id>` / `pr-task <id>` / `complete-task <id>` / `create-task <title> <desc>` / `add-task-to-current-sprint <id>` / `delete-task <id>`.  All accept `--debug`, and it also reads `CLICKUP_DEBUG` - which is the one to reach for when something fails several frames down, because `cp_new_task` and `cp_start_task` call `clickup` without forwarding their own `--debug`:

```bash
CLICKUP_DEBUG=true cp_new_task "Some title"
```

`delete-task` is the only command in the tree that destroys anything, and everything in the tree is reachable by any process in the container - so it confirms first.  With a terminal it requires the **task ID typed back**.  Without one there is nothing to ask, so the absence of `--yes` means refuse: that covers every agent tool call, because prompting into a closed stdin reads EOF and reading EOF as assent deletes.

### `aws-login` / `aws-check-session`

`aws-login` runs `aws sso login` then a root-owned assertion baked into the image, which requires the role-session name to end `.ai` and the permission set to end `-Ai-Access`; `aws-check-session` runs the same assertion against the session you already have.  The guard is in the shell *function* rather than only the `bin/` shim because in zsh a function shadows a same-named executable on `PATH`, so an interactive `aws-login` would never reach the shim.

## Investigating CI failures - full scriptable path

Only the status-check rollup is broken: `gh pr checks` -> "Resource not accessible by personal access token" (`checks:read` is ungrantable on fine-grained PATs).  These work on completed runs:

- `gh run view <run-id>` - job list and per-job status (ignore the trailing ANNOTATIONS 403).
- `gh run view <run-id> --log` and `gh run view --job <job-id> --log` - full logs (a 141 exit on `| head` is just SIGPIPE).

Scriptable path:

1. `gh run list --branch "<branch>" --limit 10 --json databaseId,headSha,status,conclusion,workflowName` (filter `conclusion == "failure"`; for current HEAD only, also `headSha == $(git rev-parse HEAD)`).
2. `gh api "repos/<owner>/<repo>/actions/runs/<run-id>/jobs" --jq '.jobs[] | {name, conclusion, html_url}'` (html_url ends with `/job/<job-id>`).
3. `gh api "repos/<owner>/<repo>/actions/jobs/<job-id>/logs" 2>&1 | tail -80`.

Get `<owner>/<repo>` via `gh repo view --json nameWithOwner -q .nameWithOwner`.

The PAT is not in the container - the proxy holds it and attaches it, sourced from 1Password on the host.  So widening its permissions is a host-side change plus an org-owner approval at `https://github.com/organizations/Carepatron/settings/personal-access-token-requests`, and is not something an agent can act on locally.
