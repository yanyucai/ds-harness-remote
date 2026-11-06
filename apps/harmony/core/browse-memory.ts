import { readPreference as prefRead, writePreference as prefWrite } from './private-preferences'

export interface ReadingPosition { key: string; offset: number; atBottom: boolean }
interface Entry { scope: string; session: string; position: ReadingPosition }
const STORAGE_KEY = 'dshremote.harmony-browse.v1'
const validId = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.length <= 4096
function position(value: unknown): ReadingPosition | undefined {
  const row = value as Partial<ReadingPosition> | undefined
  if (!row || typeof row.key !== 'string' || row.key.length > 4096 || typeof row.atBottom !== 'boolean'
    || typeof row.offset !== 'number' || !Number.isFinite(row.offset) || row.offset < 0 || row.offset > 10_000_000) return undefined
  return { key: row.key, offset: row.offset, atBottom: row.atBottom }
}

/** Bounded navigation metadata only. Never store messages, images or credentials. */
export class HarmonyBrowseMemory {
  resume = false
  private entries: Entry[] = []
  private recent?: { scope: string; session: string }
  private writes = Promise.resolve()

  async hydrate(): Promise<void> {
    try {
      const saved = JSON.parse(await prefRead(STORAGE_KEY) || '{}')
      this.resume = saved.resume === true
      if (validId(saved.last?.scope) && validId(saved.last?.session)) this.recent = { scope: saved.last.scope, session: saved.last.session }
      if (Array.isArray(saved.entries)) {
        for (const row of saved.entries.slice(-100)) {
          const restored = position(row?.position)
          if (restored && validId(row.scope) && validId(row.session)) this.entries.push({ scope: row.scope, session: row.session, position: restored })
        }
      }
    } catch { /* Invalid navigation metadata must not block startup. */ }
  }
  startup(): { scope: string; deviceId: string; sessionId: string } | undefined {
    if (!this.recent) return undefined
    try { const parts = JSON.parse(this.recent.scope) as string[]; return { scope: this.recent.scope, deviceId: parts[2], sessionId: this.recent.session } } catch { return undefined }
  }
  last(scope: string): string | undefined { return this.recent?.scope === scope ? this.recent.session : undefined }
  read(scope: string, session: string): ReadingPosition {
    return this.entries.find(row => row.scope === scope && row.session === session)?.position ?? { key: '', offset: 0, atBottom: true }
  }
  async setResume(enabled: boolean): Promise<void> { this.resume = enabled; await this.save() }
  async visit(scope: string, session: string): Promise<void> {
    if (!validId(scope) || !validId(session)) return
    this.recent = { scope, session }; await this.save()
  }
  async remember(scope: string, session: string, value: unknown): Promise<boolean> {
    const next = position(value)
    if (!next || !validId(scope) || !validId(session)) return false
    this.entries = [...this.entries.filter(row => row.scope !== scope || row.session !== session), { scope, session, position: next }].slice(-100)
    await this.save(); return true
  }
  private save(): Promise<void> {
    const raw = JSON.stringify({ resume: this.resume, last: this.recent, entries: this.entries })
    this.writes = this.writes.catch(() => undefined).then(() => prefWrite(STORAGE_KEY, raw))
    return this.writes
  }
}
