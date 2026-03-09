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

  ### `pr` / `cp_pr_task [--body DESCRIPTION]`

  Creates or updates a PR for the current branch:

  1. Pushes the current branch (sets upstream if needed).
  2. Extracts task ID from branch name.
  3. Fetches task name/description from ClickUp API.
  4. Generates PR title as `[CU-{taskid}] {Capitalized title}`.
  5. Creates a **draft** PR with reviewer `Carepatron/platform`, or updates an existing PR.
  6. Marks the ClickUp task as IN REVIEW.

  Use `--body` to provide a custom PR description; otherwise uses the ClickUp task description.

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

  ## When asked to "pr this"

  Run `pr` (alias for `cp_pr_task`) in the shell.  Generate a concise summary of the changes first and pass it with `--body`.