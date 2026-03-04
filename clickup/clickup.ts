import { ClickUpClient } from './clickup-client'
import stringify from 'safe-stable-stringify'

/*
  ------------------------------------------------------------------------------------
  ClickUp CLI – read-only utilities
  ------------------------------------------------------------------------------------
  Commands implemented:
    • whoami                             – get authorized user info (shows your user ID)
    • get-task <task-id>                  – detailed info for a single task
    • start-task <task-id>               – update task status to "IN PROGRESS"
    • pr-task <task-id>                  – update task status to "IN REVIEW"
    • complete-task <task-id>            – update task status to "DONE"
    • create-task <title> <description>    – create a new task (requires CLICKUP_DEFAULT_LIST_ID and CLICKUP_USER_ID)
    • add-task-to-current-sprint <task-id> – move task to current sprint (requires CLICKUP_TEAM_PLATFORM_FOLDER_ID)

  Usage examples:
    npx tsx clickup.ts whoami
    npx tsx clickup.ts get-task 86ew4x0vz
    npx tsx clickup.ts get-task 86ew4x0vz --debug
    npx tsx clickup.ts start-task 86ew4x0vz
    npx tsx clickup.ts pr-task 86ew4x0vz
    npx tsx clickup.ts complete-task 86ew4x0vz
    npx tsx clickup.ts create-task "My title" "My description"
    npx tsx clickup.ts create-task "My title" "My description" --no-assignment
    npx tsx clickup.ts add-task-to-current-sprint 86ew4x0vz

  Notes:
  • Commands that return data (whoami, get-task, create-task, add-task-to-current-sprint) output JSON to stdout.
  • Status-update commands (start-task, pr-task, complete-task) write only to stderr on success; use exit code for success/failure.
  • Use the --debug flag for verbose logging to stderr.
*/

// -------------------------------------------------------------------------------------------------
// Environment
// -------------------------------------------------------------------------------------------------
const apiKey: string | undefined = process.env.CLICKUP_API_KEY
if (!apiKey) {
  console.error(
    JSON.stringify({
      error: 'CLICKUP_API_KEY environment variable is not set.',
    }),
  )
  process.exit(1)
}

// List ID and User ID are only validated when needed (for create-task command)
const listIdRaw = process.env.CLICKUP_DEFAULT_LIST_ID
const userIdRaw = process.env.CLICKUP_USER_ID
const teamPlatformFolderIdRaw = process.env.CLICKUP_TEAM_PLATFORM_FOLDER_ID

const clickUp = new ClickUpClient({ apiKey })

// -------------------------------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------------------------------
async function main(): Promise<void> {
  const rawArgs = process.argv.slice(2)
  const argv = stripGlobalFlags(rawArgs)
  const command = argv[0]
  const rest = argv.slice(1)
  const params = parseArgs(rest)

  try {
    switch (command) {
      case 'whoami': {
        const json = stringify(await whoami(), null, 2)
        console.log(json)
        return
      }
      case 'get-task': {
        // Accept task ID as positional argument or --id flag
        const taskId = rest[0] && !rest[0].startsWith('--') ? rest[0] : (params.id as string)
        const json = stringify(await getTask(taskId), null, 2)
        console.log(json)
        return
      }
      case 'start-task': {
        // Accept task ID as positional argument or --id flag. No stdout on success (exit code + stderr only).
        const taskId = rest[0] && !rest[0].startsWith('--') ? rest[0] : (params.id as string)
        await startTask(taskId)
        return
      }
      case 'pr-task': {
        // Accept task ID as positional argument or --id flag. No stdout on success (exit code + stderr only).
        const taskId = rest[0] && !rest[0].startsWith('--') ? rest[0] : (params.id as string)
        await prTask(taskId)
        return
      }
      case 'complete-task': {
        // Accept task ID as positional argument or --id flag. No stdout on success (exit code + stderr only).
        const taskId = rest[0] && !rest[0].startsWith('--') ? rest[0] : (params.id as string)
        await completeTask(taskId)
        return
      }
      case 'create-task': {
        const title = rest[0] && !rest[0].startsWith('--') ? rest[0] : (params.title as string)
        const description = rest[1] && !rest[1].startsWith('--') ? rest[1] : (params.description as string)
        const noAssignment = params['no-assignment'] === true
        const json = stringify(await createTask(title, description, noAssignment), null, 2)
        console.log(json)
        return
      }
      case 'add-task-to-current-sprint': {
        const taskId = rest[0] && !rest[0].startsWith('--') ? rest[0] : (params.id as string)
        const json = stringify(await addTaskToCurrentSprint(taskId), null, 2)
        console.log(json)
        return
      }
      default:
        console.error(
          JSON.stringify({
            error: `Unknown command: ${command}`,
            supported: ['whoami', 'get-task', 'start-task', 'pr-task', 'complete-task', 'create-task', 'add-task-to-current-sprint'],
          }),
        )
        process.exit(1)
        return
    }
  } catch (err: unknown) {
    const error = err as Error
    console.error(JSON.stringify({ error: error.message, stack: error.stack }))
    process.exit(1)
  }
}

main()

// -------------------------------------------------------------------------------------------------
// CLI argument parsing (very small utility – avoids bringing external deps)
// -------------------------------------------------------------------------------------------------
interface ParsedArgs {
  [key: string]: string | boolean
}

function parseArgs(argv: string[]): ParsedArgs {
  const parsed: ParsedArgs = {}
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg.startsWith('--')) {
      const key = arg.slice(2)
      // next token is value if it does not start with '--'
      const next = argv[i + 1]
      if (next && !next.startsWith('--')) {
        parsed[key] = next
        i++ // skip value
      } else {
        parsed[key] = true // flag style
      }
    }
  }
  return parsed
}

// -------------------------------------------------------------------------------------------------
// Logging helpers (info to stderr, debug to stderr when enabled)
// -------------------------------------------------------------------------------------------------
const parsedGlobalArgs = parseArgs(process.argv.slice(2))
const DEBUG_ENABLED: boolean = Boolean(parsedGlobalArgs.debug)

function debug(message: unknown, ...optional: unknown[]): void {
  if (DEBUG_ENABLED) {
    console.error(`[DEBUG] ${String(message)}`, ...optional)
  }
}

function info(message: unknown, ...optional: unknown[]): void {
  console.error(`[INFO] ${String(message)}`, ...optional)
}

// Remove global flags (like --debug) from argv before command dispatch
function stripGlobalFlags(argv: string[]): string[] {
  const copy = [...argv]
  return copy.filter((token) => {
    if (!token.startsWith('--')) return true
    const key = token.slice(2)
    if (key === 'debug') {
      // remove flag and following value if any (though we use flag style only)
      return false
    }
    return true
  })
}

// -------------------------------------------------------------------------------------------------
// Command implementations
// -------------------------------------------------------------------------------------------------
async function whoami(): Promise<unknown> {
  info('Fetching authorized user info…')
  const user = await clickUp.getAuthorizedUser()
  debug('User fetched:', user)
  return user
}

async function getTask(taskId: string): Promise<unknown> {
  if (!taskId) throw new Error("Task ID is required for get-task (e.g., '86ew4x0vz' or '--id 86ew4x0vz')")
  info(`Fetching task ${taskId}…`)
  const task = await clickUp.getTask(taskId)
  debug('Task fetched:', task)
  return task
}

async function startTask(taskId: string): Promise<unknown> {
  if (!taskId) throw new Error("Task ID is required for start-task (e.g., '86ew4x0vz' or '--id 86ew4x0vz')")
  info(`Updating task ${taskId} status to "IN PROGRESS"…`)
  const task = await clickUp.updateTask(taskId, { status: 'IN PROGRESS' })
  debug('Task updated:', task)
  return task
}

async function prTask(taskId: string): Promise<unknown> {
  if (!taskId) throw new Error("Task ID is required for pr-task (e.g., '86ew4x0vz' or '--id 86ew4x0vz')")
  info(`Updating task ${taskId} status to "IN REVIEW"…`)
  const task = await clickUp.updateTask(taskId, { status: 'IN REVIEW' })
  debug('Task updated:', task)
  return task
}

async function completeTask(taskId: string): Promise<unknown> {
  if (!taskId) throw new Error("Task ID is required for complete-task (e.g., '86ew4x0vz' or '--id 86ew4x0vz')")
  info(`Updating task ${taskId} status to "DONE"…`)
  const task = await clickUp.updateTask(taskId, { status: 'DONE' })
  debug('Task updated:', task)
  return task
}

async function createTask(title: string, description: string, noAssignment: boolean): Promise<unknown> {
  if (!title) throw new Error("Title is required for create-task (e.g., 'My title' or --title 'My title')")

  // Validate required environment variables for create-task
  if (!listIdRaw) {
    throw new Error('CLICKUP_DEFAULT_LIST_ID environment variable is not set. Required for create-task.')
  }

  if (!noAssignment) {
    if (!userIdRaw) {
      throw new Error('CLICKUP_USER_ID environment variable is not set. Required for task assignment (use --no-assignment to skip).')
    }
    const userId = parseInt(userIdRaw, 10)
    if (Number.isNaN(userId)) {
      throw new Error('CLICKUP_USER_ID must be a valid integer.')
    }
    const assignees = [userId]
    info(`Creating task "${title}" (assigning to user ${userId})…`)
    const task = await clickUp.createTask(listIdRaw, { name: title, description: description || undefined, assignees })
    debug('Task created:', task)
    return task
  } else {
    info(`Creating task "${title}" (no assignment)…`)
    const task = await clickUp.createTask(listIdRaw, { name: title, description: description || undefined })
    debug('Task created:', task)
    return task
  }
}

async function addTaskToCurrentSprint(taskId: string): Promise<unknown> {
  if (!taskId) throw new Error("Task ID is required for add-task-to-current-sprint (e.g., '86ew4x0vz' or --id 86ew4x0vz)")

  if (!teamPlatformFolderIdRaw) {
    throw new Error('CLICKUP_TEAM_PLATFORM_FOLDER_ID environment variable is not set. Required for add-task-to-current-sprint (Team - Platform folder ID).')
  }

  info(`Fetching task ${taskId} to get workspace…`)
  const task = (await clickUp.getTask(taskId)) as { team_id?: string; list?: { id?: string } }
  const workspaceId = task?.team_id
  if (!workspaceId) {
    throw new Error('Could not determine workspace (team_id) from task.')
  }
  debug('Workspace ID:', workspaceId)

  info(`Fetching lists in folder ${teamPlatformFolderIdRaw} (Team - Platform)…`)
  const { lists } = await clickUp.getFolderLists(teamPlatformFolderIdRaw)
  if (!lists || lists.length === 0) {
    throw new Error('No lists found in Team - Platform folder.')
  }
  debug(
    'Lists:',
    lists.map((l) => ({ id: l.id, name: l.name })),
  )

  // API returns lists with current sprint first (Sprint 63, then 62, …)
  const currentSprint = lists[0]
  info(`Current sprint: ${currentSprint.name} (list id: ${currentSprint.id})`)

  const taskListId = (task as { list?: { id?: string } })?.list?.id
  if (taskListId === currentSprint.id) {
    info(`Task ${taskId} is already in current sprint "${currentSprint.name}"; skipping move (idempotent).`)
    debug('Task list id matches current sprint list id:', taskListId)
    return task
  }
  debug(`Task list id: ${taskListId}, current sprint list id: ${currentSprint.id}; moving task.`)

  info(`Moving task ${taskId} to ${currentSprint.name}…`)
  const result = await clickUp.moveTaskToList(String(workspaceId), taskId, currentSprint.id)
  debug('Move result:', result)
  return result
}
