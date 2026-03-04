# branch format is username/CU-identifier-title
# Example: justin/CU-86ew4x0vz-fix-the-bug
# PR title should be: "[CU-86ew4x0vz] "Fix the bug"

# Infer branch name from task ID and title
# Usage: infer_branch_name <task_id> <title> [debug]
# Returns: branch name in format username/CU-{taskid}-{slug}
infer_branch_name() {
  local task_id="$1"
  local title="$2"
  local DEBUG="${3:-false}"

  # Validate USER environment variable is set
  if [[ -z "$USER" ]]; then
    error "USER environment variable is not set. Cannot infer branch name."
    return 1
  fi

  # Validate inputs
  if [[ -z "$task_id" ]]; then
    error "Task ID is required for infer_branch_name"
    return 1
  fi

  if [[ -z "$title" ]]; then
    error "Title is required for infer_branch_name"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "infer_branch_name: task_id=$task_id, title=$title"

  # Convert task name to branch-safe format:
  # - Convert to lowercase
  # - Replace spaces and special characters with dashes
  # - Collapse multiple consecutive dashes
  # - Remove leading/trailing dashes
  local branch_name_slug
  branch_name_slug=$(echo "$title" | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | \
    sed 's/-\+/-/g' | \
    sed 's/^-\|-$//g')

  [[ "$DEBUG" == "true" ]] && debug "infer_branch_name: branch_name_slug=$branch_name_slug"

  # Construct branch name: username/CU-{taskid}-{slug}
  local branch_name="${USER}/CU-${task_id}-${branch_name_slug}"

  [[ "$DEBUG" == "true" ]] && debug "infer_branch_name: result=$branch_name"
  info "Constructed branch name: $branch_name"

  echo "$branch_name"
}

# Infer PR title from task ID and title
# Usage: infer_pr_title <task_id> <title> [debug]
# Returns: PR title in format [CU-{taskid}] {Capitalized Title}
infer_pr_title() {
  local task_id="$1"
  local title="$2"
  local DEBUG="${3:-false}"

  # Validate inputs
  if [[ -z "$task_id" ]]; then
    error "Task ID is required for infer_pr_title"
    return 1
  fi

  if [[ -z "$title" ]]; then
    error "Title is required for infer_pr_title"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "infer_pr_title: task_id=$task_id, title=$title"

  # Keep task ID as-is (no uppercase conversion)
  local id="$task_id"
  [[ "$DEBUG" == "true" ]] && debug "infer_pr_title: id=$id"

  # Ensure the first letter of the task title is capitalized
  local title_capitalized
  title_capitalized=$(echo "$title" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
  [[ "$DEBUG" == "true" ]] && debug "infer_pr_title: title_capitalized=$title_capitalized"

  # Format the PR title with CU- prefix, task ID and capitalized title
  local pr_title="[CU-$id] $title_capitalized"
  [[ "$DEBUG" == "true" ]] && debug "infer_pr_title: result=$pr_title"
  info "Generated PR title: $pr_title"

  echo "$pr_title"
}

# Infer task ID from branch name
# Usage: git_infer_task_id <branch_name> [debug]
# Returns: task ID extracted from branch name, or empty string if invalid
git_infer_task_id() {
  local branch_name="$1"
  local DEBUG="${2:-false}"

  # Validate USER environment variable is set
  if [[ -z "$USER" ]]; then
    error "USER environment variable is not set. Cannot infer task ID."
    return 1
  fi

  # Validate input
  if [[ -z "$branch_name" ]]; then
    error "Branch name is required for git_infer_task_id"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "git_infer_task_id: branch_name=$branch_name"

  # Extract the task ID from branch format: username/CU-{taskid}-{slug}
  # Example: justin/CU-86ew4x0vz-update-canvas-dependency -> 86ew4x0vz
  local task_id
  task_id=$(echo "$branch_name" | sed 's|.*/||' | sed 's/^CU-//' | sed 's/-.*//')

  [[ "$DEBUG" == "true" ]] && debug "git_infer_task_id: extracted task_id=$task_id"

  # Validate extracted task ID
  if [[ -z "$task_id" ]]; then
    error "No task ID detected in branch name. Expected format: username/CU-{taskid}-{slug} (e.g. ${USER}/CU-86ew4x0vz-fix-the-bug)"
    info "Please use a branch with a valid task identifier."
    return 1
  fi

  echo "$task_id"
}

git_checkout_task_branch() {
  # Default options
  local DEBUG=false
  local task_id=""

  # Process command line arguments
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
        echo "Usage: git_checkout_task_branch <task-id> [--debug]"
        return 1
      fi
      shift
      ;;
    esac
  done

  [[ "$DEBUG" == "true" ]] && echo "Debug mode enabled"
  [[ "$DEBUG" == "true" ]] && debug "Task ID: $task_id"

  # Validate task ID is provided
  if [[ -z "$task_id" ]]; then
    error "Task ID is required"
    echo "Usage: git_checkout_task_branch <task-id> [--debug]"
    echo "Example: git_checkout_task_branch 86ew4x0vz"
    return 1
  fi

  info "📝 Fetching task details for $task_id using ClickUp CLI"

  # Get task from ClickUp using our local clickup function
  local task
  task=$(clickup get-task "$task_id")

  if [[ $? -ne 0 || -z "$task" ]]; then
    error "Could not fetch task details from ClickUp for task ID: $task_id"
    info "Please check that the task exists, the ID is correct, and that you have proper access."
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "Received task from ClickUp: $task"

  # Sanitize JSON to handle any remaining control characters before jq parsing
  local sanitized_task
  sanitized_task=$(echo "$task" | tr -d '\000-\037')
  [[ "$DEBUG" == "true" ]] && debug "Sanitized task JSON"

  # Extract task name using jq
  local task_name
  task_name=$(echo "$sanitized_task" | jq -r '.name')

  if [[ -z "$task_name" || "$task_name" == "null" ]]; then
    error "Could not extract task name from ClickUp response for task ID: $task_id"
    [[ "$DEBUG" == "true" ]] && debug "Task details JSON was: $task"
    return 1
  fi

  info "Successfully fetched task name for $task_id: '$task_name'"
  [[ "$DEBUG" == "true" ]] && debug "Raw task name: $task_name"

  # Infer branch name from task ID and title
  local branch_name
  branch_name=$(infer_branch_name "$task_id" "$task_name" "$DEBUG")
  if [[ $? -ne 0 ]]; then
    error "Failed to infer branch name"
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "Full branch name: $branch_name"

  # Check if branch already exists
  if git show-ref --verify --quiet refs/heads/"$branch_name"; then
    info "Branch $branch_name already exists, checking it out"
    git checkout "$branch_name"
    if [[ $? -ne 0 ]]; then
      error "Failed to checkout existing branch: $branch_name"
      return 1
    fi
    info "✅ Successfully checked out branch: $branch_name"
  else
    info "Creating and checking out new branch: $branch_name"
    git checkout -b "$branch_name"
    if [[ $? -ne 0 ]]; then
      error "Failed to create and checkout branch: $branch_name"
      info "This might be due to uncommitted changes or other git issues."
      return 1
    fi
    info "✅ Successfully created and checked out branch: $branch_name"
  fi
}

git_pr_task_branch() {

  # Default options
  local SKIP_LLM=true
  local DEBUG=false
  local reviewer="${GITHUB_DEFAULT_PR_REVIEWER:-}"
  local custom_body=""

  # Process command line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --skip-llm)
      SKIP_LLM=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    --body)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Missing value for --body"
        echo "Usage: git_pr_task_branch [--skip-llm] [--debug] [--body DESCRIPTION]"
        return 1
      fi
      custom_body="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: git_pr_task_branch [--skip-llm] [--debug] [--body DESCRIPTION]"
      return 1
      ;;
    esac
  done

  [[ "$DEBUG" == "true" ]] && echo "Debug mode enabled"
  [[ "$SKIP_LLM" == "true" ]] && echo "Skipping LLM description generation"

  # Check if upstream is already set for the current branch
  current_branch=$(git branch --show-current)
  if ! git rev-parse --abbrev-ref --symbolic-full-name @{upstream} &>/dev/null; then
    # No upstream set, so push with -u to set it
    echo "Setting upstream for branch $current_branch"
    git push --set-upstream origin $current_branch
  else
    # Upstream already configured, just push
    echo "Pushing changes to remote"
    git push
  fi

  # Get current branch name using zsh git alias
  branch=$(git branch --show-current)
  [[ "$DEBUG" == "true" ]] && echo "branch: $branch"

  # Extract the task ID from branch name
  local task_id_from_branch
  task_id_from_branch=$(git_infer_task_id "$current_branch" "$DEBUG")
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  info "📝 Fetching task details for $task_id_from_branch using ClickUp CLI"

  # Get task from ClickUp using our local clickup function
  local task
  task=$(clickup get-task "$task_id_from_branch")

  if [[ $? -ne 0 || -z "$task" ]]; then
    error "Could not fetch task details from ClickUp for task ID: $task_id_from_branch"
    info "Please check that the task exists, the ID is correct, and that you have proper access."
    return 1
  fi

  [[ "$DEBUG" == "true" ]] && debug "Received task from ClickUp: $task"

  # Sanitize JSON to handle any remaining control characters before jq parsing
  local sanitized_task
  sanitized_task=$(echo "$task" | tr -d '\000-\037')

  # Extract task fields - extract description separately to preserve newlines
  local task_name task_url
  task_name=$(echo "$sanitized_task" | jq -r '.name')
  task_url=$(echo "$sanitized_task" | jq -r '.url')
  # Extract description with newlines preserved (jq -r outputs raw, including \n)
  local task_description
  task_description=$(echo "$sanitized_task" | jq -r '.text_content // ""')

  if [[ -z "$task_name" || "$task_name" == "null" ]]; then
    error "Could not extract task name from ClickUp response for task ID: $task_id_from_branch"
    [[ "$DEBUG" == "true" ]] && debug "Task details JSON was: $task"
    return 1
  fi

  info "Successfully fetched task name for $task_id_from_branch: '$task_name'"

  # Infer PR title from task ID and title
  local pr_title
  pr_title=$(infer_pr_title "$task_id_from_branch" "$task_name" "$DEBUG")
  if [[ $? -ne 0 ]]; then
    error "Failed to infer PR title"
    return 1
  fi

  # Keep task ID for use in description
  local id="$task_id_from_branch"
  
  # Capitalize title for use in description
  local title_capitalized
  title_capitalized=$(echo "$task_name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

  # PR description: custom body overrides ClickUp/LLM
  local pr_description
  if [[ -n "$custom_body" ]]; then
    pr_description="$custom_body"
    [[ "$DEBUG" == "true" ]] && debug "Using provided --body as PR description"
  # Generate PR description if LLM is not being skipped
  elif [[ "$SKIP_LLM" != "true" ]]; then
    info "📝 Generating PR description (LLM step)"

    # Construct a more detailed task context string for the LLM
    local clickup_task_context="ClickUp Task ID: $id\nTitle: $task_name\nURL: $task_url\nDescription: $task_description"
    [[ "$DEBUG" == "true" ]] && debug "clickup_task_context for LLM: $clickup_task_context"

    local ollama_model="qwen3:8b"  # Gemma3
    [[ "$DEBUG" == "true" ]] && debug "ollama_model: $ollama_model"

    ollama_prompt="Based on the following git diff and the branch name '$current_branch', write a \
concise, informative, and detailed PR description that summarizes the changes. \
Here is the ClickUp task context for this PR:\n\n${clickup_task_context}. \
\nUse sections that are correctly formatted markdown:\
# Purpose -> concise overview of why the PR has been created.  Try to use the task title if available.\
## Context -> background information about the PR. USE task context if available, particularly the task description. 
\nUse line breaks to ensure they are correctly formatted markdown. \
Do not use emojis. \
At the end, include a note in italics stating that this summary was written by an LLM, and to tag Justin if you're not happy with it. \
Only return the PR description, don't return anything else."

    if [[ "$DEBUG" == "true" ]]; then
      debug "🔍 Here's the prompt that will be given to Ollama:"
      debug "-------------------------------------------------"
      debug "$ollama_prompt"
      debug "-------------------------------------------------"
    fi

    info "⏳ Now running Ollama... (this might take a while)"

    raw_description=$(git diff main | ollama run $ollama_model "$ollama_prompt" | sed "s/\"//g")
    [[ "$DEBUG" == "true" ]] && debug "raw_description: $raw_description"

    if [[ "$DEBUG" == "true" ]]; then
      debug "📄 Raw PR description before removing think tags:"
      debug "$raw_description"
      debug "----------------------------------------"
    fi

    info "🔍 Removing <think> tags"

    # Clean and escape the PR description
    pr_description=$(echo "$raw_description" |
      perl -0777 -pe 's/<think>.*?<\/think>//gs')

    info "🧹 Removing LLM output footer"
    # Remove the output footer that sometimes appears in LLM responses
    pr_description=$(echo "$pr_description" |
      perl -0777 -pe 's/\n\n---\n\n\*Note: This PR description is concise.*?instructions\.\*//gs')
  else
    info "⏭️ Skipping PR description generation (--skip-llm flag set)"
    # Use task description as-is for PR body
    if [[ -n "$task_description" && "$task_description" != "null" && "$task_description" != "" ]]; then
      pr_description="$task_description"
    else
      pr_description=""
    fi
    [[ "$DEBUG" == "true" ]] && debug "Generated PR description: $pr_description"
  fi

  # Check if a PR already exists
  existing_pr=$(gh pr view --json number,title,body)

  if [ $? -eq 0 ]; then
    # PR exists, update it
    # Sanitize the JSON output before passing it to jq to handle control characters
    sanitized_pr=$(echo "$existing_pr" | tr -d '\000-\037')
    pr_number=$(echo "$sanitized_pr" | jq -r .number)

    if [[ "$SKIP_LLM" == "true" ]]; then
      if [[ -n "$pr_description" && "$pr_description" != "" ]]; then
        info "🔄 Updating existing PR #$pr_number"
        gh pr edit $pr_number --title "$pr_title" --body "$pr_description"
      else
        info "🔄 Updating existing PR #$pr_number (title only)"
        gh pr edit $pr_number --title "$pr_title"
      fi
    else
      info "🔄 Updating existing PR #$pr_number"
      gh pr edit $pr_number --title "$pr_title" --body "$pr_description"
    fi
    echo "🎉 Successfully updated PR"
  else
    # Create new PR via CLI (so we can set reviewer); then open in browser.
    # --web is not used because it doesn't support --reviewer.
    local pr_args=(--title "$pr_title" --draft)
    
    # Add optional flags
    if [[ "$SKIP_LLM" != "true" || (-n "$pr_description" && "$pr_description" != "") ]]; then
      pr_args+=(--body "$pr_description")
    fi
    
    if [[ -n "$reviewer" ]]; then
      pr_args+=(--reviewer "$reviewer")
    fi
    
    if [[ "$SKIP_LLM" == "true" && (-n "$pr_description" && "$pr_description" != "") ]]; then
      info "🆕 Creating new PR (with description)"
    elif [[ "$SKIP_LLM" == "true" ]]; then
      info "🆕 Creating new PR (without description)"
    else
      info "🆕 Creating new PR"
    fi
    
    debug "Executing: gh pr create ${pr_args[*]}"
    gh pr create "${pr_args[@]}"
    echo "🎉 Successfully created PR"
    # Open the new PR in the browser so you can review it
    gh pr view --web
  fi
}
