cp_new_task() {
  local title=""
  local description=""
  local no_assignment=false
  local start=true
  local use_worktree=false
  local DEBUG=false

  local help_text='Usage: cp_new_task <title> [description] [--no-assignment] [--no-start] [--worktree] [--debug] [-h|--help]

Creates a ClickUp task and (by default) immediately starts it via cp_start_task.

Options:
  --no-assignment   Skip assigning the task.
  --no-start        Create the task without starting work on it.
  --worktree        Devcontainer worktree workflow: instead of checking out
                    the branch in the current repo, create a fresh git worktree
                    under ~/worktrees/CU-<id>-<slug> off origin/master and wire
                    up the standard node_modules symlinks.  /workspace stays on
                    its current branch.  Devcontainer-only.
  --debug           Verbose output.
  -h, --help        Show this help.

Example: cp_new_task "Fix login bug" "Description of the fix"
         cp_new_task --worktree "Refactor auth"  # parallel session in a worktree'

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)
      echo "$help_text"
      return 0
      ;;
    --no-assignment)
      no_assignment=true
      shift
      ;;
    --no-start)
      start=false
      shift
      ;;
    --worktree)
      use_worktree=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      if [[ -z "$title" ]]; then
        title="$1"
      elif [[ -z "$description" ]]; then
        description="$1"
      else
        error "Unknown option or too many arguments: $1"
        echo "$help_text"
        return 1
      fi
      shift
      ;;
    esac
  done

  if [[ -z "$title" ]]; then
    error "Title is required"
    echo "$help_text"
    return 1
  fi

  if [[ "$use_worktree" == "true" && "$start" != "true" ]]; then
    error "--worktree is only meaningful with --start (the default).  Drop --no-start, or drop --worktree."
    return 1
  fi

  if [[ -z "$description" ]]; then
    description="$title"
    [[ "$DEBUG" == "true" ]] && debug "No description provided; defaulting description to title"
  fi

  info "Creating ClickUp task: $title"
  local create_result
  if [[ "$no_assignment" == "true" ]]; then
    create_result=$(clickup create-task "$title" "$description" --no-assignment)
  else
    create_result=$(clickup create-task "$title" "$description")
  fi
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    error "Failed to create ClickUp task"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "Raw create-task output: $create_result"

  local sanitized_result
  sanitized_result=$(tr -d '\000-\037' <<<"$create_result")
  local task_id
  task_id=$(jq -r '.id' <<<"$sanitized_result")

  if [[ -z "$task_id" || "$task_id" == "null" ]]; then
    error "Could not extract task ID from create-task response"
    echo "Raw output was:" >&2
    echo "$create_result" >&2
    return 1
  fi

  if [[ "$start" == "true" ]]; then
    local -a start_args=("$task_id")
    [[ "$use_worktree" == "true" ]] && start_args+=(--worktree)
    [[ "$DEBUG" == "true" ]] && start_args+=(--debug)
    cp_start_task "${start_args[@]}"
  else
    if command -v pbcopy &>/dev/null; then
      echo -n "$task_id" | pbcopy
      info "Created ClickUp task: $task_id (copied to clipboard)"
    else
      info "Created ClickUp task: $task_id"
    fi
    info "Run: cp_start_task $task_id"
  fi
}

alias new=cp_new_task

cp_start_task() {
  local DEBUG=false
  local task_id=""
  local use_worktree=false

  local help_text='Usage: cp_start_task <task-id> [--worktree] [--debug] [-h|--help]

Starts work on a ClickUp task:
  1. Checks out branch ${ISSUE_BRANCH_PREFIX}/CU-{taskid}-{slug}.
  2. Marks the task IN PROGRESS in ClickUp.
  3. Adds the task to the current sprint.

Accepts a task ID or a ClickUp URL.

Options:
  --worktree    Devcontainer worktree workflow: instead of checking out the
                branch in the current repo, create a fresh git worktree
                under ~/worktrees/CU-<id>-<slug> off origin/master and wire
                up the standard node_modules symlinks.  /workspace stays on
                its current branch.  Devcontainer-only.
  --debug       Verbose output.
  -h, --help    Show this help.

Examples:
  cp_start_task 86ew4x0vz
  cp_start_task 86ew4x0vz --worktree
  cp_start_task https://app.clickup.com/t/86ewdbtbh'

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)
      echo "$help_text"
      return 0
      ;;
    --worktree)
      use_worktree=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      if [[ -z "$task_id" ]]; then
        task_id="$1"
      else
        error "Unknown option or multiple task IDs provided: $1"
        echo "$help_text"
        return 1
      fi
      shift
      ;;
    esac
  done

  [[ "$DEBUG" == "true" ]] && echo "Debug mode enabled"
  [[ "$DEBUG" == "true" ]] && debug "Task ID: $task_id"
  [[ "$DEBUG" == "true" ]] && debug "use_worktree: $use_worktree"

  if [[ -z "$task_id" ]]; then
    error "Task ID is required"
    echo "$help_text"
    return 1
  fi

  if [[ "$task_id" == *"/t/"* ]]; then
    local resolved_id
    resolved_id=$(clickup_infer-task-id "$task_id")
    if [[ -z "$resolved_id" ]]; then
      error "Could not extract task ID from URL: $task_id"
      return 1
    fi
    [[ "$DEBUG" == "true" ]] && debug "Resolved URL to task ID: $resolved_id"
    task_id="$resolved_id"
  fi

  if [[ "$use_worktree" == "true" ]]; then
    info "Setting up devcontainer worktree for task $task_id"
    if [[ "$DEBUG" == "true" ]]; then
      git_worktree_for_task_branch "$task_id" --debug
    else
      git_worktree_for_task_branch "$task_id"
    fi
  else
    info "Checking out git branch for task $task_id"
    if [[ "$DEBUG" == "true" ]]; then
      git_checkout_task_branch "$task_id" --debug
    else
      git_checkout_task_branch "$task_id"
    fi
  fi

  local checkout_exit_code=$?

  if [[ $checkout_exit_code -ne 0 ]]; then
    if [[ "$use_worktree" == "true" ]]; then
      error "Failed to set up worktree for task $task_id"
    else
      error "Failed to checkout branch for task $task_id"
    fi
    return 1
  fi

  info "Marking task $task_id as IN PROGRESS in ClickUp"
  local start_result
  start_result=$(clickup start-task "$task_id" 2>&1)
  local start_exit_code=$?

  if [[ $start_exit_code -ne 0 ]]; then
    error "Failed to mark task $task_id as IN PROGRESS"
    [[ "$DEBUG" == "true" ]] && debug "start-task output: $start_result"
    info "Branch/worktree setup was successful, but task status update failed."
    info "You may want to manually update the task status in ClickUp."
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "start-task result: $start_result"
  info "Successfully marked task $task_id as IN PROGRESS"

  info "Adding task $task_id to current sprint (Team - Platform)"
  local sprint_result
  sprint_result=$(clickup add-task-to-current-sprint "$task_id" 2>&1)
  local sprint_exit_code=$?

  if [[ $sprint_exit_code -ne 0 ]]; then
    error "Failed to add task $task_id to current sprint"
    [[ "$DEBUG" == "true" ]] && debug "add-task-to-current-sprint output: $sprint_result"
    return 1
  fi

  info "Task $task_id added to current sprint"
  info "Task $task_id is now ready for work!"
}

alias start=cp_start_task

cp_pr_task() {
  local DEBUG=false
  local pr_body=""
  local ai_review=false
  local no_slack=false
  local slack_channel="$SLACK_PR_NOTIFY_DEFAULT_CHANNEL"

  local help_text='Usage: cp_pr_task [--body DESCRIPTION] [--ai-review|-ar|--greptile] [--no-slack] [--channel CHANNEL_ID] [--debug] [-h|--help]

Creates or updates a draft PR for the current branch and marks the ClickUp task IN REVIEW.
On initial PR creation, posts "PR please\n<url>" to $SLACK_PR_NOTIFY_DEFAULT_CHANNEL (if set).
Subsequent invocations on the same PR (commit updates) are silent — reviewers were already pinged when the PR was opened.

Options:
  --body DESCRIPTION              Custom PR description (otherwise uses ClickUp task description).
  --ai-review, -ar, --greptile    Add the greptile label so the Greptile bot reviews the PR.
  --no-slack                      Skip the Slack notification.
  --channel CHANNEL_ID            Override the Slack destination channel/DM for this invocation.
  --debug                         Verbose output.
  -h, --help                      Show this help.'

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)
      echo "$help_text"
      return 0
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    --body)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Missing value for --body"
        echo "$help_text"
        return 1
      fi
      pr_body="$1"
      shift
      ;;
    --ai-review|-ar|--greptile)
      ai_review=true
      shift
      ;;
    --no-slack)
      no_slack=true
      shift
      ;;
    --channel)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Missing value for --channel"
        echo "$help_text"
        return 1
      fi
      slack_channel="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "$help_text"
      return 1
      ;;
    esac
  done

  [[ "$DEBUG" == "true" ]] && echo "Debug mode enabled"

  local current_branch
  current_branch=$(git branch --show-current)

  if [[ -z "$current_branch" ]]; then
    error "Not on a git branch"
    return 1
  fi

  local task_id
  task_id=$(git_infer_task_id "$current_branch" "$DEBUG")

  if [[ -z "$task_id" ]]; then
    error "Failed to extract task ID from branch name"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "Extracted task ID from branch: $task_id"

  info "Creating/updating PR for task $task_id"

  # Detect whether a PR already exists for this branch BEFORE git_pr_task_branch
  # runs the create-or-update.  Used at the end to skip the Slack notification
  # on update-only invocations — reviewers were already pinged when the PR
  # was opened; re-posting "PR please" on every commit is noisy.
  local pr_existed_before=false
  if [[ -n "$(gh pr list --head "$current_branch" --json number -q '.[0].number' 2>/dev/null)" ]]; then
    pr_existed_before=true
  fi
  [[ "$DEBUG" == "true" ]] && debug "pr_existed_before=$pr_existed_before"

  local pr_args=()
  [[ -n "$pr_body" ]] && pr_args+=(--body "$pr_body")
  [[ "$DEBUG" == "true" ]] && pr_args+=(--debug)
  [[ "$ai_review" == true ]] && pr_args+=(--ai-review)

  git_pr_task_branch "${pr_args[@]}"

  local pr_exit_code=$?

  if [[ $pr_exit_code -ne 0 ]]; then
    error "Failed to create/update PR for task $task_id"
    return 1
  fi

  info "Marking task $task_id as IN REVIEW in ClickUp"
  local pr_task_result
  pr_task_result=$(clickup pr-task "$task_id" 2>&1)
  local pr_task_exit_code=$?

  if [[ $pr_task_exit_code -ne 0 ]]; then
    error "Failed to mark task $task_id as IN REVIEW"
    [[ "$DEBUG" == "true" ]] && debug "pr-task output: $pr_task_result"
    info "PR creation/update was successful, but task status update failed."
    info "You may want to manually update the task status in ClickUp."
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "pr-task result: $pr_task_result"
  info "Successfully marked task $task_id as IN REVIEW"
  info "PR created/updated and task $task_id is now in review!"

  if [[ "$no_slack" == "true" ]]; then
    [[ "$DEBUG" == "true" ]] && debug "Skipping Slack notification (--no-slack)"
    return 0
  fi

  if [[ "$pr_existed_before" == "true" ]]; then
    [[ "$DEBUG" == "true" ]] && debug "Skipping Slack notification (PR already existed; updates are silent)"
    return 0
  fi

  if [[ -z "$slack_channel" ]]; then
    [[ "$DEBUG" == "true" ]] && debug "No Slack channel configured; skipping notification."
    return 0
  fi

  local pr_url
  pr_url=$(gh pr view --json url -q .url 2>/dev/null)
  if [[ -z "$pr_url" ]]; then
    error "Could not resolve PR URL; skipping Slack notification."
    return 0
  fi

  local slack_text=$'PR please\n'"$pr_url"
  info "Notifying Slack channel $slack_channel"
  local slack_args=("$slack_channel" "$slack_text")
  [[ "$DEBUG" == "true" ]] && slack_args+=(--debug)
  if ! slack_post_message "${slack_args[@]}"; then
    error "Slack notification failed (PR is still created/updated)."
    return 0
  fi
  info "Slack notification sent."
}

alias pr=cp_pr_task

cp_cleanup_branches() {
  local DEBUG=false

  local help_text='Usage: cp_cleanup_branches [--debug] [-h|--help]

Cleans up merged branches:
  1. Finds local branches whose remote tracking branch is gone.
  2. Marks the corresponding ClickUp tasks as DONE.
  3. Removes worktrees for gone branches.
  4. Deletes the local branches (git bclean).

Options:
  --debug       Verbose output.
  -h, --help    Show this help.'

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)
      echo "$help_text"
      return 0
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      error "Unknown option: $1"
      echo "$help_text"
      return 1
      ;;
    esac
  done

  local gone_branches
  gone_branches=("${(f)$(git gone 2>/dev/null)}")
  if [[ ${#gone_branches[@]} -eq 0 ]]; then
    info "No branches to clean up (git gone is empty)."
    return 0
  fi

  [[ "$DEBUG" == "true" ]] && debug "Branches to clean: ${gone_branches[*]}"

  local current_branch
  current_branch=$(git branch --show-current)
  if [[ -n "$current_branch" ]] && [[ -n "${gone_branches[(r)$current_branch]}" ]]; then
    info "Current branch '$current_branch' is in gone list; switching to default before cleanup."
    git checkout "$(git default)" || return 1
  fi

  local branch task_id failed=0
  for branch in "${gone_branches[@]}"; do
    branch="${branch//[$'\r\n']}"
    [[ -z "$branch" ]] && continue
    task_id=$(git_infer_task_id "$branch" "$DEBUG" 2>/dev/null)
    if [[ -n "$task_id" ]]; then
      info "Marking ClickUp task $task_id (branch $branch) as DONE."
      if ! cp_complete_task "$task_id"; then
        error "Failed to complete task $task_id for branch $branch"
        failed=1
      fi
    else
      [[ "$DEBUG" == "true" ]] && debug "No task ID for branch $branch; skipping ClickUp."
    fi
  done

  info "Removing worktrees for gone branches before deletion."
  git_remove_gone_worktrees "${gone_branches[@]}" || failed=1

  info "Running git bclean to delete gone branches."
  git bclean

  [[ $failed -eq 1 ]] && return 1
  return 0
}

alias cleanup=cp_cleanup_branches
