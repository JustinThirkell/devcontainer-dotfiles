##############################################################################################
# ClickUp CLI Wrapper
##############################################################################################

# Get the directory where this file is located (works when file is sourced)
_CLICKUP_DIR="${${(%):-%x}:A:h}"

# Path to the clickup.ts script
_CLICKUP_SCRIPT_PATH="$_CLICKUP_DIR/clickup.ts"

# Main clickup function that dispatches to subcommands
clickup() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: clickup <command> [options]"
    echo ""
    echo "Available commands:"
    echo "  whoami                            - Get your ClickUp user info (shows user ID)"
    echo "  get-task <task-id>                - Get detailed info for a task"
    echo "  start-task <task-id>              - Update task status to \"IN PROGRESS\""
    echo "  pr-task <task-id>                 - Update task status to \"IN REVIEW\""
    echo "  complete-task <task-id>           - Update task status to \"DONE\""
    echo "  create-task <title> <description> - Create a new task (requires CLICKUP_DEFAULT_LIST_ID and CLICKUP_USER_ID)"
    echo "  add-task-to-current-sprint <task-id> - Move task to current sprint (requires CLICKUP_TEAM_PLATFORM_FOLDER_ID)"
    echo ""
    echo "Examples:"
    echo "  clickup whoami"
    echo "  clickup get-task 86ew4x0vz"
    echo "  clickup get-task 86ew4x0vz --debug"
    echo "  clickup start-task 86ew4x0vz"
    echo "  clickup pr-task 86ew4x0vz"
    echo "  clickup complete-task 86ew4x0vz"
    echo "  clickup create-task \"My title\" \"My description\""
    echo "  clickup create-task \"My title\" \"My description\" --no-assignment"
    echo "  clickup add-task-to-current-sprint 86ew4x0vz"
    return 1
  fi

  # Check if clickup.ts exists
  if [[ ! -f "$_CLICKUP_SCRIPT_PATH" ]]; then
    echo "Error: ClickUp script not found at $_CLICKUP_SCRIPT_PATH" >&2
    return 1
  fi

  # Use the pre-computed clickup directory
  local tsx_path="$_CLICKUP_DIR/node_modules/.bin/tsx"
  
  # Check if tsx exists
  if [[ ! -f "$tsx_path" ]]; then
    echo "Error: tsx not found at $tsx_path. Please run 'npm install' in $_CLICKUP_DIR" >&2
    return 1
  fi
  
  # Use the absolute path to tsx to ensure it works from any directory
  "$tsx_path" "$_CLICKUP_SCRIPT_PATH" "$@"
}

# Extract task ID from a ClickUp task URL (e.g. https://app.clickup.com/t/86ewdbtbh -> 86ewdbtbh)
clickup_infer-task-id() {
  local url="$1"
  if [[ -z "$url" ]]; then
    echo "" >&2
    return 1
  fi
  if [[ "$url" =~ /t/([a-zA-Z0-9]+) ]]; then
    echo "$match[1]"
    return 0
  fi
  echo "" >&2
  return 1
}

# Individual command functions for direct access
clickup_get-task() {
  clickup get-task "$@"
}

clickup_start-task() {
  clickup start-task "$@"
}

clickup_pr-task() {
  clickup pr-task "$@"
}

clickup_complete-task() {
  clickup complete-task "$@"
}

# Mark a ClickUp task as complete (status DONE). Used by cp_cleanup_branches.
# Usage: cp_complete_task <task-id>
cp_complete_task() {
  local task_id="$1"
  if [[ -z "$task_id" ]]; then
    echo "Usage: cp_complete_task <task-id>" >&2
    return 1
  fi
  clickup complete-task "$task_id"
}

clickup_create-task() {
  clickup create-task "$@"
}

clickup_add-task-to-current-sprint() {
  clickup add-task-to-current-sprint "$@"
}

clickup_whoami() {
  clickup whoami "$@"
}

