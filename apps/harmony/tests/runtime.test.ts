import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { HarmonyRuntime, cleanTerminalText } from '../core/runtime'
import { installPlatform } from '../core/platform'
import { controls, secrets, prefs } from './native/state'
import { resident } from './native/background'
import { notificationsRecord } from './native/notification'
import { generateKeyPair } from '@dsh-remote/crypto'
import type { AndroidRemoteConnection } from '../../android/src/services/connection'

let snapshot: Record<string, any>
let runtime: HarmonyRuntime
let publicKey: string
let devicesFailure = false
let onFrame: (frame: any) => void = () => undefined
let proxy: Record<string, any>
let sessionToolsPermissions: Array<{ value: string; name: string; description?: string }> = []
let sessionToolsFailure = false
let skills: Array<{ name: string; description: string; modelInvocable: boolean }> = []
let commandResult: (line: string) => { kind: 'success' | 'error'; text?: string } = () => ({ kind: 'success' })
let fileTree: (path: string) => { path: string; entries: Array<{ name: string; type: 'file' | 'directory' | 'other'; size?: number }>; truncated: boolean } =
  () => ({ path: '', entries: [], truncated: false })
const TEST_PDF_BYTES = new TextEncoder().encode('%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n')
function testPngBytes(): Uint8Array {
  const bytes = new Uint8Array(24)
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52])
  bytes[19] = 100; bytes[23] = 100
  return bytes
}
let fileStat: (path: string) => { absolutePath: string; version: string; bytes?: number } =
  path => ({ absolutePath: path, version: '1', bytes: 100 })
let fileBytes: (path: string, offset: number, length: number) => { absolutePath: string; version: string; offset: number; data: Uint8Array; bytes?: number; eof: boolean } =
  (path, offset, length) => ({ absolutePath: path, version: '1', offset, data: new Uint8Array(length), bytes: 100, eof: true })
let officeRender: (path: string) => { absolutePath: string; version: string; generation: string; offset: number; eof: boolean; bytes: number; data: Uint8Array; missingFonts: string[] } =
  path => ({
    absolutePath: path, version: '1', generation: 'gen-1', offset: 0, eof: true, bytes: TEST_PDF_BYTES.byteLength,
    data: TEST_PDF_BYTES, missingFonts: ['CustomFont.ttf'],
  })
let mockTerminals: Array<{ id: string; title: string; shell?: { name?: string }; cwd?: string; state: 'running' | 'exited' | 'failed'; cols: number; rows: number; exitCode: number | null }> = []
let mockTerminalWritten: string[] = []
let mockTerminalClosed: string[] = []
let mockTerminalCreated: any[] = []
let mockTerminalResized: Array<{ cols: number; rows: number }> = []
let mockTerminalStream: { push(frame: any): void } | undefined
const hostId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
let codexClient: any = undefined
let mockBotClient: any = undefined
let mockStats: any = undefined
let mockNetworkDetails: any = undefined
let mockOpenedLinks: string[] = []
let lastConnectOptions: any = undefined
const bridge = {
  connect: vi.fn(async (...args: any[]) => { onFrame = args[4]; lastConnectOptions = args[5] }), close: vi.fn(async () => undefined),
  requireProxy: () => proxy,
  configureHistory: vi.fn(async () => undefined),
  checkHealth: vi.fn(async () => true),
  requireSessionTools: () => ({ permissionOptions: async () => {
    if (sessionToolsFailure) throw new Error('old host')
    return sessionToolsPermissions
  }, listSkills: async () => skills, executeCommand: async (_id: string, line: string) => commandResult(line),
    listFiles: async (_id: string, path: string) => fileTree(path),
    readFile: async (_id: string, path: string, offset?: number) => ({ absolutePath: path, version: '1', text: 'hello', offset: offset ?? 1, lines: 1, eof: true }),
    statFile: async (_id: string, path: string) => fileStat(path),
    readBytes: async (_id: string, path: string, offset: number, length: number) => fileBytes(path, offset, length),
    officeGeneration: async () => 'gen-1',
    renderOfficePdf: async (_id: string, path: string) => officeRender(path),
    terminalEnvironment: async () => ({ maxInputBytes: 4096, maxCols: 200, maxRows: 80 }),
    listTerminals: async () => [...mockTerminals],
    createTerminal: async (_sessionId: string, id: string, cols: number, rows: number) => {
      const created = { id, title: `shell-${id}`, shell: { name: 'zsh' }, state: 'running' as const, cols, rows, exitCode: null }
      mockTerminalCreated.push(created)
      mockTerminals.push(created)
      return created
    },
    retainTerminal: async () => ({
      async *[Symbol.asyncIterator]() {
        yield { type: 'retained' }
      },
      close: async () => undefined,
    }),
    followTerminal: async (_sessionId: string, id: string, attachmentId: string) => {
      let closed = false
      const queue: any[] = [
        { type: 'snapshot', sequence: 1, screen: '\x1b[32mhello terminal\x1b[0m\r\n', info: { id, title: `shell-${id}`, shell: { name: 'zsh' }, state: 'running', controllerId: attachmentId, cols: 80, rows: 24, exitCode: null } }
      ]
      const waiters: Array<(val: any) => void> = []
      const stream = {
        [Symbol.asyncIterator]() {
          return {
            next() {
              if (closed) return Promise.resolve({ done: true, value: undefined })
              if (queue.length > 0) return Promise.resolve({ done: false, value: queue.shift() })
              return new Promise(resolve => waiters.push(resolve))
            }
          }
        },
        push(frame: any) {
          if (closed) return
          if (waiters.length > 0) waiters.shift()!({ done: false, value: frame })
          else queue.push(frame)
        },
        async close() {
          closed = true
          while (waiters.length > 0) waiters.shift()!({ done: true, value: undefined })
        }
      }
      mockTerminalStream = stream
      return stream
    },
    writeTerminal: async (_sessionId: string, _id: string, _attachmentId: string, data: string) => {
      mockTerminalWritten.push(data)
    },
    resizeTerminal: async (_sessionId: string, _id: string, _attachmentId: string, cols: number, rows: number) => {
      mockTerminalResized.push({ cols, rows })
    },
    closeTerminal: async (_sessionId: string, id: string) => {
      mockTerminalClosed.push(id)
      mockTerminals = mockTerminals.filter(t => t.id !== id)
    },
  }),
  hasCodex: () => codexClient !== undefined,
  requireCodex: () => {
    if (!codexClient) throw new Error('no codex client')
    return codexClient
  },
  requireBotClient: () => {
    if (!mockBotClient) throw new Error('no bot client')
    return mockBotClient
  },
  getStats: () => mockStats ?? { connected: true, mode: 'Relay', bytesSent: 1024, bytesReceived: 2048 },
  getNetworkDetails: async () => mockNetworkDetails,
  hasPi: () => false, hasClaude: () => false, hasOpencode: () => false, hasAntigravity: () => false, hasCursor: () => false, hasHermes: () => false,
}
beforeAll(() => {
  Object.defineProperty(globalThis, 'crypto', { value: globalThis.crypto, writable: true, configurable: true })
  installPlatform()
})
beforeEach(async () => {
  secrets.clear(); prefs.clear(); controls.vaultFailure = false; devicesFailure = false; publicKey = generateKeyPair().publicKey
  notificationsRecord.reset()
  codexClient = undefined
  mockBotClient = undefined
  mockStats = undefined
  mockNetworkDetails = undefined
  mockOpenedLinks = []
  lastConnectOptions = undefined
  sessionToolsPermissions = []; sessionToolsFailure = false
  skills = []; commandResult = () => ({ kind: 'success' }); fileTree = () => ({ path: '', entries: [], truncated: false })
  mockTerminals = []; mockTerminalWritten = []; mockTerminalClosed = []; mockTerminalCreated = []; mockTerminalResized = []; mockTerminalStream = undefined
  bridge.connect.mockClear(); bridge.close.mockClear()
  proxy = { workspaceList: async () => ({ items: [] }), sessionList: async () => [] }
  controls.fetch = async request => {
    const path = new URL(request.url).pathname
    const body = path === '/api/v1/auth/login' ? { token: 'account-token-123456789', account: 'owner@example.com', isAdmin: false, expiresAt: Date.now() + 60000 }
      : path === '/api/v1/auth/oauth/providers' ? { items: [{ id: 'github', displayName: 'GitHub', startUrl: '/api/v1/auth/oauth/github/start' }, { id: 'zhihu', displayName: '知乎', startUrl: '/api/v1/auth/oauth/start' }] }
      : path === '/api/v1/auth/me' ? { account: 'oauth-owner@example.com', isAdmin: false }
      : path === '/api/v1/devices/register' ? { accessToken: 'access-token-123456789', refreshToken: 'refresh-token-123456789', accessTokenExpiresAt: Date.now() + 600000, refreshTokenExpiresAt: Date.now() + 6000000 }
      : path === '/api/v1/devices' ? { items: [{ deviceId: hostId, name: 'My Host', role: 'host', platform: 'linux', membershipId: 'member-123', online: true }] }
      : { deviceId: hostId, name: 'My Host', role: 'host', platform: 'linux', membershipId: 'member-123', identityKey: publicKey, online: true }
    if (devicesFailure && path === '/api/v1/devices') return Response.json({ error: { code: 'TEMPORARY_FAILURE', message: 'Temporary failure' } }, { status: 503 })
    return Response.json(body)
  }
  runtime = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
  runtime.attachContext({ openLink: async (url: string) => { mockOpenedLinks.push(url) } } as Object)
  runtime.setListener(raw => { snapshot = JSON.parse(raw) })
  await runtime.initialize()
})
afterEach(async () => { await runtime.dispose(); controls.fetch = undefined; controls.vaultFailure = false })
async function login(server = 'https://one.example') { await runtime.perform('login', JSON.stringify({ server, email: 'owner@example.com', password: 'test-password' })) }

describe('Harmony authorization and trust lifecycle', () => {
  it('requires explicit first trust, pins the host key, and blocks a replacement key', async () => {
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    expect(snapshot.view).toBe('trust'); expect(bridge.connect).not.toHaveBeenCalled()
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    expect(bridge.connect).toHaveBeenCalledTimes(1); expect(snapshot.connected).toBe(true)
    await runtime.perform('disconnect', '{}')
    publicKey = generateKeyPair().publicKey
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    expect(snapshot.error).toContain('身份公钥已改变')
    expect(bridge.connect).toHaveBeenCalledTimes(1)
  })

  it('isolates trust by server and restores the same identity after process restart', async () => {
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('disconnect', '{}')
    const identity = secrets.get('dsh.harmony.identity')
    await login('https://two.example')
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    expect(snapshot.candidate.trusted).toBe(false)
    expect(bridge.connect).toHaveBeenCalledTimes(1)
    await runtime.dispose()
    runtime = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
    runtime.setListener(raw => { snapshot = JSON.parse(raw) })
    await runtime.initialize()
    expect(snapshot.view).toBe('devices'); expect(snapshot.account).toBe('owner@example.com')
    expect(secrets.get('dsh.harmony.identity')).toEqual(identity)
  })

  it('retains a known device list on network failure instead of fabricating empty success', async () => {
    await login(); expect(snapshot.devices).toHaveLength(1)
    devicesFailure = true; await runtime.perform('refresh', '{}')
    expect(snapshot.devices).toHaveLength(1); expect(snapshot.error).toContain('Temporary failure')
  })

  it('does not replace an identity when secure storage is locked', async () => {
    const stored = secrets.get('dsh.harmony.identity')
    controls.vaultFailure = true
    const locked = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
    let error = ''; locked.setListener(raw => { error = JSON.parse(raw).error })
    await locked.initialize()
    expect(error).toContain('安全存储读取失败')
    expect(secrets.get('dsh.harmony.identity')).toEqual(stored)
    await locked.dispose()
  })
  it('cancels an in-flight host lookup before it can reopen a disconnected connection', async () => {
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('disconnect', '{}')
    const original = controls.fetch!
    let release: () => void = () => undefined
    let entered: () => void = () => undefined
    const lookupEntered = new Promise<void>(resolve => { entered = resolve })
    const pendingLookup = new Promise<void>(resolve => { release = resolve })
    controls.fetch = async request => {
      if (request.url.endsWith('/' + hostId)) { entered(); await pendingLookup }
      return original(request)
    }
    const pending = runtime.perform('connect', JSON.stringify({ id: hostId }))
    await lookupEntered
    await runtime.perform('disconnect', '{}'); release(); await pending
    expect(snapshot.connected).toBe(false); expect(snapshot.view).toBe('devices'); expect(bridge.connect).toHaveBeenCalledTimes(1)
  })

  it('allows only single-use approvals while a prompt is pending, and rejects them after disconnect', async () => {
    let finishPrompt: () => void = () => undefined
    proxy = {
      workspaceList: async () => ({ items: [{ workspaceId: 'w1', title: 'Workspace', path: '/project', sessionIds: ['s1'] }] }),
      sessionList: async () => [{ sessionId: 's1', title: 'Session', blank: false, running: false, updatedAt: 0 }],
      sessionHistory: async () => ({ events: [], hasMore: false }),
      sessionModels: async () => ({ current: { provider: 'provider', model: 'model' }, groups: [], routable: true }),
      sessionPrompt: vi.fn(() => new Promise<void>(resolve => { finishPrompt = resolve })),
      respondApproval: vi.fn(async () => undefined),
    }
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('workspace', '{"id":"w1"}'); await runtime.perform('session', '{"id":"s1"}')
    const sending = runtime.perform('prompt', '{"text":"hello"}')
    onFrame({ rpcId: 'event-1', payload: { type: 'approval/requested', sessionId: 's1', approvalId: 'approval-1', toolName: 'Bash' } })
    // Obtain the reducer-owned row id without hardcoding its implementation.
    await new Promise(resolve => setTimeout(resolve, 60))
    const row = snapshot.rows.find((item: any) => item.kind === 'approval')
    expect(row).toBeDefined()
    await runtime.perform('approval', JSON.stringify({ id: row.id, decision: 'always' }))
    expect(proxy.respondApproval).not.toHaveBeenCalled()
    await runtime.perform('approval', JSON.stringify({ id: row.id, decision: 'allow_once' }))
    expect(proxy.respondApproval).toHaveBeenCalledWith('event-1', 's1', 'approval-1', 'allowed-once')
    await runtime.perform('disconnect', '{}')
    await runtime.perform('approval', JSON.stringify({ id: row.id, decision: 'allow_once' }))
    expect(proxy.respondApproval).toHaveBeenCalledTimes(1)
    finishPrompt(); await sending
  })

  it('names sessions from the Host projection and refreshes the name when a turn ends', async () => {
    const named = { sessionId: 's1', blank: false, running: false, updatedAt: 0, projections: { values: { sessionListMetadata: { blank: false }, title: '整理周报' } } }
    const blank = { sessionId: 's2', blank: true, running: false, updatedAt: 0, projections: { values: { sessionListMetadata: { blank: true }, title: null } } }
    let rows: any[] = [named, blank]
    proxy = {
      workspaceList: async () => ({ items: [{ workspaceId: 'w1', title: 'Workspace', path: '/project', sessionIds: ['s1', 's2'] }] }),
      sessionList: async () => rows,
      sessionHistory: async () => ({ events: [], hasMore: false }),
    }
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('workspace', '{"id":"w1"}')
    expect(snapshot.sessions.map((row: any) => row.name)).toEqual(['整理周报', '新对话'])
    await runtime.perform('session', '{"id":"s1"}'); expect(snapshot.title).toBe('整理周报')
    // The Host renames a blank session from its first prompt; the ended turn must pull that back.
    rows = [named, { ...blank, blank: false, projections: { values: { sessionListMetadata: { blank: false }, title: '修复登录' } } }]
    await runtime.perform('session', '{"id":"s2"}')
    onFrame({ rpcId: 'event-1', payload: { type: 'session/event', sessionId: 's2', event: { type: 'turn/start', seq: 1, time: Date.now(), data: { turn: 1 } } } } as any)
    onFrame({ rpcId: 'event-2', payload: { type: 'session/event', sessionId: 's2', event: { type: 'turn/end', seq: 2, time: Date.now(), data: { turn: 1, reason: { kind: 'completed' } } } } } as any)
    await new Promise(resolve => setTimeout(resolve, 60))
    expect(snapshot.running).toBe(false)
    expect(snapshot.sessions.find((row: any) => row.id === 's2').name).toBe('修复登录')
    expect(snapshot.title).toBe('修复登录')
  })

  it('localizes a server host-offline error and never opens a transport for it', async () => {
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId }))
    const original = controls.fetch!
    controls.fetch = async request => request.url.endsWith('/' + hostId)
      ? Response.json({ error: { code: 'HOST_OFFLINE', message: 'host is offline', retryable: true } }, { status: 409 })
      : original(request)
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    expect(snapshot.error).toContain('已离线')
    expect(snapshot.connected).toBe(false)
    expect(bridge.connect).not.toHaveBeenCalled()
  })

})

describe('Harmony session overview, archiving and message actions', () => {
  const sessionRow = (id: string, updatedAt: number) => ({
    sessionId: id, blank: false, running: false, updatedAt,
    projections: { values: { sessionListMetadata: { blank: false }, title: `会话 ${id}` } },
  })
  const assistantEvent = (seq?: number) => ({
    event: {
      type: 'assistant/message', ...(seq === undefined ? {} : { seq }), time: 1730000000000,
      data: { message: { id: 'm1', content: [{ type: 'text', text: '**已完成** 修复登录' }] }, turn: 't1', usage: { inputTokens: 1200, outputTokens: 300, totalTokens: 1500 } },
    },
  })
  const catalogProxy = (extra: Record<string, any> = {}) => ({
    workspaceList: async () => ({ items: [{ workspaceId: 'w1', title: 'Alpha', path: '/a', sessionIds: ['s1', 's2'] }], archivedSessionIds: [] }),
    sessionList: async () => [sessionRow('s1', 2000), sessionRow('s2', 1000)],
    sessionHistory: async () => ({ events: [], hasMore: false }),
    sessionModels: async () => ({ current: { provider: 'p', model: 'm' }, groups: [], routable: true }),
    messageFeedbackList: async () => [],
    ...extra,
  })
  async function connected(_proxy: Record<string, any>) {
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
  }

  it('pages the grouped overview, expands on demand, and keeps view state out of the asset vault', async () => {
    const rows = ['s1', 's2', 's3', 's4', 's5'].map((id, index) => sessionRow(id, 1000 + index))
    proxy = catalogProxy({
      workspaceList: async () => ({ items: [{ workspaceId: 'w1', title: 'Alpha', path: '/a', sessionIds: rows.map(row => row.sessionId) }], archivedSessionIds: [] }),
      sessionList: async () => rows,
    })
    await connected(proxy)
    expect(snapshot.backends.map((tab: any) => tab.id)).toEqual(['harness'])
    expect(snapshot.overview.filter((row: any) => row.kind === 'group').map((row: any) => row.name)).toEqual(['Alpha'])
    expect(snapshot.overview.filter((row: any) => row.kind === 'session' && !row.hidden).map((row: any) => row.id))
      .toEqual(['s5', 's4', 's3'])
    expect(snapshot.overview.find((row: any) => row.kind === 'more').remaining).toBe(2)
    await runtime.perform('showMore', JSON.stringify({ id: 'workspace:harness:w1' }))
    expect(snapshot.overview.filter((row: any) => row.kind === 'session' && !row.hidden)).toHaveLength(5)
    expect(snapshot.overview.some((row: any) => row.kind === 'more')).toBe(false)
    await runtime.perform('toggleGroup', JSON.stringify({ id: 'workspace:harness:w1' }))
    expect(snapshot.overview.find((row: any) => row.kind === 'group').expanded).toBe(false)
    expect(snapshot.overview.filter((row: any) => row.kind === 'session')).toHaveLength(0)
    await runtime.perform('favorite', JSON.stringify({ id: 'w1' }))
    await runtime.perform('session', JSON.stringify({ id: 's2' }))
    expect(snapshot.overview.filter((row: any) => row.kind === 'group').map((row: any) => row.name)).toEqual(['最近访问', 'Alpha'])
    expect([...secrets.keys()].some(key => key.includes('view.'))).toBe(false)
    expect([...prefs.keys()].some(key => key.startsWith('view.'))).toBe(true)

    const restored = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
    const seen: Record<string, any>[] = []
    restored.setListener(raw => { seen.push(JSON.parse(raw)) })
    await restored.initialize()
    await restored.perform('connect', JSON.stringify({ id: hostId }))
    const last = seen[seen.length - 1]
    expect(last.workspaces[0].favorite).toBe(true)
    expect(last.overview.filter((row: any) => row.kind === 'group').map((row: any) => row.name)).toEqual(['最近访问', 'Alpha'])
    const recentGroup = last.overview.filter((row: any) => row.kind === 'session').map((row: any) => row.id)
    expect(recentGroup[0]).toBe('s2')
    await restored.dispose()
  })

  it('honours the archive filter using the Host-confirmed archive set', async () => {
    proxy = catalogProxy({ workspaceArchiveSession: vi.fn(async () => ['s2']) })
    await connected(proxy)
    await runtime.perform('archive', JSON.stringify({ id: 's2' }))
    expect(proxy.workspaceArchiveSession).toHaveBeenCalledWith('s2')
    expect(snapshot.archivedCount).toBe(1)
    expect(snapshot.overview.filter((row: any) => row.kind === 'session').map((row: any) => row.id)).toEqual(['s1'])
    expect(snapshot.sessions.map((row: any) => row.id)).toEqual(['s1'])
    await runtime.perform('archiveFilter', JSON.stringify({ mode: 'only' }))
    const archived = snapshot.overview.filter((row: any) => row.kind === 'session')
    expect(archived.map((row: any) => row.id)).toEqual(['s2'])
    expect(archived[0].description).toBe('已归档')
    await runtime.perform('archiveFilter', JSON.stringify({ mode: 'all' }))
    expect(snapshot.overview.filter((row: any) => row.kind === 'session').map((row: any) => row.id)).toEqual(['s1', 's2'])
  })

  it('restores Android defaults when the drawer opens instead of inheriting a stale filter', async () => {
    proxy = catalogProxy()
    await connected(proxy)
    await runtime.perform('archiveFilter', JSON.stringify({ mode: 'only' }))
    await runtime.perform('groupMode', JSON.stringify({ mode: 'list' }))
    expect(snapshot.archiveFilter).toBe('only')
    expect(snapshot.overview.filter((row: any) => row.kind === 'session')).toHaveLength(0)
    await runtime.perform('openDrawer', JSON.stringify({}))
    expect(snapshot.archiveFilter).toBe('hidden')
    expect(snapshot.groupBy).toBe('workspace')
    expect(snapshot.overview.filter((row: any) => row.kind === 'group').map((row: any) => row.meta)).toEqual(['2 条'])

    // A blob written by an older build must not empty the drawer across a restart either.
    const key = [...prefs.keys()].find(row => row.startsWith('view.'))!
    prefs.set(key, JSON.stringify({ favorites: [], recents: [], collapsed: [], groupBy: 'list', orderBy: 'manual', archiveFilter: 'only' }))
    const restored = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
    const seen: Record<string, any>[] = []
    restored.setListener(raw => { seen.push(JSON.parse(raw)) })
    await restored.initialize()
    await restored.perform('connect', JSON.stringify({ id: hostId }))
    const last = seen[seen.length - 1]
    expect(last.archiveFilter).toBe('hidden')
    expect(last.overview.filter((row: any) => row.kind === 'session')).toHaveLength(2)
    await restored.dispose()
  })

  it('archives the selected session without leaving a dead chat stream behind', async () => {
    const close = vi.fn(async () => undefined)
    proxy = catalogProxy({ workspaceArchiveSession: vi.fn(async () => ['s1']), stream: () => close })
    await connected(proxy)
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    expect(snapshot.view).toBe('chat')
    await runtime.perform('archive', JSON.stringify({ id: 's1' }))
    expect(snapshot.view).toBe('workspaces')
    expect(snapshot.sessionKey).toBe('')
    expect(snapshot.rows).toHaveLength(0)
  })

  it('exposes trajectory metadata on every row so the trace view needs no new endpoint', async () => {
    proxy = catalogProxy({ sessionHistory: async () => ({ events: [assistantEvent(7)], hasMore: true }) })
    await connected(proxy)
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    const row = snapshot.rows.find((item: any) => item.kind === 'message')
    expect(row.category).toBe('assistant')
    expect(row.turn).toBe('t1')
    expect(row.preview).toBe('已完成 修复登录')
    expect(row.tokens).toBe('1,500 tokens')
    expect(row.actionable).toBe(true)
    expect(row.clock).toMatch(/^\d{2}:\d{2}$/)
  })

  it('surfaces turnEnd failure details on failed turns without leaving an empty assistant message', async () => {
    const failedTurnEvent = {
      event: {
        type: 'turn/end', time: 1730000001000, seq: 10,
        data: { turn: 't2', reason: { kind: 'error', error: { message: '模型配额已用尽' } } },
      },
    }
    proxy = catalogProxy({ sessionHistory: async () => ({ events: [failedTurnEvent], hasMore: false }) })
    await connected(proxy)
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    const failureRow = snapshot.rows.find((item: any) => item.kind === 'message')
    expect(failureRow).toBeDefined()
    expect(failureRow.text).toBe('模型配额已用尽')
    expect(failureRow.preview).toBe('模型配额已用尽')
  })

  it('forks only from a durable message boundary and opens the branch the Host confirms', async () => {
    let events: any[] = [assistantEvent(undefined)]
    let rows = [sessionRow('s1', 2000), sessionRow('s2', 1000)]
    proxy = catalogProxy({
      sessionHistory: async () => ({ events, hasMore: false }),
      sessionList: async () => rows,
      sessionFork: vi.fn(async () => { rows = [...rows, sessionRow('s9', 3000)]; return { sessionId: 's9' } }),
    })
    await connected(proxy)
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    const row = snapshot.rows.find((item: any) => item.kind === 'message')
    expect(row.actionable).toBe(true)
    await runtime.perform('fork', JSON.stringify({ id: row.id }))
    expect(snapshot.error).toContain('持久边界')
    expect(proxy.sessionFork).not.toHaveBeenCalled()

    events = [assistantEvent(7)]
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    const durable = snapshot.rows.find((item: any) => item.kind === 'message')
    await runtime.perform('fork', JSON.stringify({ id: durable.id }))
    expect(proxy.sessionFork).toHaveBeenCalledWith('s1', 7)
    expect(JSON.parse(snapshot.sessionKey)[1]).toBe('s9')
    expect(snapshot.title).toBe('会话 s9')
  })

  it('shows a rating only after the Host reads it back', async () => {
    proxy = catalogProxy({
      sessionHistory: async () => ({ events: [assistantEvent(7)], hasMore: false }),
      messageFeedbackPut: vi.fn(async () => ({ messageId: 'm1', rating: 'negative', version: 'v1' })),
    })
    await connected(proxy)
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    const row = snapshot.rows.find((item: any) => item.kind === 'message')
    expect(row.feedback).toBe('')
    await runtime.perform('feedback', JSON.stringify({ id: row.id, rating: 'thumbs_up' }))
    expect(snapshot.error).toContain('点赞或点踩')
    expect(proxy.messageFeedbackPut).not.toHaveBeenCalled()
    await runtime.perform('feedback', JSON.stringify({ id: row.id, rating: 'negative' }))
    expect(proxy.messageFeedbackPut).toHaveBeenCalledWith('s1', row.id, 'negative')
    expect(snapshot.rows.find((item: any) => item.id === row.id).feedback).toBe('negative')
  })
})

describe('Harmony composer panel, queue and workspace management', () => {
  const sessionRow = (id: string, extra: Record<string, any> = {}) => ({
    sessionId: id, blank: false, running: false, updatedAt: 1000,
    projections: { values: { sessionListMetadata: { blank: false }, title: `会话 ${id}` } }, ...extra,
  })
  const harnessProxy = (extra: Record<string, any> = {}) => ({
    workspaceList: async () => ({ items: [
      { workspaceId: 'w1', title: 'Alpha', path: '/a', sessionIds: ['s1'] },
      { workspaceId: 'w2', title: 'Beta', path: '/b', sessionIds: [] },
    ], archivedSessionIds: [] }),
    sessionList: async () => [sessionRow('s1')],
    sessionHistory: async () => ({ events: [], hasMore: false }),
    sessionModels: async () => ({ current: { provider: 'p', model: 'm' }, groups: [], routable: true }),
    messageFeedbackList: async () => [],
    agentPresetList: async () => ({ presets: [{ id: 'standard', isDefault: true, name: '标准模式' }, { id: 'broken-one', isDefault: false, name: '坏预设', broken: 'missing entry' }] }),
    agentPresetSelect: vi.fn(async () => 'chosen'),
    sessionSelectPermission: vi.fn(async () => undefined),
    sessionUpdateQueue: vi.fn(async () => undefined),
    workspaceRename: vi.fn(async (_id: string, title: string) => ({ workspaceId: 'w1', title })),
    workspaceDelete: vi.fn(async () => undefined),
    workspaceInsertBefore: vi.fn(async () => ['w2', 'w1']),
    workspaceArchiveSession: vi.fn(async () => ['s1']),
    sessionCreate: vi.fn(async () => ({ sessionId: 's7' })),
    ...extra,
  })
  async function openChat(_proxy: Record<string, any>) {
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('workspace', JSON.stringify({ id: 'w1' })); await runtime.perform('session', JSON.stringify({ id: 's1' }))
  }

  it('shows the Host inbox queue and only offers actions for rows that carry an item id', async () => {
    proxy = harnessProxy({
      sessionList: async () => [sessionRow('s1', { projections: { values: { inbox: { 'next-turn': [
        { id: 'q1', content: [{ type: 'text', text: '先跑测试' }], source: { rpcId: 'rpc-1' } },
        { content: [{ type: 'text', text: '无 id 的行' }] },
      ] } } } })],
    })
    await openChat(proxy)
    onFrame({ rpcId: 'rpc-9', payload: { type: 'session/event', sessionId: 's1', event: { type: 'user/message', seq: 3, time: Date.now(), data: { id: 'local-1', message: { id: 'local-1', source: 'user', content: [{ type: 'text', text: '本地待发' }] } } } } } as any)
    await new Promise(resolve => setTimeout(resolve, 80))
    expect(snapshot.queue[0]).toMatchObject({ id: 'q1', preview: '先跑测试', host: true })
    expect(snapshot.queue[1]).toMatchObject({ id: '', preview: '无 id 的行', host: true })
    const local = snapshot.queue.filter((row: any) => !row.host)
    expect(local).toEqual([])
    await runtime.perform('queueAction', JSON.stringify({ id: 'q1', mode: 'steer' }))
    expect(proxy.sessionUpdateQueue).toHaveBeenCalledWith('s1', 'q1', { kind: 'steer' })
    await runtime.perform('queueAction', JSON.stringify({ id: 'q1', mode: 'push' }))
    expect(snapshot.error).toContain('移出队列或立即发送')
  })

  it('loads mode and permission rosters, disables broken presets, and keeps a rejected switch on the started-session copy', async () => {
    sessionToolsFailure = true
    proxy = harnessProxy()
    await openChat(proxy)
    await runtime.perform('morePanel', '{}')
    expect(snapshot.modes.map((row: any) => [row.id, row.broken])).toEqual([['standard', false], ['broken-one', true]])
    expect(snapshot.permissions).toEqual([])
    expect(snapshot.panelWarning).toBe('操作权限列表暂不可用。')
    sessionToolsFailure = false
    sessionToolsPermissions = [{ value: 'read-only', name: '仅可查看' }, { value: 'full', name: '完全权限' }]
    await runtime.perform('morePanel', '{}')
    expect(snapshot.permissions.map((row: any) => [row.id, row.current])).toEqual([['read-only', false], ['full', false]])
    await runtime.perform('selectMode', JSON.stringify({ id: 'ptc' }))
    expect(proxy.agentPresetSelect).toHaveBeenCalledWith('s1', 'ptc')
    expect(snapshot.currentMode).toBe('ptc')

    proxy.agentPresetSelect = vi.fn(async () => { throw new Error('host refused') })
    await runtime.perform('selectMode', JSON.stringify({ id: 'minimal' }))
    expect(snapshot.error).toContain('只能在开始之前更改')
  })

  it('keeps quick prompts across restarts and records deleted built-ins instead of re-seeding them', async () => {
    proxy = harnessProxy()
    await openChat(proxy)
    expect(snapshot.prompts.map((row: any) => row.builtIn)).toEqual([true, true, true])
    await runtime.perform('savePrompt', JSON.stringify({ id: '', name: '周报', text: '总结本周改动' }))
    expect(snapshot.prompts).toHaveLength(4)
    expect(snapshot.prompts[3]).toMatchObject({ title: '周报', builtIn: false })
    await runtime.perform('deletePrompt', JSON.stringify({ id: 'builtin-commit' }))
    expect(snapshot.prompts.map((row: any) => row.title)).not.toContain('提交改动')

    const second = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
    const seen: Record<string, any>[] = []
    second.setListener(raw => { seen.push(JSON.parse(raw)) })
    await second.initialize()
    const titles = seen[seen.length - 1].prompts.map((row: any) => row.title)
    expect(titles).toContain('周报')
    expect(titles).not.toContain('提交改动')
    await second.dispose()
    expect([...secrets.keys()].some(key => key.includes('prompts'))).toBe(false)
    expect([...prefs.keys()].some(key => key.startsWith('prompts'))).toBe(true)
  })

  it('restores the stored draft when the same conversation opens again', async () => {
    proxy = harnessProxy()
    await openChat(proxy)
    await runtime.perform('saveDraft', JSON.stringify({ id: snapshot.sessionKey, text: '草稿内容' }))
    await runtime.perform('back', '{}')
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    expect(snapshot.draft).toBe('草稿内容')
  })

  it('manages Harness workspaces only, and reorders with the neighbour the Host must place before', async () => {
    proxy = harnessProxy()
    await openChat(proxy)
    await runtime.perform('renameWorkspace', JSON.stringify({ id: 'w1', name: 'Alpha 改名' }))
    expect(proxy.workspaceRename).toHaveBeenCalledWith('w1', 'Alpha 改名')
    await runtime.perform('moveWorkspace', JSON.stringify({ id: 'w1', mode: 'up' }))
    expect(snapshot.error).toContain('列表两端')
    expect(proxy.workspaceInsertBefore).not.toHaveBeenCalled()
    await runtime.perform('moveWorkspace', JSON.stringify({ id: 'w2', mode: 'up' }))
    expect(proxy.workspaceInsertBefore).toHaveBeenCalledWith('w2', 'w1')
    expect(snapshot.orderBy).toBe('manual')
    await runtime.perform('deleteWorkspace', JSON.stringify({ id: 'w2' }))
    expect(proxy.workspaceDelete).toHaveBeenCalledWith('w2')
  })

  it('moves only an untouched conversation and archives the placeholder it replaces', async () => {
    proxy = harnessProxy()
    await openChat(proxy)
    await runtime.perform('moveSession', JSON.stringify({ id: 'w2' }))
    expect(snapshot.error).toContain('工作目录不能更改')
    expect(proxy.sessionCreate).not.toHaveBeenCalled()

    proxy.sessionList = async () => [sessionRow('s1', { blank: true })]
    await runtime.perform('back', '{}'); await runtime.perform('catalog', '{}'); await runtime.perform('session', JSON.stringify({ id: 's1' }))
    expect(snapshot.sessionBlank).toBe(true)
    await runtime.perform('moveSession', JSON.stringify({ id: 'w2' }))
    expect(proxy.sessionCreate).toHaveBeenCalledWith('w2')
    expect(proxy.workspaceArchiveSession).toHaveBeenCalledWith('s1')
    expect(JSON.parse(snapshot.sessionKey)[1]).toBe('s7')
  })

  it('unbinds a host through the account endpoint and returns to the device list', async () => {
    proxy = harnessProxy()
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    const calls: string[] = []
    const original = controls.fetch!
    controls.fetch = async request => {
      if (request.method === 'DELETE') calls.push(new URL(request.url).pathname)
      return original(request)
    }
    await runtime.perform('forgetHost', JSON.stringify({ id: hostId }))
    expect(calls).toEqual([`/api/v1/account/devices/${hostId}`])
    expect(snapshot.view).toBe('devices')
  })
})

describe('Harmony auto-connect and foreground recovery', () => {
  const sessionRow = (id: string, updatedAt: number) => ({
    sessionId: id, blank: false, running: false, updatedAt,
    projections: { values: { sessionListMetadata: { blank: false }, title: `会话 ${id}` } },
  })
  const catalogProxy = (extra: Record<string, any> = {}) => ({
    workspaceList: async () => ({ items: [{ workspaceId: 'w1', title: 'Alpha', path: '/a', sessionIds: ['s1', 's2'] }], archivedSessionIds: [] }),
    sessionList: async () => [sessionRow('s1', 2000), sessionRow('s2', 1000)],
    sessionHistory: async () => ({ events: [], hasMore: false }),
    sessionModels: async () => ({ current: { provider: 'p', model: 'm' }, groups: [], routable: true }),
    messageFeedbackList: async () => [],
    ...extra,
  })
  const lastHostKey = 'lastHost.https://one.example|owner@example.com'
  /** A cold start is a fresh runtime over the same vault and preferences. */
  async function coldStart(target: Record<string, any> = bridge): Promise<HarmonyRuntime> {
    const instance = new HarmonyRuntime(target as unknown as AndroidRemoteConnection)
    instance.attachContext({} as Object)
    instance.setListener(raw => { snapshot = JSON.parse(raw) })
    await instance.initialize()
    return instance
  }
  function dropTrustRecords(): void {
    for (const key of [...secrets.keys()]) if (key.includes('.trust.')) secrets.delete(key)
  }

  it('re-opens the remembered host on cold start and keeps that memory out of the vault', async () => {
    proxy = catalogProxy()
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    expect(snapshot.connected).toBe(true)
    expect(prefs.get(lastHostKey)).toBe(hostId)
    expect([...secrets.keys()].some(key => key.includes('lastHost'))).toBe(false)

    await runtime.perform('disconnect', '{}')
    bridge.connect.mockClear()
    const next = await coldStart()
    expect(bridge.connect).toHaveBeenCalledTimes(1)
    expect(snapshot.connected).toBe(true)
    expect(snapshot.view).toBe('workspaces')
    expect(snapshot.error).toBe('')
    await next.dispose()
  })

  async function remembered(): Promise<void> {
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    expect(prefs.get(lastHostKey)).toBe(hostId)
    bridge.connect.mockClear()
  }
  function serveDevices(devices: Array<Record<string, any>>, presence?: { online?: boolean; status?: number }): () => void {
    const original = controls.fetch!
    controls.fetch = async request => {
      const path = new URL(request.url).pathname
      if (path === '/api/v1/devices') return Response.json({ items: devices })
      const row = devices.find(item => path === `/api/v1/devices/${item.deviceId}/presence`)
      if (row !== undefined) {
        if (presence?.status !== undefined) return Response.json({ error: { code: 'TEMPORARY_FAILURE', message: 'Temporary failure' } }, { status: presence.status })
        return Response.json({ deviceId: row.deviceId, online: presence?.online ?? row.online === true, lastSeenAt: null })
      }
      return original(request)
    }
    return () => { controls.fetch = original }
  }

  it('follows the live presence answer when the device record still says offline', async () => {
    await remembered()
    const restore = serveDevices([{ deviceId: hostId, name: 'My Host', role: 'host', platform: 'linux', membershipId: 'member-123', identityKey: publicKey, online: false }], { online: true })
    const next = await coldStart()
    restore()
    expect(bridge.connect).toHaveBeenCalledTimes(1)
    expect(snapshot.connected).toBe(true)
    expect(snapshot.devices[0].online).toBe(true)
    await next.dispose()
  })

  it('keeps the device record when the presence endpoint fails', async () => {
    await remembered()
    const restore = serveDevices([{ deviceId: hostId, name: 'My Host', role: 'host', platform: 'linux', membershipId: 'member-123', identityKey: publicKey, online: true }], { status: 503 })
    const next = await coldStart()
    restore()
    expect(snapshot.devices[0].online).toBe(true)
    expect(bridge.connect).toHaveBeenCalledTimes(1)
    await next.dispose()
  })

  it('will not auto-connect a host the server reports offline', async () => {
    await remembered()
    const restore = serveDevices([{ deviceId: hostId, name: 'My Host', role: 'host', platform: 'linux', membershipId: 'member-123', identityKey: publicKey, online: false }])
    const next = await coldStart()
    restore()
    expect(bridge.connect).not.toHaveBeenCalled()
    expect(snapshot.view).toBe('devices')
    expect(snapshot.error).toBe('')
    await next.dispose()
  })

  it('will not auto-connect once the local trust record is withdrawn', async () => {
    await remembered()
    dropTrustRecords()
    const next = await coldStart()
    expect(bridge.connect).not.toHaveBeenCalled()
    expect(snapshot.view).toBe('devices')
    expect(snapshot.error).toBe('')
    await next.dispose()
  })

  it('will not auto-connect a host that now presents a different key', async () => {
    await remembered()
    publicKey = generateKeyPair().publicKey
    const next = await coldStart()
    expect(bridge.connect).not.toHaveBeenCalled()
    expect(snapshot.view).toBe('devices')
    expect(snapshot.error).toBe('')
    await next.dispose()
  })

  it('treats an explicit 断开 as intent to stay off until the next manual connect', async () => {
    proxy = catalogProxy()
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('disconnect', '{}')
    bridge.connect.mockClear()
    await runtime.onForeground()
    expect(bridge.connect).not.toHaveBeenCalled()

    const started = resident.started
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    expect(snapshot.connected).toBe(true)
    expect(resident.started).toBe(started + 1)
    bridge.connect.mockClear()
    bridge.close.mockClear()
    await runtime.onBackground()
    // Hiding the app keeps the carrier: the resident task holds the sockets.
    expect(snapshot.connected).toBe(true)
    expect(bridge.close).not.toHaveBeenCalled()
    await runtime.onForeground()
    expect(bridge.connect).not.toHaveBeenCalled()
    expect(snapshot.connected).toBe(true)
    await runtime.perform('disconnect', '{}')
    expect(resident.stopped).toBeGreaterThan(0)
  })

  it('keeps background recovery armed while a resident task owns the carrier', async () => {
    proxy = catalogProxy()
    await remembered()
    await runtime.onBackground()
    vi.useFakeTimers()
    try {
      lastConnectOptions.onClose()
      expect(snapshot.recovering).toBe(true)
      await vi.advanceTimersByTimeAsync(0)
      expect(bridge.connect).toHaveBeenCalledTimes(1)
      await vi.waitFor(() => expect(snapshot.connected, `${snapshot.status}: ${snapshot.error}`).toBe(true))
    } finally { vi.useRealTimers() }
  })

  it('probes the carrier on resume and reconnects when a suspended network left it half-open', async () => {
    proxy = catalogProxy()
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    expect(snapshot.connected).toBe(true)
    const connects = bridge.connect.mock.calls.length
    bridge.checkHealth.mockResolvedValue(false)
    await runtime.onForeground()
    expect(bridge.checkHealth.mock.calls.length).toBeGreaterThanOrEqual(2)
    expect(bridge.connect.mock.calls.length).toBe(connects + 1)
    expect(snapshot.connected).toBe(true)
    bridge.checkHealth.mockResolvedValue(true)
    const stable = bridge.connect.mock.calls.length
    await runtime.onForeground()
    expect(bridge.connect.mock.calls.length).toBe(stable)
  })

  it('retries a dropped carrier and lands back on the same session without replaying sends', async () => {
    const drops: Array<() => void> = []
    const localBridge = {
      ...bridge,
      connect: vi.fn(async (...args: any[]) => { onFrame = args[4]; drops.push(args[5].onClose) }),
      close: vi.fn(async () => undefined),
    }
    proxy = catalogProxy({ prompt: vi.fn(async () => ({ accepted: true })) })
    const instance = await coldStart(localBridge)
    await instance.perform('login', JSON.stringify({ server: 'https://one.example', email: 'owner@example.com', password: 'test-password' }))
    await instance.perform('connect', JSON.stringify({ id: hostId }))
    await instance.perform('trustHost', JSON.stringify({ id: hostId }))
    await instance.perform('workspace', JSON.stringify({ id: 'w1' }))
    await instance.perform('session', JSON.stringify({ id: 's1' }))
    expect(snapshot.view).toBe('chat')
    const connects = localBridge.connect.mock.calls.length

    vi.useFakeTimers()
    try {
      drops[drops.length - 1]()
      expect(snapshot.connected).toBe(false)
      expect(snapshot.recovering).toBe(true)
      expect(snapshot.status).toBe('正在恢复当前对话…')
      expect(snapshot.error).toBe('')
      await vi.advanceTimersByTimeAsync(1_000)
      expect(localBridge.connect.mock.calls.length).toBe(connects + 1)
      expect(snapshot.connected).toBe(true)
      expect(snapshot.recovering).toBe(false)
      expect(snapshot.view).toBe('chat')
      expect(proxy.prompt).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
      await instance.dispose()
    }
  })

  it('retries after failed recovery attempts, falls back to relay and retains the selected session', async () => {
    proxy = catalogProxy({ sessionPrompt: vi.fn() })
    mockStats = { mode: 'Relay' }
    await remembered()
    await runtime.perform('workspace', JSON.stringify({ id: 'w1' }))
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    const dropped = lastConnectOptions.onClose
    bridge.connect.mockRejectedValueOnce(new Error('network unavailable'))
      .mockRejectedValueOnce(new Error('network unavailable'))
    vi.useFakeTimers()
    try {
      dropped()
      await vi.advanceTimersByTimeAsync(0)
      expect(bridge.connect).toHaveBeenCalledTimes(1)
      expect(snapshot.recovering).toBe(true)
      await vi.advanceTimersByTimeAsync(1000)
      expect(bridge.connect).toHaveBeenCalledTimes(2)
      expect(bridge.connect.mock.calls[1][5]).toMatchObject({ forceRelay: true, preferredTransports: ['relay'] })
      await vi.advanceTimersByTimeAsync(3000)
      expect(bridge.connect).toHaveBeenCalledTimes(3)
      expect(snapshot.connected).toBe(true)
      expect(snapshot.view).toBe('chat')
      expect(JSON.parse(snapshot.sessionKey)[1]).toBe('s1')
      expect(proxy.sessionPrompt).not.toHaveBeenCalled()
    } finally { vi.useRealTimers() }
  })

  it('stops automatic retry on a non-retryable server close but allows manual recovery', async () => {
    proxy = catalogProxy()
    await remembered()
    vi.useFakeTimers()
    try {
      lastConnectOptions.onClose({ retryable: false })
      await vi.advanceTimersByTimeAsync(20000)
      expect(bridge.connect).not.toHaveBeenCalled()
      expect(snapshot.recovering).toBe(false)
      expect(snapshot.canReconnect).toBe(true)
      expect(await runtime.perform('reconnect', '{}')).toBe(true)
      expect(snapshot.connected).toBe(true)
    } finally { vi.useRealTimers() }
  })

  it('recovers after host lookup fails before the carrier opens and stops after the retry budget', async () => {
    proxy = catalogProxy()
    await remembered()
    const original = controls.fetch!
    controls.fetch = async request => {
      if (new URL(request.url).pathname === `/api/v1/devices/${hostId}`) throw new Error('lookup unavailable')
      return original(request)
    }
    vi.useFakeTimers()
    try {
      lastConnectOptions.onClose()
      await vi.advanceTimersByTimeAsync(150000)
      expect(bridge.connect).not.toHaveBeenCalled()
      expect(snapshot.recovering).toBe(false)
      expect(snapshot.canReconnect).toBe(true)
      controls.fetch = original
      await runtime.perform('reconnect', '{}')
      expect(snapshot.connected).toBe(true)
    } finally { controls.fetch = original; vi.useRealTimers() }
  })

  it('does not let a cancelled recovery restore connection or navigation', async () => {
    proxy = catalogProxy()
    await remembered()
    const dropped = lastConnectOptions.onClose
    let finish!: () => void
    bridge.connect.mockImplementationOnce(() => new Promise<void>(resolve => { finish = resolve }))
    dropped()
    const recovering = runtime.perform('reconnect', '{}')
    await vi.waitFor(() => expect(finish).toBeTypeOf('function'))
    await runtime.perform('back', '{}')
    finish()
    await recovering
    expect(snapshot.connected).toBe(false)
    expect(snapshot.view).toBe('devices')
    expect(snapshot.recovering).toBe(false)
  })
})

describe('Harmony input-area tail and session panels', () => {
  const sessionRow = (id: string, updatedAt: number) => ({
    sessionId: id, blank: false, running: false, updatedAt,
    projections: { values: { title: `会话 ${id}` } },
  })
  const catalogProxy = (extra: Record<string, any> = {}) => ({
    workspaceList: async () => ({ items: [{ workspaceId: 'w1', title: 'Alpha', path: '/a', sessionIds: ['s1'] }], archivedSessionIds: [] }),
    sessionList: async () => [sessionRow('s1', 2000), { ...sessionRow('c1', 1500), origin: 'subagent', parentSessionId: 's1' }],
    sessionHistory: async () => ({ events: [], hasMore: false }),
    sessionModels: async () => ({ current: { provider: 'p', model: 'm' }, groups: [], routable: true }),
    messageFeedbackList: async () => [],
    ...extra,
  })
  async function openChat(): Promise<void> {
    await login(); await runtime.perform('connect', JSON.stringify({ id: hostId })); await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('workspace', JSON.stringify({ id: 'w1' }))
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    expect(snapshot.view).toBe('chat')
  }

  it('lists host skills, runs one slash line, and surfaces dispatcher errors', async () => {
    skills = [{ name: 'export', description: '导出会话', modelInvocable: false }]
    const seen: string[] = []
    commandResult = line => { seen.push(line); return line === '/export' ? { kind: 'success', text: '已导出' } : { kind: 'error', text: '不支持的命令' } }
    proxy = catalogProxy()
    await openChat()
    await runtime.perform('skills', '{}')
    expect(snapshot.skills.map((row: any) => row.id)).toEqual(['export'])
    await runtime.perform('command', JSON.stringify({ text: '/export' }))
    expect(seen).toEqual(['/export']); expect(snapshot.notice).toBe('已导出')
    await runtime.perform('command', JSON.stringify({ text: '/nope' }))
    expect(snapshot.error).toBe('不支持的命令')
    await runtime.perform('command', JSON.stringify({ text: 'export' }))
    expect(snapshot.error).toContain('/')
  })

  it('browses the workspace tree read-only, directories first, and previews text', async () => {
    fileTree = path => path === ''
      ? { path: '', entries: [{ name: 'a.txt', type: 'file', size: 5 }, { name: 'src', type: 'directory' }], truncated: false }
      : { path, entries: [{ name: 'b.txt', type: 'file', size: 1 }], truncated: false }
    proxy = catalogProxy()
    await openChat()
    await runtime.perform('files', JSON.stringify({ id: '' }))
    expect(snapshot.files.map((row: any) => row.name)).toEqual(['src', 'a.txt'])
    await runtime.perform('files', JSON.stringify({ id: 'src' }))
    expect(snapshot.filePath).toBe('src'); expect(snapshot.files.map((row: any) => row.name)).toEqual(['b.txt'])
    await runtime.perform('readFile', JSON.stringify({ id: 'src/b.txt' }))
    expect(snapshot.filePreview.text).toBe('hello'); expect(snapshot.filePreview.eof).toBe(true)
    expect(snapshot.filePreview.kind).toBe('text')

    // Paging text file with offset
    await runtime.perform('readFile', JSON.stringify({ id: 'src/b.txt', offset: 201 }))
    expect(snapshot.filePreview.offset).toBe(201)

    // Image preview
    fileStat = path => ({ absolutePath: path, version: '1', bytes: 24 })
    fileBytes = (path, _offset, _len) => ({ absolutePath: path, version: '1', offset: 0, data: testPngBytes(), bytes: 24, eof: true })
    await runtime.perform('readFile', JSON.stringify({ id: 'assets/logo.png' }))
    expect(snapshot.filePreview.kind).toBe('image')
    expect(snapshot.filePreview.mimeType).toBe('image/png')
    expect(snapshot.filePreview.data).toBe(Buffer.from(testPngBytes()).toString('base64'))

    // PDF preview
    fileStat = path => ({ absolutePath: path, version: '1', bytes: TEST_PDF_BYTES.byteLength })
    fileBytes = (path, _offset, _len) => ({ absolutePath: path, version: '1', offset: 0, data: TEST_PDF_BYTES, bytes: TEST_PDF_BYTES.byteLength, eof: true })
    await runtime.perform('readFile', JSON.stringify({ id: 'docs/guide.pdf' }))
    expect(snapshot.filePreview.kind).toBe('pdf')
    expect(snapshot.filePreview.mimeType).toBe('application/pdf')
    expect(snapshot.filePreview.data).toBe(Buffer.from(TEST_PDF_BYTES).toString('base64'))

    // Office document preview (Host officeToPdf conversion)
    fileStat = path => ({ absolutePath: path, version: '1', bytes: 5000 })
    await runtime.perform('readFile', JSON.stringify({ id: 'docs/spec.docx' }))
    expect(snapshot.filePreview.kind).toBe('office')
    expect(snapshot.filePreview.mimeType).toBe('application/pdf')
    expect(snapshot.filePreview.missingFonts).toEqual(['CustomFont.ttf'])
    expect(snapshot.filePreview.data).toBe(Buffer.from(TEST_PDF_BYTES).toString('base64'))

    // Unsupported file type
    await runtime.perform('readFile', JSON.stringify({ id: 'firmware.bin' }))
    expect(snapshot.filePreview.kind).toBe('unsupported')
    expect(snapshot.filePreview.error).toContain('暂不支持')

    await runtime.perform('closeFile', '{}')
    expect(snapshot.filePreview.path).toBe('')
  })

  it('persists the compact-history preference and re-applies it when a session opens', async () => {
    proxy = catalogProxy()
    await openChat()
    expect(snapshot.compactHistory).toBe(false)
    await runtime.perform('compactHistory', '{}')
    expect(snapshot.compactHistory).toBe(true)
    expect(bridge.configureHistory).toHaveBeenCalledWith(true)
    expect([...prefs.keys()].some(key => key.startsWith('compact.'))).toBe(true)
    bridge.configureHistory.mockClear()
    await runtime.perform('session', JSON.stringify({ id: 's1' }))
    expect(bridge.configureHistory).toHaveBeenCalledWith(true)
  })

  it('lists subagent children separately and exposes session metadata', async () => {
    proxy = catalogProxy()
    await openChat()
    expect(snapshot.children.map((row: any) => row.id)).toEqual(['c1'])
    await runtime.perform('sessionInfo', '{}')
    expect(snapshot.info.find((row: any) => row.label === '主机').value).toBe('My Host')
    expect(snapshot.info.find((row: any) => row.label === '工作区目录').value).toBe('/a')
    await runtime.perform('session', JSON.stringify({ id: 'c1' }))
    expect(snapshot.children).toEqual([])
  })
})

describe('Harmony host plugin manager and automation tasks', () => {
  // A real `schema.toJSON()` envelope: the root is a numeric uid and so is every
  // nested node, resolved through `refs`. One field per editable kind, plus a secret.
  const schema = {
    uid: 1,
    refs: {
      1: { type: 'object', dict: { limit: 2, enabled: 3, tags: 4, token: 6 } },
      2: { type: 'number', meta: { description: '上限', min: 1, max: 9, step: 1, default: 5 } },
      3: { type: 'boolean', meta: { description: '启用' } },
      4: { type: 'array', inner: 5 },
      5: { type: 'string' },
      6: { type: 'string', meta: { role: 'secret' } },
    },
  }
  const bundles = (): unknown[] => [
    {
      name: 'dsh-plugin-alpha', official: true, enabled: true, availability: 'profile', version: '1.2.0',
      meta: { title: { 'zh-CN': 'Alpha 插件' }, description: { 'zh-CN': '示例组件' } },
      rows: [{ rowId: 'r1', entryId: 'e1', moduleName: 'alpha-main', meta: { title: { 'zh-CN': '主组件' } } }],
    },
    { name: 'dsh-plugin-beta', optional: true, enabled: false, availability: 'missing', meta: { title: 'Beta' }, rows: [] },
  ]
  const tasks = (): unknown[] => [
    {
      id: 't2', sessionId: 's1', kind: 'daily', title: '每日巡检', prompt: '检查改动', status: 'active',
      scheduledAt: '2026-11-05T09:00:00.000Z', time: '09:00:00', timeZone: 'Asia/Shanghai',
      lastDelivery: { scheduledAt: '2026-11-04T09:00:00.000Z', deliveredAt: '2026-11-04T09:00:03.000Z', messageId: 'm1' },
    },
    { id: 't1', sessionId: 's2', kind: 'every', title: '心跳', prompt: '汇报', status: 'inactive', scheduledAt: '2026-11-04T12:00:00.000Z', everySeconds: 7200 },
  ]
  let mutate: any
  let toggle: any
  let remove: any
  let history: any
  const hostProxy = (extra: Record<string, any> = {}) => ({
    workspaceList: async () => ({ items: [], archivedSessionIds: [] }),
    sessionList: async () => [],
    pluginListBundles: async () => bundles(),
    pluginListPlugins: async () => [{ entryId: 'e1', patchId: 'p1', enabled: true }],
    settingsDescribe: async () => ({ writable: true, namespaces: [{ ns: 'p1', schema, value: { limit: 3, tags: ['a'] }, user: { limit: 3 }, revision: 7 }] }),
    settingsMutate: (...args: any[]) => mutate(...args),
    pluginSetEnabled: (...args: any[]) => toggle(...args),
    scheduleCatalog: async () => tasks(),
    scheduleDelete: (...args: any[]) => remove(...args),
    scheduleHistory: (...args: any[]) => history(...args),
    ...extra,
  })
  beforeEach(() => {
    mutate = vi.fn(async () => undefined)
    toggle = vi.fn(async () => ({ application: 'applied' }))
    remove = vi.fn(async () => ({ id: 't1', deleted: true }))
    history = vi.fn(async () => ({
      records: [{ scheduledAt: '2026-11-04T09:00:00.000Z', deliveredAt: '2026-11-04T09:00:03.000Z', messageId: 'm1', prompt: '检查改动' }],
    }))
  })
  async function connectHost(): Promise<void> {
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    expect(snapshot.connected).toBe(true)
  }

  it('groups the inventory into the three Android sections and switches bundles and components', async () => {
    proxy = hostProxy()
    await connectHost()
    await runtime.perform('plugins', '{}')
    expect(snapshot.settingsWritable).toBe(true)
    expect(snapshot.plugins.map((row: any) => `${row.level}/${row.id}`)).toEqual([
      'section/section:remote', 'bundle/deepseek-harness-intelligent-ui',
      'section/section:installed', 'bundle/dsh-plugin-alpha', 'component/row:e1',
      'section/section:experimental', 'bundle/dsh-plugin-beta',
    ])
    const alpha = snapshot.plugins.find((row: any) => row.id === 'dsh-plugin-alpha')
    expect(alpha.name).toBe('Alpha 插件'); expect(alpha.official).toBe(true); expect(alpha.version).toBe('1.2.0')
    const component = snapshot.plugins.find((row: any) => row.level === 'component')
    expect(component.form).toBe('e1'); expect(component.parent).toBe('Alpha 插件')
    // A bundle the Host lacks stays listed as unavailable, and its switch is off limits.
    const beta = snapshot.plugins.find((row: any) => row.id === 'dsh-plugin-beta')
    expect(beta.available).toBe(false); expect(beta.readOnly).toBe(true)
    await runtime.perform('pluginToggle', JSON.stringify({ id: 'dsh-plugin-alpha', mode: 'off' }))
    expect(toggle).toHaveBeenCalledWith('bundle', 'dsh-plugin-alpha', false)
    expect(snapshot.notice).toBe('已停用')
    await runtime.perform('pluginToggle', JSON.stringify({ id: 'row:e1', mode: 'on' }))
    expect(toggle).toHaveBeenLastCalledWith('plugin', 'e1', true)
    toggle.mockResolvedValueOnce({ application: 'restart-required' })
    await runtime.perform('pluginToggle', JSON.stringify({ id: 'dsh-plugin-alpha', mode: 'on' }))
    expect(snapshot.notice).toBe('已切换，需要重启 Host 后生效。')
  })

  it('reads a settings form at its revision, coerces edits back, and unsets only overridden keys', async () => {
    proxy = hostProxy()
    await connectHost()
    await runtime.perform('plugins', '{}')
    await runtime.perform('pluginForm', JSON.stringify({ id: 'e1' }))
    expect(snapshot.formTitle).toBe('主组件')
    expect(snapshot.form.map((row: any) => `${row.key}:${row.kind}:${row.value}`)).toEqual([
      'limit:number:3', 'enabled:boolean:false', 'tags:string-list:a', 'token:unsupported:',
    ])
    expect(snapshot.form[0].bounds).toContain('≥ 1')
    expect(snapshot.formResettable).toBe(true)
    // An unchanged boolean and a secret field never enter the write set.
    await runtime.perform('pluginSave', JSON.stringify({ text: JSON.stringify({ limit: '4', enabled: 'false', tags: 'a\nb', token: 'x' }) }))
    expect(mutate).toHaveBeenCalledWith('p1', [
      { op: 'set', path: ['limit'], value: 4 },
      { op: 'set', path: ['tags'], value: ['a', 'b'] },
    ], 7)
    expect(snapshot.notice).toBe('设置已保存')
    await runtime.perform('pluginSave', JSON.stringify({ text: JSON.stringify({ limit: '99' }) }))
    expect(snapshot.error).toBe('请输入有效数字')
    expect(mutate).toHaveBeenCalledTimes(1)
    await runtime.perform('pluginReset', '{}')
    expect(mutate).toHaveBeenLastCalledWith('p1', [{ op: 'unset', path: ['limit'] }], 7)
  })

  it('keeps a read-only Host configuration from being written and reports an old Host in localized form', async () => {
    proxy = hostProxy({ settingsDescribe: async () => ({ writable: false, namespaces: [{ ns: 'p1', schema, value: { limit: 3 }, revision: 7 }] }) })
    await connectHost()
    await runtime.perform('plugins', '{}')
    expect(snapshot.settingsWritable).toBe(false)
    await runtime.perform('pluginForm', JSON.stringify({ id: 'e1' }))
    expect(snapshot.formResettable).toBe(false)
    await runtime.perform('pluginSave', JSON.stringify({ text: JSON.stringify({ limit: '4' }) }))
    expect(snapshot.error).toBe('Host 当前配置不可写入')
    expect(mutate).not.toHaveBeenCalled()
    const error = Object.assign(new Error('method not allowed'), { code: 'METHOD_NOT_ALLOWED' })
    proxy = hostProxy({ pluginListBundles: async () => { throw error } })
    await runtime.perform('plugins', '{}')
    expect(snapshot.error).toBe('此 Host 尚不支持此功能，请更新 DSH 和 Remote 插件后重连。')
  })

  it('lists automation tasks by next run, opens their records, and deletes only on Host confirmation', async () => {
    proxy = hostProxy()
    await connectHost()
    await runtime.perform('tasks', '{}')
    expect(snapshot.tasks.map((row: any) => row.id)).toEqual(['t1', 't2'])
    expect(snapshot.tasks[0].schedule).toBe('每 2 h')
    expect(snapshot.tasks[0].status).toBe('已结束'); expect(snapshot.tasks[0].next).toBe('')
    expect(snapshot.tasks[1].schedule).toBe('每天 09:00 (Asia/Shanghai)')
    expect(snapshot.tasks[1].status).toBe('已开启')
    expect(snapshot.tasks[1].next).toMatch(/^\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}$/)
    expect(snapshot.tasks[1].last).toMatch(/^\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}$/)
    await runtime.perform('taskHistory', JSON.stringify({ id: 't2', name: 's1' }))
    expect(history).toHaveBeenCalledWith('s1', 't2')
    expect(snapshot.recordsTitle).toBe('每日巡检')
    expect(snapshot.records.map((row: any) => row.prompt)).toEqual(['检查改动'])
    await runtime.perform('taskDelete', JSON.stringify({ id: 't1', name: 's2' }))
    expect(remove).toHaveBeenCalledWith('s2', 't1')
    expect(snapshot.tasks.map((row: any) => row.id)).toEqual(['t2'])
    expect(snapshot.records).toEqual([])
    expect(snapshot.notice).toBe('任务已删除')
    remove.mockResolvedValueOnce({ id: 't2' })
    await runtime.perform('taskDelete', JSON.stringify({ id: 't2', name: 's1' }))
    expect(snapshot.error).toBe('无法删除任务')
    expect(snapshot.tasks).toHaveLength(1)
  })

  it('drops the previous host\'s plugin and task lists when the carrier goes away', async () => {
    proxy = hostProxy()
    await connectHost()
    await runtime.perform('plugins', '{}')
    await runtime.perform('tasks', '{}')
    expect(snapshot.plugins.length).toBeGreaterThan(0); expect(snapshot.tasks).toHaveLength(2)
    await runtime.perform('disconnect', '{}')
    expect(snapshot.plugins).toEqual([]); expect(snapshot.tasks).toEqual([])
    expect(snapshot.form).toEqual([]); expect(snapshot.records).toEqual([])
    expect(snapshot.settingsWritable).toBe(false)
  })
})

describe('Harmony CodeX pagination and preference persistence', () => {
  it('submits default CodeX permissions at creation and preserves them on send', async () => {
    const thread = (id: string) => ({ id, cwd: '/workspace/codex', title: 'CodeX', status: 'idle', createdAt: 1000, updatedAt: 2000, turns: [] })
    codexClient = {
      request: vi.fn(async (method: string, params: any) => {
        if (method === 'project/list') return { data: [] }
        if (method === 'thread/list') return { data: [thread('existing')] }
        if (method === 'thread/start') return { thread: thread('created') }
        if (method === 'thread/read') return { thread: thread(params.threadId) }
        if (method === 'dsh/sessionHistory') return { header: { id: 'codex:' + params.threadId }, records: [], hasMore: false }
        return { data: [] }
      }),
      subscribe: vi.fn(async () => ({ close: async () => undefined })),
    }
    proxy = { workspaceList: async () => ({ items: [] }), sessionList: async () => [] }
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('backend', JSON.stringify({ backend: 'codex' }))
    await runtime.perform('workspace', JSON.stringify({ id: snapshot.workspaces[0].id }))
    await runtime.perform('setDefaultPermission', JSON.stringify({ name: 'danger-full-access' }))
    expect(await runtime.perform('newSession', '{}')).toBe(true)
    expect(codexClient.request).toHaveBeenCalledWith('thread/start', { cwd: '/workspace/codex', permissionPreset: 'danger-full-access' })
    const scope = JSON.parse(JSON.parse(snapshot.sessionKey)[0])
    expect(scope[1]).toBe(snapshot.account); expect(scope[2]).toBe(hostId); expect(scope[3]).toBe(publicKey)
    await runtime.perform('prompt', JSON.stringify({ text: 'permission probe' }))
    expect(codexClient.request).toHaveBeenCalledWith('thread/resume', { threadId: 'created', permissionPreset: 'danger-full-access' })
  })

  it('loads CodeX history page with pagination, prepends older history on demand, and merges live frames', async () => {
    let codexSubscriber: ((frame: any) => void) | undefined
    const codexSessionId = 'codex:th-100'
    codexClient = {
      request: vi.fn(async (method: string, params: any) => {
        if (method === 'project/list') return { data: [] }
        if (method === 'thread/list') {
          return {
            data: [{ id: 'th-100', title: 'CodeX 会话', cwd: '/workspace/codex', createdAt: 1000, updatedAt: 2000 }],
          }
        }
        if (method === 'thread/read') {
          return {
            thread: {
              id: 'th-100',
              title: 'CodeX 会话',
              cwd: '/workspace/codex',
              status: 'idle',
              turns: [],
              createdAt: 1000,
              updatedAt: 2000,
            },
          }
        }
        if (method === 'dsh/sessionHistory') {
          if (params.beforeSeq === 20) {
            return {
              header: { id: 'codex:th-100' },
              hasMore: false,
              records: [
                {
                  type: 'event',
                  event: {
                    type: 'assistant/message',
                    seq: 10,
                    time: 1500,
                    data: { message: { id: 'msg-older', content: [{ type: 'text', text: '这是更早的消息' }] } },
                  },
                },
              ],
            }
          }
          return {
            header: { id: 'codex:th-100' },
            hasMore: true,
            activeTurnId: 'turn-1',
            records: [
              {
                type: 'event',
                event: {
                  type: 'user/message',
                  seq: 20,
                  time: 2000,
                  data: { message: { id: 'msg-recent', source: { kind: 'user' }, content: [{ type: 'text', text: '最近的问题' }] } },
                },
              },
            ],
          }
        }
        if (method === 'model/list') return { data: [] }
        return {}
      }),
      subscribe: vi.fn(async (_id: string, cb: any) => {
        codexSubscriber = cb
        return { close: async () => undefined }
      }),
    }
    proxy = {
      workspaceList: async () => ({ items: [] }),
      sessionList: async () => [],
    }
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('session', JSON.stringify({ id: codexSessionId }))

    expect(snapshot.view).toBe('chat')
    expect(snapshot.running).toBe(true)
    expect(snapshot.hasMore).toBe(true)
    expect(snapshot.rows).toHaveLength(1)
    expect(snapshot.rows[0].id).toBe('msg-recent')
    expect(snapshot.rows[0].text).toBe('最近的问题')

    await runtime.perform('history', '{}')
    expect(codexClient.request).toHaveBeenCalledWith('dsh/sessionHistory', expect.objectContaining({ beforeSeq: 20, maxMessages: 60 }))
    expect(snapshot.hasMore).toBe(false)
    expect(snapshot.rows).toHaveLength(2)
    expect(snapshot.rows.map((r: any) => r.id)).toEqual(['msg-older', 'msg-recent'])
    expect(snapshot.rows[0].text).toBe('这是更早的消息')

    // Live frame merges into chat items
    expect(codexSubscriber).toBeDefined()
    codexSubscriber!({
      method: 'turn/started',
      params: {
        turn: {
          id: 'turn-2',
          items: [
            { id: 'item-live', type: 'agentMessage', text: '正在回复中…', status: 'running' },
          ],
        },
      },
    })
    await new Promise(resolve => setTimeout(resolve, 60))
    expect(snapshot.rows).toHaveLength(3)
    expect(snapshot.rows[2].id).toBe('codex:th-100:turn-2:item-live')
    expect(snapshot.rows[2].text).toBe('正在回复中…')
  })

  it('persists language, theme, and typography density preferences across re-initialization', async () => {
    // Initial defaults
    expect(snapshot.languagePreference).toBe('zh-CN')
    expect(snapshot.themePreference).toBe('system')
    expect(snapshot.typographyDensity).toBe('compact')

    // Change preferences
    await runtime.perform('setLanguage', JSON.stringify({ id: 'en-US' }))
    expect(snapshot.languagePreference).toBe('en-US')

    await runtime.perform('setTheme', JSON.stringify({ id: 'dark' }))
    expect(snapshot.themePreference).toBe('dark')

    await runtime.perform('setDensity', JSON.stringify({ id: 'standard' }))
    expect(snapshot.typographyDensity).toBe('standard')

    // Dispose and re-initialize to verify preferences persisted
    await runtime.dispose()
    const restoredRuntime = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
    let restoredSnapshot: any
    restoredRuntime.setListener(raw => { restoredSnapshot = JSON.parse(raw) })
    await restoredRuntime.initialize()

    expect(restoredSnapshot.languagePreference).toBe('en-US')
    expect(restoredSnapshot.themePreference).toBe('dark')
    expect(restoredSnapshot.typographyDensity).toBe('standard')

    await restoredRuntime.dispose()
  })
})

describe('Harmony background task and approval notifications', () => {
  async function setupConnectedSession(sessionData: { sessionId: string; title: string; running: boolean }) {
    notificationsRecord.reset()
    proxy = {
      workspaceList: async () => ({ items: [{ workspaceId: 'w-1', path: '/home/project', title: 'Project', sessionIds: [sessionData.sessionId] }] }),
      sessionList: async () => [sessionData],
      sessionHistory: async () => ({ events: [], hasMore: false }),
      messageFeedbackList: async () => [],
    }
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('session', JSON.stringify({ id: sessionData.sessionId }))
  }

  it('delivers taskEnded notification when task finishes while in background, and suppresses it in foreground', async () => {
    await setupConnectedSession({ sessionId: 'session-task-1', title: 'Build Task', running: true })
    expect(snapshot.view).toBe('chat')
    expect(snapshot.running).toBe(true)

    // Put app into background
    await runtime.onBackground()

    // Task finishes via frame
    onFrame({ payload: { sessionId: 'session-task-1', type: 'session/event', event: { type: 'turn/end', data: { turn: '1', reason: 'completed' } } } })
    await new Promise(resolve => setTimeout(resolve, 60))
    expect(snapshot.running).toBe(false)

    // Verify notification was published
    expect(notificationsRecord.published).toHaveLength(1)
    expect(notificationsRecord.published[0].title).toBe('Build Task')
    expect(notificationsRecord.published[0].text).toBe('任务已结束，点此查看结果')

    // Reset and bring app to foreground
    notificationsRecord.reset()
    await runtime.onForeground()

    // Start another task then finish while in foreground
    onFrame({ payload: { sessionId: 'session-task-1', type: 'session/event', event: { type: 'turn/start', data: { turn: '2' } } } })
    await new Promise(resolve => setTimeout(resolve, 60))
    expect(snapshot.running).toBe(true)
    onFrame({ payload: { sessionId: 'session-task-1', type: 'session/event', event: { type: 'turn/end', data: { turn: '2', reason: 'completed' } } } })
    await new Promise(resolve => setTimeout(resolve, 60))
    expect(snapshot.running).toBe(false)

    // In foreground, notifications must NOT be published
    expect(notificationsRecord.published).toHaveLength(0)
  })

  it('delivers taskInput notification on approval while in background, with duplicate suppression', async () => {
    await setupConnectedSession({ sessionId: 'session-task-2', title: 'Refactor Task', running: false })
    await runtime.onBackground()

    // Approval frame arrives
    onFrame({
      rpcId: 'appr-101',
      payload: {
        sessionId: 'session-task-2',
        type: 'approval/requested',
        approvalId: 'appr-101',
        toolName: 'bash',
        reason: 'Run git diff',
      },
    })
    await new Promise(resolve => setTimeout(resolve, 60))

    expect(notificationsRecord.published).toHaveLength(1)
    expect(notificationsRecord.published[0].title).toBe('Refactor Task')
    expect(notificationsRecord.published[0].text).toBe('需要你确认，点此打开对话')

    // Redundant frame for same approval must not duplicate notification
    onFrame({
      rpcId: 'appr-101',
      payload: {
        sessionId: 'session-task-2',
        type: 'approval/requested',
        approvalId: 'appr-101',
        toolName: 'bash',
        reason: 'Run git diff',
      },
    })
    await new Promise(resolve => setTimeout(resolve, 60))
    expect(notificationsRecord.published).toHaveLength(1)
  })

  it('honours notification preference and provides notification navigation', async () => {
    await setupConnectedSession({ sessionId: 'session-task-3', title: 'Deploy Task', running: true })
    expect(snapshot.notificationsEnabled).toBe(true)

    // Disable notifications
    await runtime.perform('setNotifications', JSON.stringify({ enabled: false }))
    expect(snapshot.notificationsEnabled).toBe(false)

    await runtime.onBackground()
    onFrame({ payload: { sessionId: 'session-task-3', type: 'session/event', event: { type: 'turn/end', data: { turn: '1', reason: 'completed' } } } })
    await new Promise(resolve => setTimeout(resolve, 60))

    // Notification disabled -> no publish
    expect(notificationsRecord.published).toHaveLength(0)

    // Re-enable notifications
    await runtime.perform('setNotifications', JSON.stringify({ enabled: true }))
    expect(snapshot.notificationsEnabled).toBe(true)

    // Test notification navigation
    await runtime.perform('back', '{}')
    expect(snapshot.view).toBe('workspaces')

    await runtime.handleNotificationNavigation(hostId, 'session-task-3')
    expect(snapshot.view).toBe('chat')
    expect(snapshot.sessionKey).toContain('session-task-3')
  })
})

describe('Harmony Interactive Terminal alignment', () => {
  async function openTestSession() {
    proxy = {
      workspaceList: async () => ({ items: [{ workspaceId: 'w-term', path: '/home/project', title: 'Term Project', sessionIds: ['session-term-1'] }] }),
      sessionList: async () => [{ sessionId: 'session-term-1', title: 'Terminal Session', running: false }],
      sessionHistory: async () => ({ events: [], hasMore: false }),
      messageFeedbackList: async () => [],
    }
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('session', JSON.stringify({ id: 'session-term-1' }))
  }

  it('opens terminal, auto-creates a terminal if none exist, attaches to stream, and strips ANSI codes', async () => {
    await openTestSession()
    expect(snapshot.view).toBe('chat')
    expect(snapshot.terminals).toHaveLength(0)

    await runtime.perform('openTerminal', '{}')
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(mockTerminalCreated).toHaveLength(1)
    expect(snapshot.terminals).toHaveLength(1)
    expect(snapshot.activeTerminalId).toBe(mockTerminalCreated[0].id)
    expect(snapshot.terminalWritable).toBe(true)
    expect(snapshot.terminalScreen).toContain('hello terminal\n')
    expect(snapshot.terminalScreen).not.toContain('\x1b[32m')
  })

  it('waits for the current renderer acknowledgement before consuming more terminal output', async () => {
    await openTestSession()
    await runtime.perform('openTerminal', '{}')
    await vi.waitFor(() => expect(snapshot.terminalWritable).toBe(true))
    const scope = snapshot.sessionKey + '/' + snapshot.activeTerminalId
    runtime.setTerminalRenderer(scope, true)
    mockTerminalStream!.push({ type: 'output', sequence: 2, data: 'first-output' })
    mockTerminalStream!.push({ type: 'output', sequence: 3, data: 'second-output' })
    await vi.waitFor(() => expect(snapshot.terminalRaw).toContain('first-output'))
    const revision = snapshot.terminalRenderRevision
    runtime.acknowledgeTerminalRender('old-scope', revision)
    runtime.acknowledgeTerminalRender(scope, revision - 1)
    await Promise.resolve()
    expect(snapshot.terminalRaw).not.toContain('second-output')
    runtime.acknowledgeTerminalRender(scope, revision)
    await vi.waitFor(() => expect(snapshot.terminalRaw).toContain('second-output'))
    runtime.setTerminalRenderer(scope, false)
  })

  it('writes commands and key shortcuts to terminal', async () => {
    await openTestSession()
    await runtime.perform('openTerminal', '{}')
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(snapshot.terminalWritable).toBe(true)

    // Send shell command
    await runtime.perform('writeTerminal', JSON.stringify({ text: 'uname -a\r' }))
    expect(mockTerminalWritten).toContain('uname -a\r')

    // Send Ctrl+C interrupt
    await runtime.perform('writeTerminal', JSON.stringify({ text: '\x03' }))
    expect(mockTerminalWritten).toContain('\x03')

    // Send Tab
    await runtime.perform('writeTerminal', JSON.stringify({ text: '\t' }))
    expect(mockTerminalWritten).toContain('\t')

    // Clear terminal screen locally
    await runtime.perform('clearTerminal', '{}')
    expect(snapshot.terminalScreen).toBe('')
  })

  it('switches between multiple terminals and closes active terminal', async () => {
    await openTestSession()
    await runtime.perform('openTerminal', '{}')
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(snapshot.terminals).toHaveLength(1)

    // Create second terminal
    await runtime.perform('createTerminal', '{}')
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(mockTerminalCreated).toHaveLength(2)
    expect(snapshot.terminals).toHaveLength(2)
    expect(snapshot.activeTerminalId).toBe(mockTerminalCreated[1].id)

    // Switch back to first terminal
    const firstId = mockTerminalCreated[0].id
    await runtime.perform('selectTerminal', JSON.stringify({ id: firstId }))
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(snapshot.activeTerminalId).toBe(firstId)

    // Close first terminal
    await runtime.perform('closeTerminal', '{}')
    await new Promise(resolve => setTimeout(resolve, 30))
    expect(mockTerminalClosed).toContain(firstId)
    expect(snapshot.terminals).toHaveLength(1)
    expect(snapshot.activeTerminalId).toBe(mockTerminalCreated[1].id)
  })

  it('handles cleanTerminalText with complex ANSI escape sequences and control characters', () => {
    const input = '\x1b[1;32m[user@host]\x1b[0m \x1b]0;Title\x07echo "hello"\r\n\x1b[K\x1b[2Jresult\x08t\r'
    const cleaned = cleanTerminalText(input)
    expect(cleaned).not.toContain('\x1b[')
    expect(cleaned).not.toContain('\x1b]')
    expect(cleaned).not.toContain('\r')
    expect(cleaned).toContain('[user@host] echo "hello"\nresult\n')
  })
})

describe('Harmony Intelligent UI artifact projection and action guard', () => {
  it('projects settled ui_render tool event into UiArtifactRow', async () => {
    const tree = {
      title: 'Counter Card',
      root: 'root',
      components: [
        { id: 'root', type: 'Card', action: 'Increment' },
      ],
    }
    proxy = {
      workspaceList: async () => ({ items: [{ workspaceId: 'w-ui', path: '/home/project', title: 'UI Project', sessionIds: ['session-ui-1'] }] }),
      sessionList: async () => [{ sessionId: 'session-ui-1', title: 'UI Session', running: false }],
      sessionHistory: async () => ({
        events: [
          {
            event: {
              type: 'tool/call',
              data: {
                callId: 'ui-tool-1',
                name: 'ui_render',
                arguments: JSON.stringify(tree),
                turn: '1',
              },
            },
            seq: 10,
          },
          {
            event: {
              type: 'tool/result',
              data: {
                callId: 'ui-tool-1',
                name: 'ui_render',
                message: { source: { callId: 'ui-tool-1' } },
                meta: { ok: true },
                turn: '1',
              },
            },
            seq: 11,
          },
        ],
        hasMore: false,
      }),
      messageFeedbackList: async () => [],
      sessionPrompt: vi.fn(async () => undefined),
    }
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('session', JSON.stringify({ id: 'session-ui-1' }))

    const toolRow = snapshot.rows.find((r: any) => r.id === 'ui-tool-1')
    expect(toolRow).toBeDefined()
    expect(toolRow.uiArtifacts).toHaveLength(1)
    expect(toolRow.uiArtifacts[0].title).toBe('Counter Card')
    expect(toolRow.uiArtifacts[0].version).toBe(1)
    expect(toolRow.uiArtifacts[0].actionText).toBe('Increment')

    expect(await runtime.perform('uiAction', JSON.stringify({ text: 'Increment' }))).toBe(false)
    expect(await runtime.perform('uiAction', JSON.stringify({ text: 'Increment', id: toolRow.uiArtifacts[0].uiId, name: '0', mode: snapshot.sessionKey }))).toBe(false)
    expect(proxy.sessionPrompt).not.toHaveBeenCalled()
    // Submit uiAction
    await runtime.perform('uiAction', JSON.stringify({ text: 'Increment', id: toolRow.uiArtifacts[0].uiId, name: '1', mode: snapshot.sessionKey }))
    expect(proxy.sessionPrompt).toHaveBeenCalledWith('session-ui-1', 'Increment', undefined, [])
  })

  it('projects ui_patch updating artifact version and title', async () => {
    const tree = {
      title: 'Poll v1',
      root: 'root',
      components: [{ id: 'root', type: 'Card', action: 'Vote' }],
    }
    const patchedTree = {
      uiId: 'ui-tool-1',
      version: 2,
      title: 'Poll v2',
      root: 'root',
      components: [{ id: 'root', type: 'Card', action: 'Vote Again' }],
    }
    proxy = {
      workspaceList: async () => ({ items: [{ workspaceId: 'w-ui', path: '/home/project', title: 'UI Project', sessionIds: ['session-ui-2'] }] }),
      sessionList: async () => [{ sessionId: 'session-ui-2', title: 'UI Session 2', running: false }],
      sessionHistory: async () => ({
        events: [
          {
            event: {
              type: 'tool/call',
              data: { callId: 'ui-tool-1', name: 'ui_render', arguments: JSON.stringify(tree), turn: '1' },
            },
            seq: 10,
          },
          {
            event: {
              type: 'tool/result',
              data: { callId: 'ui-tool-1', name: 'ui_render', message: { source: { callId: 'ui-tool-1' } }, meta: { ok: true }, turn: '1' },
            },
            seq: 11,
          },
          {
            event: {
              type: 'tool/call',
              data: { callId: 'ui-tool-2', name: 'ui_patch', arguments: JSON.stringify({ uiId: 'ui-tool-1', baseVersion: 1 }), turn: '2' },
            },
            seq: 20,
          },
          {
            event: {
              type: 'tool/result',
              data: { callId: 'ui-tool-2', name: 'ui_patch', message: { source: { callId: 'ui-tool-2' } }, meta: { ok: true, ui: patchedTree }, turn: '2' },
            },
            seq: 21,
          },
        ],
        hasMore: false,
      }),
      messageFeedbackList: async () => [],
    }
    await login()
    await runtime.perform('connect', JSON.stringify({ id: hostId }))
    await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
    await runtime.perform('session', JSON.stringify({ id: 'session-ui-2' }))

    const toolRow1 = snapshot.rows.find((r: any) => r.id === 'ui-tool-1')
    expect(toolRow1).toBeDefined()
    expect(toolRow1.uiArtifacts[0].version).toBe(2)
    expect(toolRow1.uiArtifacts[0].title).toBe('Poll v2')

    const toolRow2 = snapshot.rows.find((r: any) => r.id === 'ui-tool-2')
    expect(toolRow2).toBeDefined()
    expect(toolRow2.updatedArtifacts).toBeDefined()
    expect(toolRow2.updatedArtifacts[0]).toContain('Poll v2 已更新至版本 v2')
  })

  describe('Harmony Bot Mode and multi-agent collaboration alignment', () => {
    it('parses multi-agent bot replies from finished tool results and attaches to timeline rows', async () => {
      const rawReplies = JSON.stringify({
        replies: [
          { botId: 'bot-arch', name: '架构师 Bot', color: '#E65100', text: '我们先分析系统架构。', kind: 'agent' },
          { botId: 'bot-dev', name: '开发 Bot', color: '#10A37F', text: '单元测试已全部通过。', kind: 'agent' },
        ],
        passed: true,
      })
      proxy = {
        workspaceList: async () => ({ items: [{ workspaceId: 'w-bot', path: '/home/project', title: 'Bot Project', sessionIds: ['session-bot-1'] }] }),
        sessionList: async () => [{ sessionId: 'session-bot-1', title: 'Bot Session', running: false }],
        sessionHistory: async () => ({
          events: [
            {
              event: {
                type: 'tool/call',
                data: { callId: 'call-relay-1', name: 'group_relay', arguments: JSON.stringify({ topic: 'test' }), turn: '1' },
              },
              seq: 1,
            },
            {
              event: {
                type: 'tool/result',
                data: {
                  callId: 'call-relay-1',
                  name: 'group_relay',
                  message: { source: { callId: 'call-relay-1' }, content: [{ type: 'text', text: rawReplies }] },
                  meta: { ok: true },
                  turn: '1',
                },
              },
              seq: 2,
            },
          ],
          hasMore: false,
        }),
        messageFeedbackList: async () => [],
      }
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
      await runtime.perform('session', JSON.stringify({ id: 'session-bot-1' }))

      const toolRow = snapshot.rows.find((r: any) => r.id === 'call-relay-1')
      expect(toolRow).toBeDefined()
      expect(toolRow.title).toBe('群组协作 · 已完成')
      expect(toolRow.botReplies).toBeDefined()
      expect(toolRow.botReplies).toHaveLength(2)
      expect(toolRow.botReplies[0].name).toBe('架构师 Bot')
      expect(toolRow.botReplies[0].color).toBe('#E65100')
      expect(toolRow.botReplies[0].text).toBe('我们先分析系统架构。')
      expect(toolRow.botReplies[1].name).toBe('开发 Bot')
      expect(toolRow.botReplies[1].text).toBe('单元测试已全部通过。')
    })

    it('loads Host Bot team roster, maps main bot status, and resolves bot session', async () => {
      mockBotClient = {
        state: vi.fn(async () => ({
          bots: [
            { id: 'b-main', sessionId: 'sess-b-main', name: '主脑智能体', role: '总控', model: 'deepseek-chat', color: '#4B78E6', main: true },
            { id: 'b-sub', sessionId: 'sess-b-sub', name: '代码助手', role: '研发', model: 'codex', color: '#10A37F', main: false },
          ],
          rooms: [],
        })),
        resolveSession: vi.fn(async (id: string) => {
          if (id === 'b-main') return { session: { sessionId: 'sess-b-main', backend: 'harness' } }
          throw new Error('not found')
        }),
      }
      proxy = {
        workspaceList: async () => ({ items: [{ workspaceId: 'w-1', path: '/home', title: 'Work', sessionIds: ['sess-b-main'] }] }),
        sessionList: async () => [{ sessionId: 'sess-b-main', title: '主脑会话', running: false }],
        sessionHistory: async () => ({ events: [], hasMore: false }),
        messageFeedbackList: async () => [],
      }
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))

      await runtime.perform('bots', '{}')
      expect(mockBotClient.state).toHaveBeenCalled()
      expect(snapshot.bots).toHaveLength(2)
      expect(snapshot.bots[0].name).toBe('主脑智能体')
      expect(snapshot.bots[0].main).toBe(true)
      expect(snapshot.bots[1].name).toBe('代码助手')
      expect(snapshot.bots[1].main).toBe(false)

      await runtime.perform('botSelect', JSON.stringify({ id: 'b-main' }))
      expect(mockBotClient.resolveSession).toHaveBeenCalledWith('b-main')
      expect(snapshot.view).toBe('chat')
    })
  })

  describe('Harmony Host Network and connection diagnostics', () => {
    it('formats relay network details, control server, and security encryption', async () => {
      mockStats = { connected: true, mode: 'Relay', bytesSent: 125000, bytesReceived: 450000 }
      mockNetworkDetails = {
        controlChannelUrl: 'wss://dsh.r2049.cn/carrier/channel',
        connectedAt: 1730700000000,
        webRtc: undefined,
      }
      proxy = {
        workspaceList: async () => ({ items: [{ workspaceId: 'w-net', path: '/home/net', title: 'Net Work', sessionIds: ['s-net-1'] }] }),
        sessionList: async () => [{ sessionId: 's-net-1', title: 'Net Session', running: false }],
        sessionHistory: async () => ({ events: [], hasMore: false }),
        messageFeedbackList: async () => [],
      }
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))

      await runtime.perform('networkDetails', '{}')
      expect(snapshot.networkSections).toHaveLength(2)

      const secureSec = snapshot.networkSections.find((s: any) => s.title === '安全连接')
      expect(secureSec).toBeDefined()
      expect(secureSec.rows.find((r: any) => r.label === '连接方式').value).toBe('服务器转发')
      expect(secureSec.rows.find((r: any) => r.label === '控制信令服务器').value).toBe('dsh.r2049.cn')

      const netSec = snapshot.networkSections.find((s: any) => s.title === '网络详情')
      expect(netSec).toBeDefined()
      expect(netSec.rows.find((r: any) => r.label === '手机端点').value).toBe('服务器转发未公开')
      expect(netSec.rows.find((r: any) => r.label === '本次流量').value).toContain('KB')
    })

    it('formats WebRTC P2P network diagnostics with RTT, bitrate, and candidate path', async () => {
      mockStats = { connected: true, mode: 'P2P', bytesSent: 2048000, bytesReceived: 5120000 }
      mockNetworkDetails = {
        controlChannelUrl: 'wss://dsh.r2049.cn/carrier',
        connectedAt: 1730700000000,
        webRtc: {
          connectionState: 'connected',
          iceConnectionState: 'connected',
          localAddress: '192.168.3.23:54321',
          remoteAddress: '192.168.3.24:43210',
          protocol: 'udp',
          localCandidateType: 'host',
          localAddressScope: 'lan',
          remoteCandidateType: 'host',
          remoteAddressScope: 'lan',
          currentRoundTripTimeMs: 18.5,
          availableOutgoingBitrate: 15400000,
          bytesSent: 2048000,
          bytesReceived: 5120000,
        },
      }
      proxy = {
        workspaceList: async () => ({ items: [{ workspaceId: 'w-net2', path: '/home/net', title: 'Net Work', sessionIds: ['s-net-2'] }] }),
        sessionList: async () => [{ sessionId: 's-net-2', title: 'Net Session 2', running: false }],
        sessionHistory: async () => ({ events: [], hasMore: false }),
        messageFeedbackList: async () => [],
      }
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
      await runtime.perform('session', JSON.stringify({ id: 's-net-2' }))

      await runtime.perform('sessionInfo', '{}')
      expect(snapshot.info.length).toBeGreaterThan(0)
      expect(snapshot.networkSections).toHaveLength(2)

      const secureSec = snapshot.networkSections.find((s: any) => s.title === '安全连接')
      expect(secureSec.rows.find((r: any) => r.label === '连接方式').value).toBe('点对点直连')

      const netSec = snapshot.networkSections.find((s: any) => s.title === '网络详情')
      expect(netSec.rows.find((r: any) => r.label === '往返延迟 (RTT)').value).toBe('19 ms')
      expect(netSec.rows.find((r: any) => r.label === '可用上行带宽').value).toBe('15.4 Mbps')
      expect(netSec.rows.find((r: any) => r.label === '网络协议').value).toBe('UDP')
      expect(netSec.rows.find((r: any) => r.label === '手机端点').value).toBe('192.168.3.23:54321')
      expect(netSec.rows.find((r: any) => r.label === '电脑端点').value).toBe('192.168.3.24:43210')
      expect(netSec.rows.find((r: any) => r.label === '候选路径').value).toBe('host · lan → host · lan')
    })
  })

  describe('Harmony Browser OAuth and App Linking deep link alignment', () => {
    it('discovers OAuth provider, builds redirect URL with return_to and triggers browser openLink', async () => {
      await runtime.perform('startOAuth', JSON.stringify({ server: 'https://one.example', provider: 'github' }))
      expect(mockOpenedLinks).toHaveLength(1)
      const opened = mockOpenedLinks[0]
      expect(opened).toContain('https://one.example/api/v1/auth/oauth/github/start')
      expect(opened).toContain('return_to=dshremote%3A%2F%2Foauth')
      expect(snapshot.notice).toContain('GitHub')
    })

    it('rejects startOAuth when provider is not configured on server', async () => {
      await runtime.perform('startOAuth', JSON.stringify({ server: 'https://one.example', provider: 'weibo' }))
      expect(snapshot.error).toContain('服务器未启用')
    })

    it('completes account registration from valid dshremote://oauth deep link and transitions to devices view', async () => {
      await runtime.perform('startOAuth', JSON.stringify({ server: 'https://one.example', provider: 'github' }))
      const ok = await runtime.handleDeepLink('dshremote://oauth?token=tok_github_valid_long_token_123456')
      expect(ok).toBe(true)
      expect(snapshot.view).toBe('devices')
      expect(snapshot.account).toBe('oauth-owner@example.com')
      expect(snapshot.devices).toHaveLength(1)
    })

    it('handles OAuth error query parameter and informs the user without registering', async () => {
      await runtime.perform('startOAuth', JSON.stringify({ server: 'https://one.example', provider: 'zhihu' }))
      const ok = await runtime.handleDeepLink('dshremote://oauth?error=access_denied')
      expect(ok).toBe(false)
      expect(snapshot.view).toBe('login')
      expect(snapshot.error).toBe('未完成授权，请再试一次。')
    })

    it('rejects invalid or too short OAuth token', async () => {
      const ok = await runtime.handleDeepLink('dshremote://oauth?token=short')
      expect(ok).toBe(false)
      expect(snapshot.view).toBe('login')
      expect(snapshot.error).toBe('登录信息已失效，请重新登录。')
    })

    it('deduplicates identical deep link invocation within the same session', async () => {
      const first = await runtime.handleDeepLink('dshremote://oauth?token=tok_dedup_valid_token_12345678')
      expect(first).toBe(true)
      const duplicate = await runtime.handleDeepLink('dshremote://oauth?token=tok_dedup_valid_token_12345678')
      expect(duplicate).toBe(false)
    })

    it('ignores unrelated deep link schemes or hosts safely', async () => {
      const ok = await runtime.handleDeepLink('https://example.com/other')
      expect(ok).toBe(false)
      const ok2 = await runtime.handleDeepLink('dshremote://unknown')
      expect(ok2).toBe(false)
    })
  })

  describe('Harmony LAN / P2P transport preference and probing alignment', () => {
    it('defaults to auto preference with LAN and P2P direct probe order', async () => {
      expect(snapshot.transportPreference).toBe('auto')
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
      expect(lastConnectOptions).toBeDefined()
      expect(lastConnectOptions.forceRelay).toBe(false)
      expect(lastConnectOptions.preferredTransports).toEqual(['lan', 'p2p', 'turn', 'relay'])
      expect(typeof lastConnectOptions.fetchIceServers).toBe('function')
    })

    it('sets relay transport preference and restricts probe order to relay only', async () => {
      await runtime.perform('setTransportPreference', JSON.stringify({ mode: 'relay' }))
      expect(snapshot.transportPreference).toBe('relay')
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
      expect(lastConnectOptions.forceRelay).toBe(true)
      expect(lastConnectOptions.preferredTransports).toEqual(['relay'])
    })

    it('sets turn transport preference and restricts probe order to turn and relay', async () => {
      await runtime.perform('setTransportPreference', JSON.stringify({ mode: 'turn' }))
      expect(snapshot.transportPreference).toBe('turn')
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
      expect(lastConnectOptions.forceRelay).toBe(false)
      expect(lastConnectOptions.preferredTransports).toEqual(['turn', 'relay'])
    })

    it('persists transport preference across runtime re-initialization', async () => {
      await runtime.perform('setTransportPreference', JSON.stringify({ mode: 'turn' }))
      await runtime.dispose()
      const freshRuntime = new HarmonyRuntime(bridge as unknown as AndroidRemoteConnection)
      let freshSnapshot: any
      freshRuntime.setListener(raw => { freshSnapshot = JSON.parse(raw) })
      await freshRuntime.initialize()
      expect(freshSnapshot.transportPreference).toBe('turn')
      await freshRuntime.dispose()
    })

    it('surfaces selected transport preference in network details diagnostics', async () => {
      await runtime.perform('setTransportPreference', JSON.stringify({ mode: 'auto' }))
      await login()
      await runtime.perform('connect', JSON.stringify({ id: hostId }))
      await runtime.perform('trustHost', JSON.stringify({ id: hostId }))
      await runtime.perform('networkDetails', '{}')
      const sec = snapshot.networkSections.find((s: any) => s.title === '安全连接')
      expect(sec).toBeDefined()
      expect(sec.rows.find((r: any) => r.label === '传输策略').value).toContain('自动优选')
      expect(sec.rows.find((r: any) => r.label === '探测顺序').value).toBe('LAN → P2P → TURN → Relay')
    })
  })
})
