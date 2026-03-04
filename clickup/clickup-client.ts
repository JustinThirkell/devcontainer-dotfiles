/*
  ------------------------------------------------------------------------------------
  ClickUp API Client
  ------------------------------------------------------------------------------------
  Simple client for interacting with ClickUp API v2 (and v3 for move task)
  Based on: https://developer.clickup.com/reference/gettask
  Based on: https://developer.clickup.com/reference/updatetask
  Based on: https://developer.clickup.com/reference/getlists
  Based on: https://developer.clickup.com/reference/movetask
*/

const CLICKUP_API_BASE = 'https://api.clickup.com/api/v2'
const CLICKUP_API_BASE_V3 = 'https://api.clickup.com/api/v3'

export interface ClickUpClientOptions {
  apiKey: string
}

export class ClickUpClient {
  private apiKey: string

  constructor(options: ClickUpClientOptions) {
    this.apiKey = options.apiKey
  }

  async getAuthorizedUser(): Promise<unknown> {
    const url = `${CLICKUP_API_BASE}/user`

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: this.apiKey,
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.err) {
          errorMessage = errorJson.err
        } else if (errorJson.message) {
          errorMessage = errorJson.message
        }
      } catch {
        if (errorText) {
          errorMessage = `${errorMessage} - ${errorText}`
        }
      }
      throw new Error(errorMessage)
    }

    return await response.json()
  }

  async getTask(taskId: string): Promise<unknown> {
    const url = `${CLICKUP_API_BASE}/task/${taskId}`

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: this.apiKey,
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.err) {
          errorMessage = errorJson.err
        } else if (errorJson.message) {
          errorMessage = errorJson.message
        }
      } catch {
        // If parsing fails, use the raw error text if available
        if (errorText) {
          errorMessage = `${errorMessage} - ${errorText}`
        }
      }
      throw new Error(errorMessage)
    }

    return await response.json()
  }

  async updateTask(taskId: string, updates: { status?: string; [key: string]: unknown }): Promise<unknown> {
    const url = `${CLICKUP_API_BASE}/task/${taskId}`

    const response = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: this.apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(updates),
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.err) {
          errorMessage = errorJson.err
        } else if (errorJson.message) {
          errorMessage = errorJson.message
        }
      } catch {
        // If parsing fails, use the raw error text if available
        if (errorText) {
          errorMessage = `${errorMessage} - ${errorText}`
        }
      }
      throw new Error(errorMessage)
    }

    return await response.json()
  }

  async createTask(listId: string, task: { name: string; description?: string; assignees?: number[] }): Promise<unknown> {
    const url = `${CLICKUP_API_BASE}/list/${listId}/task`

    const body: { name: string; description?: string; assignees?: number[] } = { name: task.name }
    if (task.description !== undefined && task.description !== '') {
      body.description = task.description
    }
    if (task.assignees !== undefined && task.assignees.length > 0) {
      body.assignees = task.assignees
    }

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: this.apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.err) {
          errorMessage = errorJson.err
        } else if (errorJson.message) {
          errorMessage = errorJson.message
        }
      } catch {
        if (errorText) {
          errorMessage = `${errorMessage} - ${errorText}`
        }
      }
      throw new Error(errorMessage)
    }

    return await response.json()
  }

  /**
   * Get all lists in a folder (e.g. Team - Platform sprint folder).
   * GET /folder/{folder_id}/list
   */
  async getFolderLists(folderId: string): Promise<{ lists: Array<{ id: string; name: string; orderindex: number }> }> {
    const url = `${CLICKUP_API_BASE}/folder/${folderId}/list`

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: this.apiKey,
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.err) {
          errorMessage = errorJson.err
        } else if (errorJson.message) {
          errorMessage = errorJson.message
        }
      } catch {
        if (errorText) {
          errorMessage = `${errorMessage} - ${errorText}`
        }
      }
      throw new Error(errorMessage)
    }

    const body = (await response.json()) as
      | { lists: Array<{ id: string; name: string; orderindex: number }> }
      | Array<{ id: string; name: string; orderindex: number }>
    const lists = Array.isArray(body) ? body : body.lists
    return { lists }
  }

  /**
   * Move a task to a list (e.g. current sprint).
   * PUT /workspaces/{workspace_id}/tasks/{task_id}/home_list/{list_id}
   */
  async moveTaskToList(workspaceId: string, taskId: string, listId: string): Promise<unknown> {
    const url = `${CLICKUP_API_BASE_V3}/workspaces/${workspaceId}/tasks/${taskId}/home_list/${listId}`

    const response = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: this.apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({}),
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.err) {
          errorMessage = errorJson.err
        } else if (errorJson.message) {
          errorMessage = errorJson.message
        }
      } catch {
        if (errorText) {
          errorMessage = `${errorMessage} - ${errorText}`
        }
      }
      throw new Error(errorMessage)
    }

    return await response.json()
  }
}
