cp_new_task() {
  local title=""
  local description=""
  local no_assignment=false
  local start=true
  local DEBUG=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --no-assignment)
      no_assignment=true
      shift
      ;;
    --no-start)
      start=false
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
        echo "Usage: cp_new_task <title> <description> [--no-assignment] [--no-start] [--debug]"
        return 1
      fi
      shift
      ;;
    esac
  done

  if [[ -z "$title" ]]; then
    error "Title is required"
    echo "Usage: cp_new_task <title> <description> [--no-assignment] [--no-start] [--debug]"
    echo "Example: cp_new_task \"Fix login bug\" \"Description of the fix\""
    return 1
  fi

  if [[ -z "$description" ]]; then
    error "Description is required"
    echo "Usage: cp_new_task <title> <description> [--no-assignment] [--no-start] [--debug]"
    return 1
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
    cp_start_task "$task_id"
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      if [[ -z "$task_id" ]]; then
        task_id="$1"
      else
        error "Unknown option or multiple task IDs provided: $1"
        echo "Usage: cp_start_task <task-id> [--debug]"
        return 1
      fi
      shift
      ;;
    esac
  done

  [[ "$DEBUG" == "true" ]] && echo "Debug mode enabled"
  [[ "$DEBUG" == "true" ]] && debug "Task ID: $task_id"

  if [[ -z "$task_id" ]]; then
    error "Task ID is required"
    echo "Usage: cp_start_task <task-id> [--debug]"
    echo "Example: cp_start_task 86ew4x0vz"
    echo "Example: cp_start_task https://app.clickup.com/t/86ewdbtbh"
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

  info "Checking out git branch for task $task_id"
  if [[ "$DEBUG" == "true" ]]; then
    git_checkout_task_branch "$task_id" --debug
  else
    git_checkout_task_branch "$task_id"
  fi

  local checkout_exit_code=$?

  if [[ $checkout_exit_code -ne 0 ]]; then
    error "Failed to checkout branch for task $task_id"
    return 1
  fi

  info "Marking task $task_id as IN PROGRESS in ClickUp"
  local start_result
  start_result=$(clickup start-task "$task_id" 2>&1)
  local start_exit_code=$?

  if [[ $start_exit_code -ne 0 ]]; then
    error "Failed to mark task $task_id as IN PROGRESS"
    [[ "$DEBUG" == "true" ]] && debug "start-task output: $start_result"
    info "Branch checkout was successful, but task status update failed."
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
  local skip_ai_review=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --debug)
      DEBUG=true
      shift
      ;;
    --body)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Missing value for --body"
        echo "Usage: cp_pr_task [--debug] [--body DESCRIPTION] [--skip-ai-review|--sr]"
        return 1
      fi
      pr_body="$1"
      shift
      ;;
    --skip-ai-review|--sr)
      skip_ai_review=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: cp_pr_task [--debug] [--body DESCRIPTION] [--skip-ai-review|--sr]"
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
  local pr_args=()
  [[ -n "$pr_body" ]] && pr_args+=(--body "$pr_body")
  [[ "$DEBUG" == "true" ]] && pr_args+=(--debug)
  [[ "$skip_ai_review" == true ]] && pr_args+=(--skip-ai-review)

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
}

alias pr=cp_pr_task

cp_cleanup_branches() {
  local DEBUG=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      error "Unknown option: $1"
      echo "Usage: cp_cleanup_branches [--debug]"
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

  info "Running git bclean to delete gone branches."
  git bclean

  [[ $failed -eq 1 ]] && return 1
  return 0
}

alias cleanup=cp_cleanup_branches
