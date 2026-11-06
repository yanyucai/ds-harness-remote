import type { SessionTools, BackgroundJob } from '../../android/src/services/session-tools'
import type { RemoteGatewayStream } from '@dsh-remote/client-core'
const record = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value)

/** Authenticated, session-scoped observers. Output is bounded and never persisted. */
export class SessionActivity {
  jobs: BackgroundJob[] = []
  output = ''; outputJob = ''; lossy = false; error = ''; loading = false
  private controller?: AbortController
  private outputController?: AbortController
  private roster?: RemoteGatewayStream
  private stream?: RemoteGatewayStream
  private tools?: SessionTools
  private session = ''
  constructor(private readonly changed: () => void) {}
  stop(): void {
    this.controller?.abort(); this.outputController?.abort()
    void this.roster?.close().catch(() => {}); void this.stream?.close().catch(() => {})
    this.roster = undefined; this.stream = undefined; this.tools = undefined
    this.jobs = []; this.output = ''; this.outputJob = ''; this.error = ''; this.loading = false
  }
  start(tools: SessionTools, session: string): void {
    this.stop(); this.tools = tools; this.session = session
    if (!tools.watchJobs) return
    const controller = this.controller = new AbortController()
    this.loading = true
    void (async () => {
      try {
        const stream = await tools.watchJobs!(session, controller.signal)
        if (controller.signal.aborted) { await stream.close(); return }
        this.roster = stream
        for await (const frame of stream) {
          if (controller.signal.aborted) return
          if (!record(frame) || frame.type !== 'rows' || !Array.isArray(frame.jobs)) throw new Error('Invalid job roster')
          this.jobs = frame.jobs.filter((row): row is BackgroundJob => record(row) && typeof row.id === 'string' && typeof row.label === 'string'
            && (row.owner === undefined || row.owner === session) && ['running','stopping','completed','killed','failed'].includes(String(row.status)))
            .sort((a,b) => Number(b.status === 'running') - Number(a.status === 'running') || (b.startedAt ?? 0) - (a.startedAt ?? 0))
          this.loading = false; this.changed()
        }
      } catch { if (!controller.signal.aborted) { this.loading = false; this.error = '后台任务暂不可用'; this.changed() } }
    })()
  }
  async follow(id: string): Promise<void> {
    const tools = this.tools
    if (!tools?.followJob || !this.jobs.some(row => row.id === id)) throw new Error('后台任务不存在')
    this.outputController?.abort(); void this.stream?.close().catch(() => {})
    const controller = this.outputController = new AbortController()
    this.outputJob = id; this.output = ''; this.lossy = false
    const stream = await tools.followJob(this.session, id, controller.signal)
    if (controller.signal.aborted) { await stream.close(); return }
    this.stream = stream
    void (async () => {
      try {
        for await (const frame of stream) {
          if (controller.signal.aborted) return
          if (!record(frame)) continue
          if (frame.type === 'opened' && typeof frame.from === 'number' && frame.from > 0) this.lossy = true
          if (frame.type === 'output' && Array.isArray(frame.chunks)) {
            const text = frame.chunks.flatMap(row => record(row) && typeof row.text === 'string' ? [row.text] : []).join('')
            if (frame.lossy || frame.chunks.some(row => record(row) && row.gapBefore)) this.lossy = true
            if (this.output.length + text.length > 64000) this.lossy = true
            this.output = (this.output + text).slice(-64000)
          }
          this.changed()
        }
      } catch { if (!controller.signal.aborted) { this.error = '输出流已关闭，可重新打开'; this.changed() } }
    })()
  }
  async kill(id: string): Promise<void> {
    if (!this.tools?.killJob || !this.jobs.some(row => row.id === id)) throw new Error('当前任务无法停止')
    await this.tools.killJob(this.session, id, this.controller?.signal)
  }
}
