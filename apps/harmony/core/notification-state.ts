export interface ObservedTask { id: string; title: string; backend?: string; running: boolean; watched: boolean; updatedAt: number; inputIds: string[]; summary: string }
export interface TaskNotice { id: string; title: string; kind: 'ended' | 'input' }
export class TaskNotifications {
  private running = new Map<string, boolean>()
  private inputs = new Set<string>()
  reset(): void { this.running.clear(); this.inputs.clear() }
  observe(rows: ObservedTask[], selected: string, foreground: boolean, enabled: boolean): TaskNotice[] {
    const notices: TaskNotice[] = []
    const activeIds = new Set(rows.map(row => row.id))
    for (const key of this.running.keys()) if (!activeIds.has(key)) this.running.delete(key)
    const pending = new Set<string>()
    for (const row of rows) {
      const notify = enabled && row.watched && (!foreground || row.id !== selected)
      if (this.running.get(row.id) === true && !row.running && notify) notices.push({ id: row.id, title: row.title, kind: 'ended' })
      this.running.set(row.id, row.running)
      for (const id of row.inputIds) {
        const key = JSON.stringify([row.id, id]); pending.add(key)
        if (!this.inputs.has(key) && notify) notices.push({ id: row.id, title: row.title, kind: 'input' })
      }
    }
    this.inputs = pending
    return notices
  }
}
export function activeTask(rows: ObservedTask[], selected: string): ObservedTask | undefined {
  return rows.filter(row => row.watched && (row.running || row.inputIds.length))
    .sort((a,b) => Number(b.inputIds.length > 0)-Number(a.inputIds.length > 0) || Number(b.id === selected)-Number(a.id === selected) || b.updatedAt-a.updatedAt)[0]
}
