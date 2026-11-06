import { imageInputLimits, validateImageInput } from './image-input'
import { isTextFile, isValidUtf8Text, MAX_SINGLE_FILE_BYTES, MAX_TOTAL_FILES_BYTES } from '../../android/src/screens/chat-files'
import { sha256 } from '@noble/hashes/sha256'
import { generateKeyPair, identityFingerprint, fromBase64Url } from '@dsh-remote/crypto'
import { deviceTokenPairSchema, type DeviceTokenPair } from '@dsh-remote/protocol'
import { AndroidRemoteConnection } from '../../android/src/services/connection'
import { RemoteServerApi } from '../../android/src/services/api'
import { normalizeServerUrl } from '../../android/src/lib/server-url'
import { resolveStartupAutoConnect } from '../../android/src/lib/auto-connect'
import { ForegroundConnectionRecovery } from '../../android/src/services/connection-recovery'
import { startResidentTask, stopResidentTask, residentTaskActive, residentTaskError, observeResidentTask, openAppPowerManagementPage } from './background'
import { TaskNotifications, activeTask, type ObservedTask } from './notification-state'
import { DownloadTask } from './download-task'
import { latestRelease, HARMONY_VERSION, RELEASE_URL } from './releases'
import { heartbeatMessageBody } from '../../android/src/ui/heartbeat-message'
import { HarmonyBrowseMemory, type ReadingPosition } from './browse-memory'
import { translateNative } from './localization'
import { isCodexPermissionPreset, withCodexPermission, codexPermissionPreset } from '../../android/src/services/codex'
import { uploadFile } from './file-transfer'
import { copyText, shareText, setStatusBarVisible, clearBrowsePreferences } from './platform.js'
import { checkedBotView } from '../../android/src/services/bot-view'
import { validateViewAnswer } from '../../android/src/vendor/ds-bot/views.js'
import { SessionActivity } from './session-activity'
import { attachRtcBridge, receiveRtcBridge } from './rtc-bridge'
import { createChatImageLoader, chatImageAttachmentReference } from '../../android/src/services/chat-image-loader'
import type { ChatImage } from '../../android/src/types'
import { botMessageRequest, objects as botObjects, object as botObject, BOT_OPERATIONS, type BotOperation, type BotState } from '../../android/src/services/bot-catalog'
import { loadHermesCatalog } from '../../android/src/services/hermes'
import { createHermesSession, createHermesWorkspace, createPiWorkspace, createClaudeWorkspace, createAntigravityWorkspace, createOpencodeWorkspace } from '../../android/src/services/cursor'
import { createCodexWorkspace } from '../../android/src/services/codex'
import type { ScheduleRecord, ScheduleCreateRequest, ScheduleTimingChange } from '@dsh-remote/client-core'
import { applyLanguagePreference, isLanguagePreference, strings, type LanguagePreference } from '../../android/src/locales/i18n'
import { isThemePreference, isTypographyDensity, type ThemePreference, type TypographyDensity } from '../../android/src/ui/theme'
import { foldHistory, applyMuxFrame, sessionRunningForMuxFrame } from '../../android/src/state/event-reducer'
import { inboxQueuedItems, oldestSeq, prependHistory } from '../../android/src/state/message-helpers'
import { withActiveCodexTurn } from '../../android/src/state/session-state'
import { sessionPermissions } from '../../android/src/services/session-permissions'
import { isSubagentSession } from '../../android/src/lib/session-kind'
import { joinInventory, schemaFields, type AdaptedPluginInfo, type PluginBundleView, type PluginCategory, type SchemaField } from '../../android/src/services/plugin-catalog'
import { resolveSessionDisplayTitle } from '../../android/src/screens/session-title'
import { sessionToolsError } from '../../android/src/screens/session-tools-error'
import { classifyWorkspaceFile, loadWorkspacePreview } from '../../android/src/services/workspace-file-preview'
import { projectUiArtifacts, type UiArtifact } from '../../android/src/state/ui-artifacts'
import { botMentionTarget, linkBotMentions } from '../../android/src/screens/bot/mentions'
import { parseBotReplies } from '../../android/src/screens/bot/replies'
import { text } from '../../android/src/services/bot-catalog'
import { TerminalAttachment } from '../../android/src/services/terminal-attachment'
import type { TerminalInfo } from '../../android/src/services/session-tools'
import { createNativeRpcId } from '../../android/src/services/rpc-id'
import {
  loadCodexCatalog, codexSession, codexThreadId, codexItemsToChat, loadCodexModels,
  codexModelSelectionFromSession, readCodexSession, readCodexHistoryPage, mergeCodexLive,
} from '../../android/src/services/codex'
import { loadPiCatalog } from '../../android/src/services/pi'
import { loadClaudeCatalog } from '../../android/src/services/claude'
import { loadOpencodeCatalog } from '../../android/src/services/opencode'
import { loadAntigravityCatalog } from '../../android/src/services/antigravity'
import { applyCursorFrame, foldAcpHistory, mergeAcpHistoryAndLive, createCursorWorkspace, createCursorSession, createPiSession, createClaudeSession, createAntigravitySession, createOpencodeSession } from '../../android/src/services/cursor'
import { loadAcpModels, selectAcpModel } from '../../android/src/services/acp-models'
import { createCodexTimelineState, reduceCodexTimelineFrame, type CodexTimelineState,
  type HarnessSettingsDescribe, type HarnessSettingsPathOp, type ScheduleCatalogEntry, type ScheduleDeliveryRecord } from '@dsh-remote/client-core'
import type { ChatItem, ConnectionPhase, DeviceIdentity, RemoteDevice, RemoteSession, WorkspaceView, SessionModels, MuxStreamFrame, AskUserQuestionItem, AskUserQuestionAnswer } from '../../android/src/types'
import { vaultRead, vaultWrite, vaultDelete, attachPreferences, systemLocale } from './platform.js'
import { readPreference as prefRead, writePreference as prefWrite } from './private-preferences'
import { publishTaskNotification, requestNotificationPermission, updateActivityNotification } from './notifications'

interface Credentials extends DeviceTokenPair { account: string }
interface ReadingInput { id?: string; key?: string; offset?: number; atBottom?: boolean }
interface PromptAttachment { data: string; mediaType: string; name?: string }
interface Input { images?: PromptAttachment[]; answers?: AskUserQuestionAnswer['answers']; server?: string; email?: string; password?: string; id?: string; text?: string; decision?: string; provider?: string; model?: string; effort?: string; path?: string; image?: string; mediaType?: string; name?: string; backend?: string; mode?: string; rating?: string; enabled?: boolean; offset?: number }
interface PresetRow { id: string; name: string; description: string; current: boolean; broken: boolean }
interface TerminalRow { id: string; title: string; shell: string; state: string }
interface UiArtifactRow {
  uiId: string; kind: string; title: string; version: number;
  turn: string; updatedTurn: string; summary: string; html: string; payload: string; actionText: string;
}
interface QueueRow { id: string; preview: string; host: boolean }
interface PromptRow { id: string; title: string; text: string; builtIn: boolean }
interface SkillRow { id: string; name: string; description: string }
interface FileRow { id: string; name: string; kind: string; size: string }
interface FilePreview {
  path: string; name: string; kind: string; text: string; lines: number; eof: boolean;
  data: string; mimeType: string; missingFonts: string[]; error: string; offset: number;
}
interface InfoRow { label: string; value: string }
/**
 * One plugin-page line: a section header, a bundle, or one of its components.
 * The flat shape keeps ArkUI's list keys stable where Android stacks cards.
 */
interface PluginRow {
  id: string; level: string; parent: string; name: string; description: string; category: string
  enabled: boolean; available: boolean; readOnly: boolean; official: boolean; version: string
  error: string; feature: string; upgrade: string; form: string
}
interface FormRow { key: string; kind: string; value: string; description: string; bounds: string; secret: boolean }
interface TaskRow {
  id: string; session: string; title: string; prompt: string; status: string; active: boolean
  schedule: string; kind: string; next: string; last: string
}
interface RecordRow { id: string; delivered: string; scheduled: string; prompt: string }
interface BotReplyRow { name: string; color: string; text: string; kind: string }
interface BotEntryRow { id: string; name: string; role: string; model: string; color: string; main: boolean }
interface NetworkRow { label: string; value: string; mono?: boolean }
interface NetworkSection { title: string; rows: NetworkRow[] }
interface CustomPrompt { id: string; title: string; text: string }
interface Row {
  heartbeatRaw?: string
  id: string; kind: string; title: string; text: string; detail: string; pending: boolean; images: string[]
  questions?: AskUserQuestionItem[]
  uiArtifacts?: UiArtifactRow[]
  updatedArtifacts?: string[]
  botReplies?: BotReplyRow[]
  /** Trajectory and message-action surface; mirrors the Android row metadata. */
  category: string; turn: string; clock: string; preview: string; attachments: number
  actionable: boolean; feedback: string; tokens: string; usageDetail: string
}
interface BackendTab { id: string; name: string; count: number }
interface OverviewRow {
  id: string; kind: string; name: string; description: string; meta: string
  favorite: boolean; expanded: boolean; remaining: number; selected: boolean; hidden: boolean; target: string
}
interface CatalogRow { id: string; name: string; description: string; favorite?: boolean; backend?: string; count?: number; archived?: boolean }
const DEFAULT_SERVER = 'https://dsh.r2049.cn'
const SETTINGS_KEY = 'dsh.harmony.settings'
const IDENTITY_KEY = 'dsh.harmony.identity'
const SESSION_PAGE_SIZE = 3
const BUILT_IN_PROMPT_IDS = ['builtin-check-changes', 'builtin-commit', 'builtin-view-screenshot']
const RECENT_LIMIT = 5
const PREF_KEYS = {
  languagePreference: 'dshremote.language-preference.v1',
  themePreference: 'dshremote.theme-preference.v1',
  typographyDensity: 'dshremote.typography-density.v1',
  notifications: 'dshremote.notifications-enabled.v1',
  transportPreference: 'dshremote.transport-preference.v1',
} as const

/** A string-only boundary keeps dynamic shared TS out of ArkUI's static types. */
export function cleanTerminalText(text: string): string {
  return text
    .replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, '')
    .replace(/\x1b\].*?(?:\x07|\x1b\\)/g, '')
    .replace(/\x1b[PX^_].*?\x1b\\/g, '')
    .replace(/\x1b[@-Z\\-_]/g, '')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/[^\n]\x08/g, '')
}

function terminalLabel(item: TerminalInfo): string {
  const shell = item.shell?.name
  const folder = folderName(item.cwd)
  if (typeof shell === 'string' && shell.length > 0 && folder.length > 0 && item.title.includes(folder)) return shell
  return item.title || shell || '终端'
}

function folderName(cwd: unknown): string {
  if (typeof cwd !== 'string') return ''
  const trimmed = cwd.replace(/[\\/]+$/u, '')
  return trimmed.slice(Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\')) + 1)
}

function artifactToRow(ui: UiArtifact): UiArtifactRow {
  let summary = ''
  let actionText = ''
  let html = ''
  if (ui.kind === 'widget') {
    html = typeof ui.definition.html === 'string' ? ui.definition.html : ''
    summary = html.length > 0 ? '沙箱 HTML 微应用组件' : '微应用组件'
  } else {
    const components = Array.isArray(ui.definition.components) ? ui.definition.components : []
    const count = components.length
    summary = count > 0 ? `声明式组件树 (${count} 个节点)` : '声明式 UI 卡片'
    for (const comp of components) {
      if (typeof comp === 'object' && comp !== null) {
        const c = comp as Record<string, unknown>
        if (typeof c.action === 'string' && c.action.length > 0) {
          actionText = c.action
          break
        }
        if (typeof c.prompt === 'string' && c.prompt.length > 0) {
          actionText = c.prompt
          break
        }
      }
    }
  }
  return {
    uiId: ui.uiId,
    kind: ui.kind,
    title: ui.title || (ui.kind === 'widget' ? '微应用卡片' : '交互式 UI 卡片'),
    version: ui.version,
    turn: ui.turn ?? '',
    updatedTurn: ui.updatedTurn ?? '',
    summary,
    html,
    payload: JSON.stringify({ ...ui, policy: { ...ui.policy, allowNetwork: false, cdn: [], openLinkOrigins: [] } }),
    actionText,
  }
}

export class HarmonyRuntime {
  private taskNotifications = new TaskNotifications()
  private observedMessages = new Map<string, ChatItem[]>()
  private notificationTimer?: ReturnType<typeof setTimeout>
  private download = new DownloadTask()
  private downloadBusy = false
  private downloadBytes = 0
  private downloadRevision = 0
  private updateVersion = ''
  private listener: (snapshot: string) => void = () => undefined
  private connection = new AndroidRemoteConnection()
  private server = DEFAULT_SERVER
  private account = ''
  private identity?: DeviceIdentity
  private credentials?: Credentials
  private devices: RemoteDevice[] = []
  private host?: RemoteDevice
  private candidate?: RemoteDevice
  private workspaces: WorkspaceView[] = []
  private sessions: RemoteSession[] = []
  private workspace?: WorkspaceView
  private session?: RemoteSession
  private stagedFiles: Array<{ id: string; scope: string; name: string; path: string }> = []
  private stagedData = new Map<string,string>()
  private hostModes: Record<string,'agent'|'bot'> = {}
  private imageCache = new Map<string, string>()
  private imageAbort = new AbortController()
  private botState?: BotState
  private botTarget = ''
  private botExtras: Array<{ id: string; title: string; text: string; state: string }> = []
  private botHistory: Array<{ id: string; title: string; text: string; state: string; view: string }> = []
  private botCursor: unknown
  private botView = ''
  private botReport: Array<{ id: string; title: string; text: string; state: string }> = []
  private botModelOptions: Array<{ id: string; name: string }> = []
  private botEffortOptions: Array<{ id: string; name: string }> = []
  private botTimer?: ReturnType<typeof setTimeout>
  private botPoll?: AbortController
  private terminalRaw = ''
  private terminalChunk = ''
  private terminalReset = true
  private terminalRenderRevision = 0
  private terminalRendererScope = ''
  private terminalRenderPending?: { scope: string; revision: number; resolve: () => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }
  private messages: ChatItem[] = []
  private codexState?: CodexTimelineState
  private stream?: { close(): Promise<void> }
  private generation = 0
  private cancellation = 0
  private selection = 0
  private status = '未连接'
  private view = 'login'
  private error = ''
  private notice = ''
  private busy = false
  private initialized = false
  private refreshing?: Promise<void>
  private pendingApprovals = new Set<string>()
  private codexSelections = new Map<string, SessionModels['current']>()
  private connected = false
  private running = false
  private hasMore = false
  private beforeSeq?: number
  private defaultPermission = 'default'
  private statusBarVisible = true
  private notificationsEnabled = true
  private transportPreference: 'auto' | 'turn' | 'relay' = 'auto'
  private pendingNotificationSession?: { hostId: string; sessionId: string }
  private notifiedInputs = new Set<string>()
  private models?: SessionModels
  private modelWarning = ''
  private qr?: { qrId: string; scanUrl: string; expiresAt: number }
  private qrTimer?: ReturnType<typeof setTimeout>
  private emitTimer?: ReturnType<typeof setTimeout>
  private pinned: string[] = []
  private registeredWorkspaces: WorkspaceView[] = []
  private activity = new SessionActivity(() => this.schedulePublish())
  private projectionSeq = new Map<string, number>()
  private scheduleEntries: ScheduleCatalogEntry[] = []
  private archived: string[] = []
  private backend = 'harness'
  private groupBy: 'workspace' | 'list' = 'workspace'
  private orderBy: 'manual' | 'updated' = 'updated'
  private archiveFilter: 'hidden' | 'all' | 'only' = 'hidden'
  private favorites: string[] = []
  private recents: string[] = []
  private collapsed: string[] = []
  private visibleCounts: Record<string, number> = {}
  private feedbackByMessage = new Map<string, 'positive' | 'negative'>()
  private modes: PresetRow[] = []
  private permissions: PresetRow[] = []
  private prompts: CustomPrompt[] = []
  private removedPrompts: string[] = []
  private drafts: Record<string, string> = {}
  private draftRevision = 0
  private sharedText = ''
  private draftTimer?: ReturnType<typeof setTimeout>
  private legacyDraftOwner = ''
  private autoConnectHost = true
  private failedSends: Array<{ id: string; scope: string; text: string; image?: string; mediaType?: string; images?: PromptAttachment[]; error: string; state: string }> = []
  private browse = new HarmonyBrowseMemory()
  private resumePending = true
  private panelWarning = ''
  // Input-area tail and the two session panels mirror Android's pickers: the
  // skill catalog feeds the slash panel, the workspace file scope feeds the
  // read-only tree, and child sessions / metadata feed the title-bar panels.
  private skills: SkillRow[] = []
  private filePath = ''
  private files: FileRow[] = []
  private filePreview?: FilePreview
  private compactHistory = false
  private info: InfoRow[] = []
  private languagePreference: LanguagePreference = 'zh-CN'
  private themePreference: ThemePreference = 'system'
  private typographyDensity: TypographyDensity = 'compact'
  private pluginViews: PluginBundleView[] = []
  private pluginRows: PluginRow[] = []
  private settingsWritable = false
  private formEntry = ''
  private formNs = ''
  private formRevision = 0
  private formTitle = ''
  private formFields: SchemaField[] = []
  private formOverridden: string[] = []
  private formRows: FormRow[] = []
  private taskRows: TaskRow[] = []
  private recordRows: RecordRow[] = []
  private recordsTitle = ''
  private bots: BotEntryRow[] = []
  private networkSections: NetworkSection[] = []
  private terminals: TerminalInfo[] = []
  private activeTerminalId?: string
  private terminalAttachment?: TerminalAttachment
  private terminalScreen = ''
  private terminalWritable = false
  private terminalStatus = ''
  private terminalError = ''
  private terminalBusy = false
  private terminalDimensions = { cols: 80, rows: 24 }
  private terminalLimits = { maxCols: 240, maxRows: 100, maxInputBytes: 4096 }
  private context?: Object
  private pendingOAuthBaseUrl?: string
  private pendingOAuthProvider?: string
  private lastHandledDeepLink?: string
  // Auto-connect mirrors Android: a remembered, still trusted and currently
  // online host is re-opened on boot and on returning to the foreground, and a
  // dropped carrier retries on Android's bounded backoff. Nothing replays.
  private phase: ConnectionPhase = 'disconnected'
  private retryable = true
  private armed = false
  private foreground = false
  private autoConnectMuted = false
  private lastConnectedDeviceId = ''
  private recovery?: ForegroundConnectionRecovery
  private reconnectFlight?: Promise<boolean>
  private recoveryExhausted = false

  constructor(connection?: AndroidRemoteConnection) { if (connection) this.connection = connection }
  /**
   * Reuses Android's foreground recovery machine. It arms only after a real
   * connection, retries an offline carrier at 1s/3s/8s, and stops once the
   * budget is spent, so a dead host cannot turn into an endless reconnect loop.
   */
  private ensureRecovery(): ForegroundConnectionRecovery {
    if (this.recovery === undefined) {
      this.recovery = new ForegroundConnectionRecovery(
        () => ({
          connection: { phase: this.phase, stats: { mode: this.connection.getStats()?.mode ?? 'Disconnected' }, retryable: this.retryable },
          selectedDevice: this.host === undefined ? undefined : { deviceId: this.host.deviceId },
          reauthRequired: false,
          transportPreference: this.transportPreference,
        }),
        options => this.reconnect(options),
        () => {
          this.recoveryExhausted = true
          this.status = '连接已断开'
          if (this.retryable) this.error = '自动重连未成功，请确认电脑端在线后点「重新连接」。发送与审批不会自动重放。'
          void stopResidentTask(this.context)
          this.publish()
        },
      )
    }
    return this.recovery
  }
  /** True while a dropped carrier is being retried, so the UI says 恢复中 instead of 已断开. */
  private willRetry(): boolean {
    return (this.foreground || residentTaskActive()) && this.armed && !this.autoConnectMuted && this.retryable && !this.recoveryExhausted
      && (this.phase === 'offline' || this.phase === 'reconnecting')
  }
  /** A changed or missing host key needs a human at the computer; retrying it would be wrong. */
  private static identityMismatch(message: string): boolean {
    return message.startsWith('主机身份公钥已改变') || message.startsWith('主机授权或身份在连接前发生变化') || message.startsWith('主机授权信息不匹配')
  }
  /** Re-opens the current host after a drop, then returns to the same workspace and session. */
  private reconnect(options: { forceRelay?: boolean } = {}): Promise<boolean> {
    if (this.reconnectFlight !== undefined) return this.reconnectFlight
    const host = this.host
    if (host === undefined || this.phase === 'connecting') return Promise.resolve(false)
    const cancellation = this.cancellation
    const remembered = { workspaceId: this.workspace?.workspaceId ?? '', sessionId: this.session?.sessionId ?? '' }
    this.phase = 'reconnecting'; this.status = '正在恢复当前对话…'; this.error = ''; this.publish()
    const task = (async () => {
      if (!await this.openHostConnection(host.deviceId, 'restore', options)) throw new Error('请重新核验主机身份。')
      if (cancellation !== this.cancellation || this.host?.deviceId !== host.deviceId) return false
      this.recoveryExhausted = false
      const workspace = remembered.workspaceId.length > 0 ? this.workspaces.find(row => row.workspaceId === remembered.workspaceId) : undefined
      if (workspace !== undefined) { this.workspace = workspace; this.view = 'sessions' }
      const session = remembered.sessionId.length > 0 ? this.sessions.find(row => row.sessionId === remembered.sessionId) : undefined
      if (workspace !== undefined && session !== undefined) await this.openSession(session.sessionId)
      this.publish()
      return true
    })().catch(error => {
      if (cancellation === this.cancellation && this.host?.deviceId === host.deviceId) {
        this.connected = false; this.phase = 'offline'; this.armed = true
        this.retryable = !HarmonyRuntime.identityMismatch((error as Error).message ?? '')
        this.error = safeError(error)
        this.status = this.willRetry() ? '正在恢复当前对话…' : '连接已断开'
        this.publish()
      }
      return false
    })
    this.reconnectFlight = task
    void task.finally(() => { if (this.reconnectFlight === task) this.reconnectFlight = undefined })
    return task
  }
  /**
   * Reconnects the remembered host when the server still reports it trusted and
   * online. Any failure stays silent and lands back on the device list, because
   * auto-connect must never look like an error the user did not ask for.
   */
  private async autoConnect(): Promise<void> {
    if (this.autoConnectMuted || this.connected || this.phase === 'connecting' || this.phase === 'reconnecting' || this.credentials === undefined || this.identity === undefined) return
    const target = resolveStartupAutoConnect({ devices: this.devices, autoConnectHost: this.autoConnectHost, resumeConversation: this.browse.resume, lastConnectedDeviceId: this.lastConnectedDeviceId, hostModes: this.hostModes, scopeForDevice: device => JSON.stringify([this.server, this.account, device.deviceId, device.identityKey]), lastBrowse: this.browse.startup() })
    const host = target.kind === 'connect' ? target.device : undefined
    if (host === undefined) return
    this.phase = 'connecting'; this.status = '正在自动连接主机'; this.publish()
    try {
      if (!await this.openHostConnection(host.deviceId, 'auto')) throw new Error('主机需要重新确认身份。')
      this.autoConnectMuted = false
    } catch {
      await this.disconnect(false, false, false)
      this.error = ''; this.notice = ''
      this.status = '未连接'; this.view = 'devices'
    }
    this.publish()
  }
  /** UIAbility foreground: bring the carrier back for the remembered host. */
  async onForeground(): Promise<void> {
    this.foreground = true
    if (this.botTarget) void this.refreshBotConversation().catch(() => {})
    this.ensureRecovery().setActive(true)
    if (this.connected) { await this.resumeHealth(); this.ensureRecovery().update(); return }
    if (this.busy || this.phase === 'connecting' || this.reconnectFlight !== undefined || this.host !== undefined) {
      this.ensureRecovery().update(); return
    }
    if (this.autoConnectMuted || this.credentials === undefined) { this.ensureRecovery().update(); return }
    try { await this.refreshDevices() } catch { return }
    await this.autoConnect()
  }
  /**
   * Android probes the carrier on resume: a socket that a suspended network
   * left half-open must reconnect instead of pretending to stay connected.
   */
  private async resumeHealth(): Promise<void> {
    const generation = this.generation
    const hostId = this.host?.deviceId
    const current = () => this.generation === generation && this.host?.deviceId === hostId && this.connected
    if (!current()) return
    const healthy = await this.connection.checkHealth().catch(() => false)
    if (!current() || healthy) return
    const retry = await this.connection.checkHealth().catch(() => false)
    if (!current() || retry) return
    console.info('[dsh-remote] Resume health check failed; reconnecting')
    await this.reconnect().catch(() => false)
  }
  /**
   * UIAbility background: keep the carrier. The resident task holds the process
   * and its sockets, so hiding the app must not read as a user-requested stop.
   */
  async onBackground(): Promise<void> {
    await this.flushDrafts().catch(() => { this.error = '草稿保存失败。' })
    if (!residentTaskActive()) { this.botPoll?.abort(); if (this.botTimer) clearTimeout(this.botTimer) }
    this.foreground = false
    this.ensureRecovery().setActive(this.connected || residentTaskActive())
  }

  stageSharedText(value: string): void {
    if (typeof value !== 'string' || value.length > 40000) return
    this.sharedText = value
    if (this.session && this.connected) {
      const key = this.sessionKey()
      this.drafts[key] = [this.drafts[key] ?? '', value].filter(Boolean).join('\n\n').slice(0,40000)
      this.sharedText = ''; this.draftRevision++; this.saveDrafts(); this.publish()
    }
  }
  async readMarkdownImage(path: string, scope: string): Promise<string> {
    this.requireConnected()
    const session = this.session, selection = this.selection
    if (!session || scope !== this.sessionKey() || path.length > 8192 || /^[a-z]+:/i.test(path) && !path.startsWith('workspace:') || path.startsWith('//')) throw new Error('图片路径无效。')
    const value = decodeURIComponent(path.replace(/^workspace:/,''))
    const image = await loadWorkspacePreview(this.connection.requireSessionTools(session.sessionId), session.sessionId, value, 'image', this.imageAbort.signal)
    if (selection !== this.selection || scope !== this.sessionKey()) throw new Error('会话已切换。')
    return `data:${image.mimeType};base64,${image.data}`
  }
  translate(value: string): string { return translateNative(value) }
  attachRtcBridge(send: (raw: string) => Promise<void>): void { attachRtcBridge(send) }
  receiveRtcBridge(raw: string): void { receiveRtcBridge(raw) }
  setListener(listener: (snapshot: string) => void): void { this.listener = listener; this.publish() }
  /** Captured synchronously; preferences open inside initialize() so the first read is ordered. */
  attachContext(context: Object): void {
    this.context = context
    observeResidentTask(() => this.publish())
    updateActivityNotification(context)
    this.applyTheme(this.themePreference)
  }
  private applyTheme(preference: ThemePreference): void {
    if (!this.context) return
    const mode = preference === 'dark' ? 0 : preference === 'light' ? 1 : -1
    try {
      const appCtx = (this.context as { getApplicationContext?: () => { setColorMode?: (mode: number) => void } }).getApplicationContext?.()
      appCtx?.setColorMode?.(mode)
    } catch {}
  }
  private hostScope(): string { return this.browseScope() }
  private browseScope(): string { return JSON.stringify([this.server, this.account, this.host?.deviceId, this.host?.identityKey]) }
  private sessionKey(): string { return this.session ? JSON.stringify([this.browseScope(), this.session.sessionId]) : '' }
  private async saveReadingPosition(input: ReadingInput): Promise<boolean> {
    if (!this.host || !this.session || this.view !== 'chat' || this.busy || input.id !== this.sessionKey()) return false
    if (input.key && !this.messages.some(row => row.id === input.key)) return false
    return this.browse.remember(this.browseScope(), this.session.sessionId, input)
  }
  private async resumeStartupSession(): Promise<void> {
    if (!this.resumePending) return
    this.resumePending = false
    if (!this.browse.resume) return
    const id = this.browse.last(this.browseScope())
    const session = this.sessions.find(row => row.sessionId === id && !this.archived.includes(row.sessionId))
    if (!session) return
    this.workspace = this.workspaces.find(row => row.sessionIds.includes(session.sessionId))
    this.backend = session.backend ?? 'harness'
    await this.openSession(session.sessionId)
  }
  private lastHostKey(): string { return `lastHost.${this.server}|${this.account}` }
  private compactKey(): string { return `compact.${this.server}|${this.account}` }
  private async loadViewPrefs(): Promise<void> {
    const scope = this.hostScope()
    const raw = await prefRead(`view.${scope}`)
    this.favorites = []; this.recents = []; this.collapsed = []
    this.groupBy = 'workspace'; this.orderBy = 'updated'; this.archiveFilter = 'hidden'
    if (!raw) return
    try {
      const saved = JSON.parse(raw) as { favorites?: string[]; recents?: string[]; collapsed?: string[] }
      this.favorites = Array.isArray(saved.favorites) ? saved.favorites : []
      this.recents = Array.isArray(saved.recents) ? saved.recents : []
      this.collapsed = Array.isArray(saved.collapsed) ? saved.collapsed : []
    } catch { /* A corrupt view blob must not block the catalog. */ }
  }
  /**
   * Android keeps the drawer's group, sort and archive options in the drawer's own
   * state, so every open starts from 按工作区 / 最近更新 / 隐藏已归档. Persisting them
   * instead can leave the drawer filtered to 仅已归档 forever: every group then reads
   * 0 条 while the workspace page still shows its real session counts.
   */
  private resetDrawerView(): void {
    this.groupBy = 'workspace'; this.orderBy = 'updated'; this.archiveFilter = 'hidden'; this.visibleCounts = {}
  }
  /** Quick prompts and drafts are device-wide, not per host; identity never enters here. */
  private async loadLocalPrefs(): Promise<void> {
    await this.browse.hydrate()
    this.autoConnectHost = (await prefRead('autoConnectHost')) !== 'false'
    try { this.hostModes = JSON.parse(await prefRead('hostModes') || '{}') } catch { this.hostModes = {} }
    const permission = await prefRead('defaultPermission')
    this.defaultPermission = isCodexPermissionPreset(permission) ? permission : 'default'
    this.statusBarVisible = (await prefRead('statusBarVisible')) !== 'false'
    if (this.context) void setStatusBarVisible(this.context,this.statusBarVisible).catch(()=>{})
    const langPrefRaw = await prefRead(PREF_KEYS.languagePreference)
    if (langPrefRaw) {
      try {
        const val = (JSON.parse(langPrefRaw) as { value?: unknown }).value
        if (isLanguagePreference(val)) this.languagePreference = val
      } catch {}
    }
    const themePrefRaw = await prefRead(PREF_KEYS.themePreference)
    if (themePrefRaw) {
      try {
        const val = (JSON.parse(themePrefRaw) as { value?: unknown }).value
        if (isThemePreference(val)) this.themePreference = val
      } catch {}
    }
    const densityPrefRaw = await prefRead(PREF_KEYS.typographyDensity)
    if (densityPrefRaw) {
      try {
        const val = (JSON.parse(densityPrefRaw) as { value?: unknown }).value
        if (isTypographyDensity(val)) this.typographyDensity = val
      } catch {}
    }
    const notificationsRaw = await prefRead(PREF_KEYS.notifications)
    if (notificationsRaw) {
      try {
        const val = (JSON.parse(notificationsRaw) as { value?: unknown }).value
        if (typeof val === 'boolean') this.notificationsEnabled = val
      } catch {}
    }
    const transportPrefRaw = await prefRead(PREF_KEYS.transportPreference)
    if (transportPrefRaw) {
      try {
        const val = (JSON.parse(transportPrefRaw) as { value?: unknown }).value
        if (val === 'auto' || val === 'turn' || val === 'relay') this.transportPreference = val
      } catch {}
    }
    applyLanguagePreference(this.languagePreference, [systemLocale()])
    this.applyTheme(this.themePreference)
    const builtIns = this.builtInPrompts()
    this.prompts = builtIns.map(item => ({ ...item }))
    this.removedPrompts = []
    const raw = await prefRead('prompts')
    if (raw) {
      try {
        const saved = JSON.parse(raw) as { items?: unknown; removed?: unknown }
        const items = Array.isArray(saved.items) ? saved.items : []
        const cleaned = items.filter((item: unknown): item is CustomPrompt => {
          const row = item as CustomPrompt
          return typeof row?.id === 'string' && row.id.length > 0 && typeof row.title === 'string' && typeof row.text === 'string'
            && row.title.trim().length > 0 && row.text.trim().length > 0
        })
        const merged = [...builtIns.map(item => ({ ...item }))]
        for (const item of cleaned) {
          const index = merged.findIndex(row => row.id === item.id)
          if (index < 0) merged.push(item); else merged[index] = item
        }
        this.removedPrompts = Array.isArray(saved.removed) ? saved.removed.filter((id: unknown): id is string => typeof id === 'string') : []
        this.prompts = merged.filter(item => !this.removedPrompts.includes(item.id))
      } catch { /* Corrupt prompt storage falls back to the built-in list. */ }
    }
    const drafts = await prefRead('drafts')
    if (drafts) { try { this.drafts = JSON.parse(drafts) as Record<string, string> } catch { this.drafts = {} } }
  }
  private savePrompts(): void {
    void prefWrite('prompts', JSON.stringify({ items: this.prompts.filter(item => !this.isBuiltIn(item.id)), removed: this.removedPrompts.slice(0, 100) })).catch(() => { this.notice = '本地偏好保存失败，请解锁后重试。'; this.publish() })
  }
  private saveDrafts(): void {
    if (this.draftTimer) clearTimeout(this.draftTimer)
    this.draftTimer = setTimeout(() => { this.draftTimer = undefined; void this.flushDrafts().catch(() => { this.error = '草稿保存失败，请解锁后重试。'; this.publish() }) }, 600)
  }
  private async flushDrafts(): Promise<void> {
    if (this.draftTimer) clearTimeout(this.draftTimer)
    this.draftTimer = undefined
    const keys = Object.keys(this.drafts)
    if (keys.length === 0) return
    const trimmed = keys.length > 40 ? keys.slice(keys.length - 40) : keys
    const kept: Record<string, string> = {}
    for (const key of trimmed) if (this.drafts[key]) kept[key] = this.drafts[key]
    await prefWrite('drafts', JSON.stringify(kept))
  }
  private isBuiltIn(id: string): boolean { return BUILT_IN_PROMPT_IDS.includes(id) }
  private builtInPrompts(): CustomPrompt[] {
    const chat = strings.chat as unknown as Record<string, string>
    return [
      { id: 'builtin-check-changes', title: chat.quickCheckChanges, text: chat.quickCheckChangesPrompt },
      { id: 'builtin-commit', title: chat.quickCommit, text: chat.quickCommitPrompt },
      { id: 'builtin-view-screenshot', title: chat.quickViewScreenshot, text: chat.quickViewScreenshotPrompt },
    ].filter(item => typeof item.title === 'string' && typeof item.text === 'string' && item.title.length > 0)
  }
  private saveViewPrefs(): void {
    void prefWrite(`view.${this.hostScope()}`, JSON.stringify({
      favorites: this.favorites.slice(0, 200), recents: this.recents.slice(0, 50),
      collapsed: this.collapsed.slice(0, 400),
    })).catch(() => { this.notice = '本地浏览状态保存失败，请解锁后重试。'; this.publish() })
  }
  private key(suffix: string): string {
    const scope = Array.from(sha256(new TextEncoder().encode(this.server)), byte => byte.toString(16).padStart(2, '0')).join('')
    return `dsh.hm.${scope}.${suffix}`
  }
  private trustKey(host: RemoteDevice): string {
    const owner = Array.from(sha256(new TextEncoder().encode(this.account)), byte => byte.toString(16).padStart(2, '0')).join('')
    return this.key(`trust.${owner}.${host.deviceId}`)
  }

  async initialize(): Promise<void> {
    if (this.initialized) return
    this.initialized = true
    this.foreground = true
    this.ensureRecovery().setActive(true)
    this.busy = true; this.publish()
    try {
      applyLanguagePreference('zh-CN', [systemLocale()])
      if (this.context) await attachPreferences(this.context)
      try { await this.loadLocalPrefs() } catch { this.notice = '本地浏览数据暂不可用，请解锁后重试；账号授权保留。' }
      const settings = await vaultRead(SETTINGS_KEY)
      if (settings) this.server = normalizeServerUrl(JSON.parse(settings).server)
      const stored = await vaultRead(IDENTITY_KEY)
      if (stored) {
        this.identity = JSON.parse(stored) as DeviceIdentity
        const pair = generateKeyPair(fromBase64Url(this.identity.privateKey))
        if (pair.publicKey !== this.identity.publicKey) throw new Error('本机身份损坏，已停止连接。')
      } else {
        // The shared Android type restricts platform to Android; override only
        // this descriptor field. Server's protocol accepts "harmonyos".
        this.identity = { ...generateKeyPair(), deviceId: crypto.randomUUID(), name: 'HarmonyOS 手机', platform: 'harmonyos' as DeviceIdentity['platform'] }
        await vaultWrite(IDENTITY_KEY, JSON.stringify(this.identity))
      }
      const saved = await vaultRead(this.key('credentials'))
      if (saved) {
        const parsed = JSON.parse(saved) as Credentials
        const { account, ...tokens } = parsed
        if (typeof account !== 'string' || !account.length) throw new Error('本机授权记录无效，请重新登录。')
        this.credentials = { ...deviceTokenPairSchema.parse(tokens), account }
        this.legacyDraftOwner = await prefRead('legacyDraftOwner') || account
        await prefWrite('legacyDraftOwner', this.legacyDraftOwner)
      }
    } catch (error) { this.error = safeError(error) }
    finally { this.busy = false; this.publish() }
    // Restoring a valid credential must not be confused with an empty host list.
    if (this.credentials) {
      this.account = this.credentials.account
      this.lastConnectedDeviceId = await prefRead(this.lastHostKey())
      this.view = 'devices'
      await this.perform('refresh', '{}')
      await this.autoConnect()
    }
  }

  async perform(action: string, raw: string): Promise<boolean> {
    if (action === 'saveDraft') {
      try { const value = JSON.parse(raw) as Input; if (value.id !== this.sessionKey()) return false; this.drafts[value.id] = (value.text ?? '').slice(0, 40000); this.saveDrafts(); return true } catch { return false }
    }
    if (action === 'saveReadingPosition') {
      try { return await this.saveReadingPosition(JSON.parse(raw) as ReadingInput) } catch { return false }
    }
    if (this.busy && !['disconnect', 'reconnect', 'interrupt', 'approval', 'question', 'back'].includes(action)) return false
    let input: Input
    try { input = JSON.parse(raw || '{}') as Input } catch { return false }
    let success = true
    const generation = this.generation
    this.error = ''; this.notice = ''
    const concurrent = action === 'interrupt' || action === 'approval' || action === 'question'
    if (!concurrent) this.busy = true
    this.publish()
    try {
      if (action === 'login') await this.login(input)
      else if (action === 'startOAuth') await this.startOAuth(input)
      else if (action === 'cancelOAuth') this.cancelOAuth()
      else if (action === 'qr') await this.startQr(input)
      else if (action === 'cancelQr') this.stopQr()
      else if (action === 'refresh') await this.refreshDevices()
      else if (action === 'inspectHost') await this.inspectHost(input.id ?? '')
      else if (action === 'trustHost') await this.trustHost(input.id ?? '')
      else if (action === 'connect') { await this.connectHost(input.id ?? ''); this.autoConnectMuted = false }
      else if (action === 'reconnect') await this.reconnect()
      else if (action === 'disconnect') await this.disconnect()
      else if (action === 'catalog') await this.loadCatalog()
      else if (action === 'appSettings') await openAppPowerManagementPage(this.context)
      else if (action === 'retryBackground') { if (!this.connected) throw new Error('请先连接主机'); await startResidentTask(this.context) }
      else if (action === 'checkUpdate') {
        const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 15000)
        try { this.updateVersion = await latestRelease(controller.signal) } finally { clearTimeout(timer) }
      }
      else if (action === 'openUpdates') await this.openBrowserUrl(RELEASE_URL)
      else if (action === 'cancelDownload') { this.download.cancel(); ++this.downloadRevision; this.downloadBusy = false }
      else if (action === 'workspace') { this.workspace = this.workspaces.find(w => w.workspaceId === input.id); this.view = 'sessions' }
      else if (action === 'backend') { this.backend = input.backend ?? 'harness'; this.visibleCounts = {} }
      else if (action === 'groupMode') { this.groupBy = input.mode === 'list' ? 'list' : 'workspace'; this.saveViewPrefs() }
      else if (action === 'sortMode') { this.orderBy = input.mode === 'manual' ? 'manual' : 'updated'; this.saveViewPrefs() }
      else if (action === 'archiveFilter') { this.archiveFilter = input.mode === 'all' ? 'all' : input.mode === 'only' ? 'only' : 'hidden'; this.saveViewPrefs() }
      else if (action === 'toggleGroup') await this.toggleGroup(input.id ?? '')
      else if (action === 'openDrawer') this.resetDrawerView()
      else if (action === 'showMore') { this.visibleCounts[input.id ?? ''] = (this.visibleCounts[input.id ?? ''] ?? SESSION_PAGE_SIZE) + 10; this.saveViewPrefs() }
      else if (action === 'favorite') await this.toggleFavorite(input.id ?? '')
      else if (action === 'archive') await this.archiveSession(input.id ?? '')
      else if (action === 'fork') await this.forkMessage(input.id ?? '')
      else if (action === 'feedback') await this.rateMessage(input.id ?? '', input.rating ?? '')
      else if (action === 'morePanel') await this.loadPanel()
      else if (action === 'skills') await this.loadSkills()
      else if (action === 'command') await this.runCommand(input.text ?? '')
      else if (action === 'files') await this.listFiles(input.id ?? '')
      else if (action === 'readFile') { this.download.cancel(); ++this.downloadRevision; this.downloadBusy = false; await this.previewFile(input.id ?? '', typeof input.offset === 'number' ? input.offset : 1) }
      else if (action === 'closeFile') { this.download.cancel(); ++this.downloadRevision; this.downloadBusy = false; this.filePreview = undefined }
      else if (action === 'compactHistory') await this.toggleCompactHistory()
      else if (action === 'sessionInfo') await this.loadInfo()
      else if (action === 'networkDetails') await this.loadNetworkDetails()
      else if (action === 'plugins') await this.loadPlugins()
      else if (action === 'pluginToggle') await this.togglePlugin(input.id ?? '', input.mode === 'on')
      else if (action === 'pluginForm') await this.openPluginForm(input.id ?? '')
      else if (action === 'pluginSave') await this.savePluginForm(input.text ?? '')
      else if (action === 'pluginReset') await this.resetPluginForm()
      else if (action === 'tasks') await this.loadTasks()
      else if (action === 'setAutoConnectHost') { this.autoConnectHost = input.enabled === true; await prefWrite('autoConnectHost', String(this.autoConnectHost)) }
      else if (action === 'manageHosts') { await this.refreshDevices(); this.view = 'devices' }
      else if (action === 'retrySend') {
        const row = this.failedSends.find(row => row.id === input.id && row.scope === this.sessionKey())
        if (!row || input.enabled !== true) throw new Error('请确认后重新发送。')
        this.failedSends = this.failedSends.filter(value => value !== row)
        await this.prompt(row)
      }
      else if (action === 'dismissSend') this.failedSends = this.failedSends.filter(row => row.id !== input.id)
      else if (action === 'taskSave') await this.saveTask(input.text ?? '')
      else if (action === 'jobOutput') await this.activity.follow(input.id ?? '')
      else if (action === 'jobKill') await this.activity.kill(input.id ?? '')
      else if (action === 'sessionManage') await this.manageSession(input.id ?? '', input.mode ?? '', input.name ?? '')
      else if (action === 'hostDirectory') await this.browseHostDirectory(input.path ?? '')
      else if (action === 'taskToggle') {
        const row = this.scheduleEntries.find(row => row.id === input.id && row.sessionId === input.name)
        if (row) { row.status = row.status === 'active' ? 'inactive' : 'active'; this.taskRows = this.taskRows.map(item => item.id === row.id && item.session === row.sessionId ? { ...item, active: row.status === 'active', status: row.status === 'active' ? '运行中' : '已停用' } : item) }
      }
      else if (action === 'taskDelete') await this.deleteTask(input.id ?? '', input.name ?? '')
      else if (action === 'taskHistory') await this.loadTaskHistory(input.id ?? '', input.name ?? '')
      else if (action === 'bots') await this.loadBots()
      else if (action === 'botViewReply') {
        const pending = botObject(this.botState?.views?.[this.session?.sessionId ?? ''])
        if (!this.botTarget || input.mode !== this.sessionKey() || input.name !== text(pending.id)) throw new Error('卡片已失效。')
        const reply = JSON.parse(input.text ?? '{}') as { action: string; values: Record<string, unknown> }
        const view = checkedBotView(pending)
        if (!view || validateViewAnswer(view, reply.action, reply.values).error) throw new Error('卡片回答无效。')
        await this.botOperation('view-reply', JSON.stringify({ sessionId: this.session!.sessionId, viewId: pending.id, action: reply.action, values: reply.values }))
      }
      else if (action === 'botEarlier') await this.loadBotEarlier()
      else if (action === 'botRead') await this.readBotDetails(input.mode ?? '', input.name ?? '')
      else if (action === 'botRefresh') await this.refreshBotConversation()
      else if (action === 'botOperation') await this.botOperation(input.mode ?? '', input.text ?? '{}')
      else if (action === 'copyText') { if ((input.text ?? '').length <= 1024*1024) await copyText(input.text ?? '') }
      else if (action === 'copyMessage' || action === 'shareMessage') {
        const row = this.messages.find(item => item.id === input.id)
        if (row?.kind !== 'message') throw new Error('消息不可用。')
        if (action === 'copyMessage') await copyText(row.text)
        else if (this.context) await shareText(this.context,row.text)
      }
      else if (action === 'uploadFile') {
        this.requireConnected()
        if (!this.session || (this.session.backend ?? 'harness') !== 'harness') throw new Error('当前后端不支持工作区上传。')
        const name = input.name ?? '', data = input.text ?? ''
        if (!name || name.length > 255 || /[\\/\u0000]/.test(name) || !/^[A-Za-z0-9+/]+={0,2}$/.test(data) || data.length > 28*1024*1024 || this.stagedFiles.length >= 8 || [...this.stagedData.values()].reduce((sum,row)=>sum+row.length,0)+data.length > 44*1024*1024) throw new Error('附件名称、数量或大小超过限制。')
        const bytes = Uint8Array.from(atob(data), char => char.charCodeAt(0))
        if (!isTextFile(name) || bytes.byteLength > MAX_SINGLE_FILE_BYTES || [...this.stagedData.values()].reduce((sum,row)=>sum+atob(row).length,0)+bytes.byteLength > MAX_TOTAL_FILES_BYTES) throw new Error('请选择单个 512 KiB、合计 2 MiB 以内的代码或文本文件')
        const content = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
        if (!isValidUtf8Text(content)) throw new Error('文件不是有效的 UTF-8 文本')
        const id = createNativeRpcId()
        this.stagedFiles.push({ id, scope: this.sessionKey(), name, path: '' }); this.stagedData.set(id,data)
        this.notice = '附件已暂存，发送时上传到当前工作区。'
      }
      else if (action === 'removeFile') { this.stagedFiles = this.stagedFiles.filter(row => row.id !== input.id); this.stagedData.delete(input.id ?? '') }
      else if (action === 'imageLoad') await this.loadChatImages(input.id ?? '')
      else if (action === 'quote') {
        const row = this.messages.find(row => row.id === input.id)
        if (!row || row.kind !== 'message' || !this.session) throw new Error('消息不可用。')
        const key = this.sessionKey()
        this.drafts[key] = `${this.drafts[key] ?? ''}\n\n${row.text.split('\n').map(line => '> ' + line).join('\n')}\n\n`.slice(0,40000)
        this.draftRevision++
        this.saveDrafts()
      }
      else if (action === 'openLink') await this.routeLink(input.text ?? '')
      else if (action === 'resizeTerminal') {
        const size = JSON.parse(input.text ?? '{}') as { cols: number; rows: number }
        if (Number.isFinite(size.cols) && Number.isFinite(size.rows) && this.terminalWritable) {
          this.terminalDimensions = { cols: Math.min(this.terminalLimits.maxCols, Math.max(2,Math.floor(size.cols))), rows: Math.min(this.terminalLimits.maxRows, Math.max(2,Math.floor(size.rows))) }
          await this.terminalAttachment?.resize(this.terminalDimensions.cols, this.terminalDimensions.rows)
        }
      }
      else if (action === 'botSelect') await this.openBotSession(input.id ?? '')
      else if (action === 'uiAction') {
        const artifact = this.host && this.session ? projectUiArtifacts(this.messages, this.host.deviceId, this.session.sessionId).find(row => row.uiId === input.id) : undefined
        if (!artifact || input.mode !== this.sessionKey() || String(artifact.version) !== input.name) throw new Error('卡片已更新或会话已切换。')
        const text = (input.text ?? '').trim()
        if (text.length > 0 && text.length <= 4000) await this.prompt({ text })
      }
      else if (action === 'openTerminal') await this.openTerminal()
      else if (action === 'createTerminal') await this.createTerminal()
      else if (action === 'selectTerminal') await this.selectTerminal(input.id ?? '')
      else if (action === 'closeTerminal') await this.closeTerminal()
      else if (action === 'writeTerminal') await this.writeTerminal(input.text ?? '')
      else if (action === 'clearTerminal') { this.setTerminalRenderer(this.terminalRendererScope, false); this.terminalScreen = ''; this.terminalRaw = ''; this.terminalChunk = ''; this.terminalReset = true; ++this.terminalRenderRevision; this.publish() }
      else if (action === 'retryTerminal') await this.openTerminal()
      else if (action === 'selectMode') await this.selectMode(input.id ?? '')
      else if (action === 'selectPermission') await this.selectPermission(input.id ?? '')
      else if (action === 'queueAction') await this.queueAction(input.id ?? '', input.mode ?? '')
      else if (action === 'saveDraft') { this.drafts[input.id ?? ''] = (input.text ?? '').slice(0, 4000); this.saveDrafts() }
      else if (action === 'savePrompt') await this.savePrompt(input)
      else if (action === 'deletePrompt') await this.deletePrompt(input.id ?? '')
      else if (action === 'renameWorkspace') { await this.connection.requireProxy().workspaceRename(input.id ?? '', (input.name ?? '').trim()); await this.loadCatalog() }
      else if (action === 'deleteWorkspace') await this.deleteWorkspace(input.id ?? '')
      else if (action === 'moveWorkspace') await this.moveWorkspace(input.id ?? '', input.mode ?? '')
      else if (action === 'moveSession') await this.moveSession(input.id ?? '')
      else if (action === 'forgetHost') {
        await (await this.api()).removeAccountDevice(input.id ?? '')
        this.candidate = undefined
        if (input.id === this.lastConnectedDeviceId) { this.lastConnectedDeviceId = ''; await prefWrite(this.lastHostKey(), '') }
        await this.refreshDevices(); this.view = 'devices'
      }
      else if (action === 'session') { this.hostModes[this.browseScope()] = 'agent'; await prefWrite('hostModes', JSON.stringify(this.hostModes)); await this.openSession(input.id ?? '') }
      else if (action === 'newSession') await this.newSession()
      else if (action === 'newSessionIn') {
        this.requireConnected()
        const workspace = this.workspaces.find(row => row.workspaceId === input.id)
        if (!workspace) throw new Error('工作区不存在，请刷新')
        this.workspace = workspace; this.backend = workspace.backend ?? 'harness'
        await this.newSession()
      }
      else if (action === 'newWorkspace') await this.newWorkspace(input.path ?? '')
      else if (action === 'prompt') await this.prompt(input)
      else if (action === 'interrupt') await this.interrupt()
      else if (action === 'approval') await this.approval(input)
      else if (action === 'question') await this.answerQuestion(input)
      else if (action === 'model') await this.selectModel(input)
      else if (action === 'history') await this.olderHistory()
      else if (action === 'setLanguage') {
        const val = input.name ?? input.id
        if (isLanguagePreference(val)) {
          this.languagePreference = val
          await prefWrite(PREF_KEYS.languagePreference, JSON.stringify({ value: val }))
          applyLanguagePreference(val, [systemLocale()])
          this.savePrompts()
        }
      }
      else if (action === 'setTheme') {
        const val = input.name ?? input.id
        if (isThemePreference(val)) {
          this.themePreference = val
          await prefWrite(PREF_KEYS.themePreference, JSON.stringify({ value: val }))
          this.applyTheme(val)
        }
      }
      else if (action === 'setDensity') {
        const val = input.name ?? input.id
        if (isTypographyDensity(val)) {
          this.typographyDensity = val
          await prefWrite(PREF_KEYS.typographyDensity, JSON.stringify({ value: val }))
        }
      }
      else if (action === 'setNotifications') {
        const val = input.name !== 'false' && input.mode !== 'false' && input.enabled !== false
        this.notificationsEnabled = val
        await prefWrite(PREF_KEYS.notifications, JSON.stringify({ value: val }))
      }
      else if (action === 'setDefaultPermission') {
        const value = input.name ?? 'default'
        if (value !== 'default' && !isCodexPermissionPreset(value)) throw new Error('权限预设无效。')
        this.defaultPermission = value; await prefWrite('defaultPermission', value)
      }
      else if (action === 'setStatusBar') {
        this.statusBarVisible = input.enabled !== false; await prefWrite('statusBarVisible',String(this.statusBarVisible))
        if(this.context) await setStatusBarVisible(this.context,this.statusBarVisible)
      }
      else if (action === 'clearBrowseData') {
        await this.flushDrafts(); await this.disconnect(); await clearBrowsePreferences(); this.browse = new HarmonyBrowseMemory()
        this.drafts = {}; this.hostModes = {}; this.favorites = []; this.recents = []; this.lastConnectedDeviceId = ''; this.notice = '本机浏览记录已清除。'
      }
      else if (action === 'setResumeSession') await this.browse.setResume(input.enabled === true)
      else if (action === 'requestNotificationPermission') {
        const enabled = await requestNotificationPermission(this.context)
        this.notice = enabled ? '系统通知已开启' : '系统通知未开启，请在应用设置中允许通知'
      }
      else if (action === 'setTransportPreference') {
        const val = input.mode === 'relay' ? 'relay' : input.mode === 'turn' ? 'turn' : 'auto'
        this.transportPreference = val
        await prefWrite(PREF_KEYS.transportPreference, JSON.stringify({ value: val }))
      }
      else if (action === 'logout') await this.logout()
      else if (action === 'renameHost') { await (await this.api()).renameAccountDevice(input.id ?? '', input.name ?? ''); await this.refreshDevices() }
      else if (action === 'back') {
        this.stopQr(); ++this.selection; ++this.cancellation
        if (!this.connected && this.status !== '未连接') await this.disconnect()
        this.view = this.view === 'chat' ? (this.workspace ? 'sessions' : 'workspaces') : this.connected ? 'workspaces' : this.credentials ? 'devices' : 'login'
      } else throw new Error('不支持的操作。')
    } catch (error) { success = false; if (generation === this.generation || ['login', 'startOAuth', 'connect', 'trustHost'].includes(action)) this.error = safeError(error) }
    finally { if (!concurrent) this.busy = false; this.publish() }
    return success
  }

  private async setServer(input: Input): Promise<void> {
    const next = normalizeServerUrl(input.server ?? this.server)
    if (next.length > 180) throw new Error('服务器地址过长。')
    if (next !== this.server) { await this.disconnect(); this.credentials = undefined; this.account = ''; this.devices = []; this.server = next }
    await vaultWrite(SETTINGS_KEY, JSON.stringify({ server: this.server }))
  }
  private async login(input: Input): Promise<void> {
    this.stopQr(); await this.setServer(input)
    if (!this.identity) throw new Error('本机安全身份不可用，请重新启动。')
    const api = new RemoteServerApi(this.server)
    const result = await api.loginAccount(input.email ?? '', input.password ?? '')
    await this.register(result.token, result.account)
  }
  private async register(token: string, account: string): Promise<void> {
    if (!this.identity) throw new Error('本机身份不可用。')
    const pair = await new RemoteServerApi(this.server).registerDevice(this.identity, token)
    const credentials = { ...pair, account }
    await vaultWrite(this.key('credentials'), JSON.stringify(credentials))
    this.credentials = credentials; this.account = account; this.view = 'devices'
    await this.refreshDevices()
    this.lastConnectedDeviceId = await prefRead(this.lastHostKey())
    await this.autoConnect()
  }
  private async startQr(input: Input): Promise<void> {
    this.stopQr(); await this.setServer(input)
    const api = new RemoteServerApi(this.server)
    const providers = await api.oauthProviders()
    const provider = providers.find(p => p.id === input.provider && p.qrStartUrl)
    if (!provider) throw new Error('服务器尚未启用此扫码登录方式。')
    const qr = await api.startOAuthQrLogin(provider)
    this.qr = { ...qr, expiresAt: Date.now() + qr.expiresIn * 1000 }
    const current = this.qr
    const poll = async () => {
      if (this.qr !== current) return
      try {
        if (Date.now() >= current.expiresAt) throw new Error('二维码已过期，请重新获取。')
        const result = await api.pollOAuthQrLogin(current.qrId)
        if (this.qr !== current) return
        if (result.status === 'expired') throw new Error('二维码已过期，请重新获取。')
        if (result.status === 'complete') {
          this.stopQr(); this.busy = true; this.publish()
          const me = await api.accountMe(result.token)
          await this.register(result.token, me.account)
          this.busy = false; this.publish(); return
        }
        this.qrTimer = setTimeout(() => { void poll() }, 1800)
      } catch (error) { if (this.qr === current || this.busy) { this.stopQr(); this.busy = false; this.error = safeError(error); this.publish() } }
    }
    this.qrTimer = setTimeout(() => { void poll() }, 1800)
  }
  private stopQr(): void { if (this.qrTimer) clearTimeout(this.qrTimer); this.qrTimer = undefined; this.qr = undefined }
  private async startOAuth(input: Input): Promise<void> {
    this.stopQr()
    await this.setServer(input)
    const providerId = input.provider || 'github'
    const api = new RemoteServerApi(this.server)
    const providers = await api.oauthProviders()
    const provider = providers.find(p => p.id === providerId)
    if (!provider) {
      throw new Error(`服务器未启用 ${providerId === 'zhihu' ? '知乎' : providerId === 'github' ? 'GitHub' : providerId} 登录服务。`)
    }
    const startUrl = provider.startUrl
    const url = new URL(startUrl.startsWith('http') ? startUrl : `${this.server}${startUrl}`)
    url.searchParams.set('return_to', 'dshremote://oauth')
    this.pendingOAuthBaseUrl = this.server
    this.pendingOAuthProvider = providerId
    this.notice = `正在打开浏览器进行 ${provider.displayName || providerId} 授权...`
    this.publish()
    await this.openBrowserUrl(url.toString())
  }
  private cancelOAuth(): void {
    this.pendingOAuthBaseUrl = undefined
    this.pendingOAuthProvider = undefined
    this.notice = ''
    this.publish()
  }
  async openBrowserUrl(url: string): Promise<void> {
    const ctx = this.context as {
      openLink?: (url: string) => Promise<void>
      startAbility?: (want: Object) => Promise<void>
    } | undefined
    if (typeof ctx?.openLink === 'function') {
      await ctx.openLink(url)
    } else if (typeof ctx?.startAbility === 'function') {
      await ctx.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      })
    } else {
      console.info(`DSH Remote: openBrowserUrl: ${url}`)
    }
  }
  async handleDeepLink(uri: string): Promise<boolean> {
    if (!uri || typeof uri !== 'string') return false
    if (this.lastHandledDeepLink === uri) return false
    try {
      const parsed = new URL(uri)
      if (parsed.protocol !== 'dshremote:') return false
      if (parsed.hostname === 'oauth' || parsed.host === 'oauth') {
        this.lastHandledDeepLink = uri
        const error = parsed.searchParams.get('error')
        const token = parsed.searchParams.get('token')
        if (error !== null) {
          this.pendingOAuthBaseUrl = undefined
          this.pendingOAuthProvider = undefined
          this.error = '未完成授权，请再试一次。'
          this.notice = ''
          this.busy = false
          this.publish()
          return false
        }
        if (!token || token.length < 16) {
          this.pendingOAuthBaseUrl = undefined
          this.pendingOAuthProvider = undefined
          this.error = '登录信息已失效，请重新登录。'
          this.notice = ''
          this.busy = false
          this.publish()
          return false
        }
        this.busy = true
        this.error = ''
        this.notice = '正在完成账号授权与本机注册...'
        this.publish()
        if (!this.initialized) await this.initialize()
        const targetServer = this.pendingOAuthBaseUrl || this.server
        this.pendingOAuthBaseUrl = undefined
        this.pendingOAuthProvider = undefined
        const api = new RemoteServerApi(targetServer)
        const me = await api.accountMe(token)
        this.server = targetServer
        await this.register(token, me.account)
        this.notice = ''
        this.busy = false
        this.publish()
        return true
      }
      if (parsed.hostname === 'session') {
        const hostId = parsed.searchParams.get('hostId'), sessionId = parsed.searchParams.get('sessionId')
        if (!hostId || !sessionId || hostId.length > 4096 || sessionId.length > 4096) return false
        await this.handleNotificationNavigation(hostId, sessionId); return true
      }
      return false
    } catch (e) {
      this.pendingOAuthBaseUrl = undefined
      this.pendingOAuthProvider = undefined
      this.busy = false
      this.error = safeError(e)
      this.notice = ''
      this.publish()
      return false
    }
  }
  private async api(): Promise<RemoteServerApi> {
    if (!this.credentials || !this.identity) throw new Error('请先登录账号。')
    if (this.credentials.accessTokenExpiresAt < Date.now() + 30000) {
      if (!this.refreshing) {
        const credentials = this.credentials, server = this.server
        this.refreshing = (async () => {
          const pair = await new RemoteServerApi(server).refreshToken(this.identity!.deviceId, credentials.refreshToken)
          if (this.credentials !== credentials || this.server !== server) throw new Error('授权已切换。')
          const fresh = { ...pair, account: this.account }
          await vaultWrite(this.key('credentials'), JSON.stringify(fresh)); this.credentials = fresh
        })().finally(() => { this.refreshing = undefined })
      }
      await this.refreshing
    }
    return new RemoteServerApi(this.server, this.credentials.accessToken)
  }
  private async refreshDevices(): Promise<void> {
    const server = this.server, account = this.account
    const api = await this.api()
    const devices = await api.listDevices()
    for (const device of devices) {
      device.trusted = !!await vaultRead(this.trustKey(device))
      // The membership record's online flag is a cache that lags a Host's relay session, so
      // Android's directory prefers the live presence answer. Without it a reachable host is
      // listed as 离线, the trust page warns for nothing, and auto-connect never fires.
      const presence = await api.getPresence(device.deviceId).catch(() => undefined)
      device.online = presence?.online ?? device.online === true
    }
    if (server !== this.server || account !== this.account) throw new Error('账号已切换。')
    this.devices = devices
  }
  /** Checks the descriptor against the local trust record without touching navigation. */
  private async verifyHost(id: string): Promise<RemoteDevice> {
    const peer = await (await this.api()).deviceFor(id)
    if (peer.deviceId !== id || peer.role !== 'host' || !peer.membershipId) throw new Error('主机授权信息不匹配。')
    const previous = await vaultRead(this.trustKey(peer as RemoteDevice))
    if (previous && previous !== peer.identityKey) throw new Error('主机身份公钥已改变，已阻止连接。请在电脑端核验。')
    // The directory entry already carries the presence answer; the descriptor's flag is stale.
    const listed = this.devices.find(row => row.deviceId === id)
    return {
      ...peer, role: 'host', online: listed?.online ?? peer.online === true,
      trusted: !!previous, fingerprint: identityFingerprint(peer.identityKey),
    }
  }
  private async inspectHost(id: string): Promise<void> {
    const cancellation = this.cancellation, server = this.server, account = this.account
    const host = await this.verifyHost(id)
    if (cancellation !== this.cancellation || server !== this.server || account !== this.account) throw new Error('连接已取消。')
    this.candidate = host
    this.view = 'trust'
  }
  private async trustHost(id: string): Promise<void> {
    const cancellation = this.cancellation
    const host = this.candidate
    if (!host || host.deviceId !== id) throw new Error('请重新查看主机身份。')
    await vaultWrite(this.trustKey(host), host.identityKey)
    if (cancellation !== this.cancellation) throw new Error('连接已取消。')
    host.trusted = true
    await this.connectHost(id)
  }
  private async connectHost(id: string): Promise<void> {
    await this.openHostConnection(id, 'manual')
    // A connect the user asked for re-enables recovery for this host.
    if (this.connected) this.autoConnectMuted = false
  }
  /**
   * Opens the encrypted channel to a host whose key already matches the local
   * trust record. `restoring` keeps navigation, the loaded catalog and the
   * current host so a reconnect can land back on the same session.
   */
  private async openHostConnection(id: string, kind: 'manual' | 'restore' | 'auto', options: { forceRelay?: boolean } = {}): Promise<boolean> {
    // restore keeps navigation and the loaded catalog; manual and auto both
    // start from a clean slate and land on the workspace list.
    const restoring = kind === 'restore'
    const cancellation = this.cancellation
    const host = await this.verifyHost(id)
    const pin = await vaultRead(this.trustKey(host))
    if (cancellation !== this.cancellation) throw new Error('连接已取消。')
    if (pin !== host.identityKey) {
      this.candidate = host; this.view = 'trust'
      return false // Await the user's fingerprint confirmation.
    }
    if (restoring) { ++this.generation; ++this.selection; await this.connection.close() }
    else await this.disconnect(false, false, false)
    const generation = ++this.generation
    const api = await this.api()
    const peer = await api.deviceFor(id)
    if (generation !== this.generation || cancellation !== this.cancellation) throw new Error('连接已取消。')
    if (peer.identityKey !== pin || peer.membershipId !== host.membershipId) throw new Error('主机授权或身份在连接前发生变化。')
    this.host = host; this.phase = 'connecting'; this.armed = false
    this.status = restoring ? '正在恢复当前对话…' : '建立加密连接'; this.publish()
    if (!restoring) { await this.loadViewPrefs(); this.backend = 'harness'; this.visibleCounts = {} }
    try {
      const preference = this.transportPreference
      const forceRelay = preference === 'relay' || options.forceRelay === true
      const preferredTransports: Array<'lan' | 'p2p' | 'turn' | 'relay'> = forceRelay
        ? ['relay']
        : preference === 'turn'
          ? ['turn', 'relay']
          : ['lan', 'p2p', 'turn', 'relay']
      await this.connection.connect(this.server, this.identity!, host, this.credentials!.accessToken, frame => {
        if (this.generation !== generation) return
        this.onFrame(frame)
      }, {
        forceRelay,
        preferredTransports,
        refreshAccessToken: async () => { await this.api(); return this.credentials!.accessToken },
        fetchIceServers: async connectionId => (await this.api()).turnCredentials(connectionId),
        onSecureHandshake: () => { if (generation === this.generation) { this.status = '验证 Noise IK 身份'; this.publish() } },
        onClose: event => {
          if (generation !== this.generation) return
          this.retryable = event?.retryable !== false
          this.connected = false; this.phase = 'offline'; this.running = false
          this.messages = this.messages.filter(item => item.kind !== 'approval' && item.kind !== 'question')
          const retrying = this.willRetry()
          this.status = retrying ? '正在恢复当前对话…' : '连接已断开'
          if (!retrying) this.error = this.retryable ? '连接已断开。请重新连接；发送与审批不会自动重放。' : '连接已被服务端关闭，自动重试已停止。请检查授权或其他客户端连接后手动重连。'
          if (!retrying) void stopResidentTask(this.context)
          this.publish()
        },
      })
      if (generation !== this.generation) throw new Error('连接已取消。')
      this.connected = true; this.phase = 'connected'; this.armed = true
      this.retryable = true; this.recoveryExhausted = false
      await startResidentTask(this.context)
      if (this.foreground && this.context && !await prefRead('notificationPermissionAsked')) {
        await prefWrite('notificationPermissionAsked', 'true')
        await requestNotificationPermission(this.context)
      }
      const mode = this.connection.getStats()?.mode
      this.status = mode === 'P2P' ? 'Noise IK · 点对点直连'
        : mode === 'LAN' ? 'Noise IK · 局域网直连'
        : mode === 'TURN' ? 'Noise IK · 穿透中继'
        : 'Noise IK · 加密中继'
      if (!restoring) this.view = 'workspaces'
      await this.saveLastConnected(host.deviceId)
      await this.loadCatalog()
      if (this.pendingNotificationSession && this.pendingNotificationSession.hostId === host.deviceId) {
        this.resumePending = false
        const pending = this.pendingNotificationSession
        this.pendingNotificationSession = undefined
        await this.openSession(pending.sessionId).catch(() => {})
      } else if (kind === 'auto' && this.hostModes[this.browseScope()] === 'bot') {
        this.resumePending = false; await this.loadBots(); this.view = 'botHome'
      } else if (kind === 'auto') {
        await this.resumeStartupSession().catch(() => { this.view = 'workspaces'; this.notice = '上次对话暂时无法恢复，请从工作区重新选择。' })
      }
      return true
    } catch (error) {
      if (generation !== this.generation || cancellation !== this.cancellation) throw error
      this.connected = false; this.armed = false; this.phase = 'offline'
      // A key mismatch needs a person at the computer, not a retry storm.
      this.retryable = !HarmonyRuntime.identityMismatch((error as Error).message ?? '')
      throw error
    }
  }
  private async saveLastConnected(deviceId: string): Promise<void> {
    if (deviceId === this.lastConnectedDeviceId) return
    this.lastConnectedDeviceId = deviceId
    await prefWrite(this.lastHostKey(), deviceId).catch(() => { this.notice = '连接已建立，但未能保存启动偏好。' })
  }

  private async loadCatalog(): Promise<void> {
    const generation = this.generation
    this.requireConnected()
    const [workspaces, sessions] = await Promise.all([this.connection.requireProxy().workspaceList(), this.connection.requireProxy().sessionList()])
    const nextWorkspaces: WorkspaceView[] = workspaces.items.map(w => ({ ...w, backend: 'harness' as const }))
    const nextSessions: RemoteSession[] = sessions.map(s => ({ ...s, backend: 'harness' as const }))
    this.archived = Array.isArray(workspaces.archivedSessionIds) ? workspaces.archivedSessionIds : []
    const optional: string[] = []
    const append = (catalog: { workspaces: WorkspaceView[]; sessions: RemoteSession[] }) => { nextWorkspaces.push(...catalog.workspaces); nextSessions.push(...catalog.sessions) }
    if (this.connection.hasCodex()) { try { append(await loadCodexCatalog(this.connection.requireCodex())) } catch { optional.push('CodeX') } }
    for (const backend of ['pi', 'claude', 'opencode', 'antigravity', 'cursor', 'hermes'] as const) {
      const available = {
        pi: this.connection.hasPi?.() ?? false,
        claude: this.connection.hasClaude?.() ?? false,
        opencode: this.connection.hasOpencode?.() ?? false,
        antigravity: this.connection.hasAntigravity?.() ?? false,
        cursor: this.connection.hasCursor?.() ?? false,
        hermes: this.connection.hasHermes?.() ?? false,
      }[backend]
      if (!available) continue
      try {
        const client = this.acp(backend)
        if (backend === 'hermes') append(await loadHermesCatalog(client, this.registeredWorkspaces))
        else if (backend === 'pi') append(await loadPiCatalog(client))
        else if (backend === 'claude') append(await loadClaudeCatalog(client))
        else if (backend === 'opencode') append(await loadOpencodeCatalog(client))
        else if (backend === 'antigravity') append(await loadAntigravityCatalog(client))
        else {
          for (const root of await client.listWorkspaces('cursor')) {
            const workspace = createCursorWorkspace(root.path, root.title)
            for (const row of await client.listSessions(root.path, 'cursor')) {
              const session = createCursorSession({ acpSessionId: row.conversationId, cwd: root.path, title: row.title })
              workspace.sessionIds.push(session.sessionId); nextSessions.push(session)
            }
            nextWorkspaces.push(workspace)
          }
        }
      } catch { optional.push(backend) }
    }
    this.requireConnected()
    if (generation !== this.generation) throw new Error('连接已切换，请刷新。')
    for (const workspace of this.registeredWorkspaces) if (!nextWorkspaces.some(row => row.workspaceId === workspace.workspaceId)) nextWorkspaces.push(workspace)
    this.pinned = Array.isArray(workspaces.pinnedSessionIds) ? workspaces.pinnedSessionIds : []
    this.workspaces = nextWorkspaces; this.sessions = nextSessions
    if (this.workspace) this.workspace = nextWorkspaces.find(row => row.workspaceId === this.workspace!.workspaceId)
    if (!nextWorkspaces.some(w => (w.backend ?? 'harness') === this.backend) && !nextSessions.some(s => (s.backend ?? 'harness') === this.backend)) this.backend = 'harness'
    this.notice = optional.length ? `${optional.join('、')} 目录加载失败，可刷新重试。` : ''
  }
  /** The Host inbox is the only queue source here: this client sends prompts straight through. */
  private queueItems(session: RemoteSession): QueueRow[] {
    const inbox = (session.projections?.values as Record<string, unknown> | undefined)?.inbox
    return inboxQueuedItems(inbox).map(item => ({ id: item.id ?? '', preview: item.preview, host: true }))
  }
  private async toggleGroup(id: string): Promise<void> {
    if (!id) return
    this.collapsed = this.collapsed.includes(id) ? this.collapsed.filter(row => row !== id) : [...this.collapsed, id]
    this.saveViewPrefs()
  }
  private backendTabs(): BackendTab[] {
    const names: Record<string, string> = { harness: 'DSH', codex: 'CodeX', opencode: 'OpenCode', cursor: 'Cursor', pi: 'Pi', claude: 'Claude', antigravity: 'Antigravity', hermes: 'Hermes' }
    const counts = new Map<string, number>()
    for (const workspace of this.workspaces) {
      const id = workspace.backend ?? 'harness'
      counts.set(id, (counts.get(id) ?? 0) + workspace.sessionIds.length)
    }
    for (const session of this.sessions) {
      const id = session.backend ?? 'harness'
      if (!this.workspaces.some(w => w.sessionIds.includes(session.sessionId))) counts.set(id, (counts.get(id) ?? 0) + 1)
    }
    const order = ['harness', 'codex', 'opencode', 'cursor', 'pi', 'claude', 'antigravity', 'hermes']
    return order.filter(id => counts.has(id)).map(id => ({ id, name: names[id] ?? id, count: counts.get(id) ?? 0 }))
  }
  /** Workspaces in the order the drawer shows them: favorites first, then the chosen sort. */
  private backendWorkspaces(): WorkspaceView[] {
    const rows = this.workspaces.filter(w => (w.backend ?? 'harness') === this.backend)
    const newest = (workspace: WorkspaceView): number => workspace.sessionIds
      .map(id => this.sessions.find(s => s.sessionId === id)?.updatedAt ?? 0)
      .reduce((left, right) => Math.max(left, right), 0)
    const ranked = this.orderBy === 'updated'
      ? [...rows].sort((a, b) => newest(b) - newest(a) || a.title.localeCompare(b.title))
      : [...rows]
    const favorite = (workspace: WorkspaceView) => this.favorites.includes(workspace.workspaceId) ? 0 : 1
    return ranked.sort((a, b) => favorite(a) - favorite(b))
  }
  private overviewRows(archived: Set<string>, grouping = this.groupBy): OverviewRow[] {
    const workspaceOf = (groupId: string): string => {
      const prefix = `workspace:${this.backend}:`
      const id = groupId.startsWith(prefix) ? groupId.slice(prefix.length) : ''
      return id === 'unfiled' ? '' : id
    }
    let list = this.sessions.filter(s => (s.backend ?? 'harness') === this.backend)
    const active = this.session
    if (active && !list.some(s => s.sessionId === active.sessionId)) list = [active, ...list]
    if (this.archiveFilter === 'hidden') list = list.filter(s => !archived.has(s.sessionId))
    else if (this.archiveFilter === 'only') list = list.filter(s => archived.has(s.sessionId))
    list = [...list].sort((a,b) => Number(this.pinned.includes(b.sessionId)) - Number(this.pinned.includes(a.sessionId)) || (this.orderBy === 'updated' ? b.updatedAt - a.updatedAt : 0))
    const row = (session: RemoteSession, hidden: boolean): OverviewRow => ({
      id: session.sessionId, kind: 'session', target: session.sessionId, name: sessionName(session),
      description: archived.has(session.sessionId) ? '已归档' : dayOf(session.updatedAt),
      meta: `${session.backend ?? 'harness'}${session.running ? ' · 回复中' : ''}`,
      favorite: false, expanded: false, remaining: 0, hidden,
      selected: active?.sessionId === session.sessionId,
    })
    const header = (id: string, name: string, description: string, meta: string, expanded: boolean, favorite: boolean, target: string): OverviewRow =>
      ({ id, kind: 'group', target, name, description, meta, favorite, expanded, remaining: 0, hidden: false, selected: false })
    const rows: OverviewRow[] = []
    if (grouping === 'list') {
      rows.push(header('group:all', '全部会话', '', `${list.length} 条`, true, false, ''))
      for (const session of list) rows.push(row(session, false))
      return rows
    }
    const byId = new Map(list.map(s => [s.sessionId, s] as [string, RemoteSession]))
    const recent = this.recents.map(id => byId.get(id)).filter((s): s is RemoteSession => s !== undefined).slice(0, RECENT_LIMIT)
    if (recent.length > 0) {
      const id = `recent:${this.backend}`
      const expanded = !this.collapsed.includes(id)
      rows.push(header(id, '最近访问', '', `${recent.length} 条`, expanded, false, ''))
      if (expanded) for (const session of recent) rows.push(row(session, false))
    }
    const workspaces = this.backendWorkspaces()
    const claimed = new Set(workspaces.flatMap(w => w.sessionIds))
    const groups: Array<{ id: string; name: string; description: string; members: RemoteSession[]; favorite: boolean }> = workspaces.map(w => ({
      id: `workspace:${this.backend}:${w.workspaceId}`, name: w.title || w.path, description: w.path,
      members: list.filter(s => w.sessionIds.includes(s.sessionId)), favorite: this.favorites.includes(w.workspaceId),
    }))
    const loose = list.filter(s => !claimed.has(s.sessionId))
    if (loose.length > 0) groups.push({ id: `workspace:${this.backend}:unfiled`, name: '未分组', description: '', members: loose, favorite: false })
    for (const group of groups) {
      const expanded = !this.collapsed.includes(group.id)
      const limit = this.visibleCounts[group.id] ?? SESSION_PAGE_SIZE
      rows.push(header(group.id, group.name, group.description, `${group.members.length} 条`, expanded, group.favorite, workspaceOf(group.id)))
      if (!expanded) continue
      group.members.forEach((session, index) => rows.push(row(session, index >= limit)))
      const remaining = Math.max(0, group.members.length - limit)
      if (remaining > 0) rows.push({ id: `more:${group.id}`, kind: 'more', target: group.id, name: `展开剩余 ${remaining} 个会话`, description: '', meta: '', favorite: false, expanded: true, remaining, hidden: false, selected: false })
    }
    return rows
  }
  private async toggleFavorite(id: string): Promise<void> {
    if (!id) return
    this.favorites = this.favorites.includes(id) ? this.favorites.filter(row => row !== id) : [...this.favorites, id]
    this.saveViewPrefs()
    this.publish()
  }
  private async archiveSession(id: string): Promise<void> {
    this.requireConnected()
    const session = this.sessions.find(s => s.sessionId === id)
    if (!session) throw new Error('会话不存在，请刷新工作区。')
    const active = this.session?.sessionId === id
    if (!session.backend || session.backend === 'harness') {
      // The mutation returns the complete Host-confirmed archive set; catalog
      // membership stays, the filter hides the row.
      this.archived = await this.connection.requireProxy().workspaceArchiveSession(id)
    } else if (session.backend === 'opencode') {
      await this.acp('opencode').archiveSession(session.nativeId ?? id.split(':').slice(1).join(':'), 'opencode')
      this.sessions = this.sessions.filter(s => s.sessionId !== id)
      for (const workspace of this.workspaces) workspace.sessionIds = workspace.sessionIds.filter(row => row !== id)
    } else throw new Error('此后端暂不支持归档。')
    if (active) {
      if (this.stream) await this.stream.close(); this.stream = undefined
      this.session = undefined; this.messages = []; this.codexState = undefined; this.models = undefined
      ++this.selection; this.view = 'workspaces'
    }
    this.notice = '已归档，可在视图选项的「仅已归档」中查看。'
  }
  private async forkMessage(id: string): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    if (session.backend && session.backend !== 'harness') throw new Error('此后端暂不支持分支。')
    const item = this.messages.find(row => row.id === id)
    if (!item || item.kind !== 'message') throw new Error('只能从消息处分支。')
    const seq = item.nativeSeq
    if (item.streaming || seq === undefined || !Number.isSafeInteger(seq) || seq < 0) throw new Error('这条消息没有可分支的持久边界。')
    const proxy = this.connection.requireProxy()
    const { sessionId } = await proxy.sessionFork(session.sessionId, seq)
    const [rows, list] = await Promise.all([proxy.sessionList(), proxy.workspaceList()])
    const created = rows.find(row => row.sessionId === sessionId)
    if (!created) throw new Error('主机未确认分支会话。')
    this.sessions.unshift({ ...created, backend: 'harness' as const })
    this.archived = list.archivedSessionIds
    const owner = this.workspaces.find(w => w.sessionIds.includes(session.sessionId))
    if (owner && !owner.sessionIds.includes(sessionId)) owner.sessionIds.unshift(sessionId)
    this.notice = '已创建分支会话。'
    await this.openSession(sessionId)
  }
  private async rateMessage(id: string, rating: string): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    if (session.backend && session.backend !== 'harness') throw new Error('此后端暂不支持评价。')
    if (rating !== 'positive' && rating !== 'negative') throw new Error('只支持点赞或点踩。')
    const item = this.messages.find(row => row.id === id)
    if (!item || item.kind !== 'message' || item.streaming) throw new Error('这条消息还不能评价。')
    const saved = await this.connection.requireProxy().messageFeedbackPut(session.sessionId, id, rating)
    // Only the read-back value changes the icon, matching Android's write-then-verify rule.
    this.feedbackByMessage.set(id, saved.rating)
    this.publish()
  }
  /** Loads the mode and permission rosters for the 更多操作 panel; either may be unavailable. */
  private async loadPanel(): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    this.panelWarning = ''
    if (session.backend && session.backend !== 'harness') {
      this.modes = []; this.permissions = []
      this.panelWarning = '此后端不提供模式与操作权限预设。'
      return
    }
    const proxy = this.connection.requireProxy()
    const jobs: Array<Promise<void>> = [
      proxy.agentPresetList().then(roster => {
        this.modes = roster.presets.map(row => ({
          id: row.id, name: row.name ?? row.id, description: row.description ?? '',
          current: (session.agentPreset ?? '') === row.id, broken: row.broken !== undefined,
        }))
      }).catch(() => { this.panelWarning = '模式列表加载失败，请重新打开「更多操作」重试。' }),
    ]
    const projected = sessionPermissions(session)
    const currentPermission = projected?.currentValue ?? ''
    const fromProjection = (options: Array<{ value: string; name: string; description?: string }>): PresetRow[] => options.map(option =>
      ({ id: option.value, name: option.name, description: option.description ?? '', current: option.value === currentPermission, broken: false }))
    this.permissions = projected === undefined ? [] : fromProjection(projected.options)
    jobs.push(this.connection.requireSessionTools(session.sessionId).permissionOptions().then(options => {
      this.permissions = fromProjection(options)
    }).catch(() => { if (this.permissions.length === 0) this.panelWarning = '操作权限列表暂不可用。' }))
    await Promise.allSettled(jobs)
  }
  /** The Host skill catalog backs the slash panel; ACP backends publish none. */
  private async loadSkills(): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    const tools = this.connection.requireSessionTools(session.sessionId)
    const rows = await tools.listSkills(session.sessionId)
    this.skills = rows.map(row => ({ id: row.name, name: row.name, description: row.description }))
    if (this.skills.length === 0) this.panelWarning = '这台主机没有可用的 Slash 命令。'
  }
  /** One slash line goes through the Host command dispatcher; the reply is a notice, never a chat row. */
  private async runCommand(line: string): Promise<void> {
    this.requireConnected()
    const session = this.session
    const text = line.trim()
    if (!session || !text) throw new Error('请先打开会话。')
    if (!text.startsWith('/')) throw new Error('Slash 命令需要以 / 开头。')
    const result = await this.connection.requireSessionTools(session.sessionId).executeCommand(session.sessionId, text)
    if (result.kind === 'error') throw new Error(result.text ?? '命令执行失败。')
    this.notice = result.text ?? `已执行 ${text}`
  }
  /** Read-only workspace tree; the Host resolves `.` as the session root. */
  private async listFiles(path: string): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    const directory = await this.connection.requireSessionTools(session.sessionId).listFiles(session.sessionId, path)
    this.filePath = directory.path
    this.filePreview = undefined
    this.files = directory.entries
      .slice()
      .sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'directory' ? -1 : b.type === 'directory' ? 1 : 0))
      .map(entry => ({
        id: entry.name, name: entry.name, kind: entry.type,
        size: entry.type === 'file' && entry.size !== undefined ? group(entry.size) : '',
      }))
    if (directory.truncated) this.panelWarning = '目录条目过多，仅显示一部分。'
  }
  /** Preview workspace text, images, PDFs, and Office documents converted by the Host. */
  private async previewFile(path: string, offset = 1): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session || !path) throw new Error('请选择文件。')
    const tools = this.connection.requireSessionTools(session.sessionId)
    const kind = classifyWorkspaceFile(path)
    const name = path.split('/').pop() ?? path
    if (kind === 'text') {
      const text = await tools.readFile(session.sessionId, path, offset)
      this.filePreview = {
        path: text.absolutePath, name, kind: 'text',
        text: text.text, lines: text.lines, eof: text.eof,
        data: '', mimeType: 'text/plain', missingFonts: [], error: '', offset: text.offset,
      }
    } else if (kind === 'image' || kind === 'pdf' || kind === 'office') {
      try {
        const preview = await loadWorkspacePreview(tools, session.sessionId, path, kind)
        this.filePreview = {
          path, name, kind,
          text: '', lines: 0, eof: true,
          data: preview.data, mimeType: preview.mimeType, missingFonts: preview.missingFonts,
          error: '', offset: 1,
        }
      } catch (err) {
        this.filePreview = {
          path, name, kind,
          text: '', lines: 0, eof: true,
          data: '', mimeType: '', missingFonts: [],
          error: sessionToolsError(err), offset: 1,
        }
      }
    } else {
      this.filePreview = {
        path, name, kind: 'unsupported',
        text: '', lines: 0, eof: true,
        data: '', mimeType: '', missingFonts: [],
        error: '此文件类型暂不支持在移动端直接预览。', offset: 1,
      }
    }
  }
  /** Interactive Terminal: manages remote terminals, follow stream, and shortcut keys. */
  private async openTerminal(): Promise<void> {
    this.requireConnected()
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    this.terminalBusy = true
    this.terminalError = ''
    this.publish()
    try {
      const tools = this.connection.requireSessionTools(session.sessionId)
      const list = await tools.listTerminals(session.sessionId)
      this.terminals = list
      if (list.length === 0) {
        await this.createTerminalInternal()
      } else {
        const targetId = (this.activeTerminalId && list.some(t => t.id === this.activeTerminalId))
          ? this.activeTerminalId
          : list[0].id
        this.activeTerminalId = targetId
        await this.attachTerminal(targetId)
      }
    } catch (err) {
      this.terminalError = sessionToolsError(err)
    } finally {
      this.terminalBusy = false
      this.publish()
    }
  }

  private async createTerminalInternal(): Promise<void> {
    const session = this.session
    if (!session) throw new Error('请先打开会话。')
    const tools = this.connection.requireSessionTools(session.sessionId)
    const env = await tools.terminalEnvironment(session.sessionId)
    this.terminalLimits = env
    const id = createNativeRpcId()
    const cols = Math.min(this.terminalDimensions.cols, env.maxCols)
    const rows = Math.min(this.terminalDimensions.rows, env.maxRows)
    const created = await tools.createTerminal(session.sessionId, id, cols, rows)
    this.terminals = [...this.terminals.filter(t => t.id !== created.id), created]
    this.activeTerminalId = created.id
    await this.attachTerminal(created.id)
  }

  private async createTerminal(): Promise<void> {
    this.requireConnected()
    this.terminalBusy = true
    this.terminalError = ''
    this.publish()
    try {
      await this.createTerminalInternal()
    } catch (err) {
      this.terminalError = sessionToolsError(err)
    } finally {
      this.terminalBusy = false
      this.publish()
    }
  }

  private async selectTerminal(id: string): Promise<void> {
    if (this.activeTerminalId === id && this.terminalAttachment) return
    this.activeTerminalId = id
    this.terminalBusy = true
    this.terminalError = ''
    this.publish()
    try {
      await this.attachTerminal(id)
    } catch (err) {
      this.terminalError = sessionToolsError(err)
    } finally {
      this.terminalBusy = false
      this.publish()
    }
  }

  setTerminalRenderer(scope: string, enabled: boolean): void {
    if (enabled && scope !== this.sessionKey() + '/' + this.activeTerminalId) return
    if (!enabled && scope !== this.terminalRendererScope) return
    if (!enabled || scope !== this.terminalRendererScope) {
      const pending = this.terminalRenderPending
      this.terminalRenderPending = undefined
      if (pending) { clearTimeout(pending.timer); pending.resolve() }
    }
    this.terminalRendererScope = enabled ? scope : ''
  }
  acknowledgeTerminalRender(scope: string, revision: number): void {
    const pending = this.terminalRenderPending
    if (!pending || pending.scope !== scope || pending.revision !== revision) return
    this.terminalRenderPending = undefined
    clearTimeout(pending.timer); pending.resolve()
  }
  private async attachTerminal(id: string): Promise<void> {
    this.setTerminalRenderer(this.terminalRendererScope, false)
    this.terminalAttachment?.dispose()
    this.terminalAttachment = undefined
    this.terminalRaw = ''; this.terminalChunk = ''; this.terminalReset = true; ++this.terminalRenderRevision; this.terminalScreen = ''
    this.terminalWritable = false
    this.terminalStatus = '正在连接终端…'
    this.terminalError = ''
    this.publish()

    const session = this.session
    if (!session) return
    const tools = this.connection.requireSessionTools(session.sessionId)
    const env = await tools.terminalEnvironment(session.sessionId)
    this.terminalLimits = env

    let applied = false
    const attachment = new TerminalAttachment(
      tools,
      session.sessionId,
      id,
      env.maxInputBytes,
      async (data: string, reset: boolean): Promise<void> => {
        if (this.activeTerminalId !== id || this.terminalAttachment !== attachment) return
        this.terminalChunk = data; this.terminalReset = reset
        this.terminalRaw = (reset ? data : this.terminalRaw + data).slice(-1024 * 1024)
        const cleaned = cleanTerminalText(data)
        if (reset) {
          this.terminalScreen = cleaned
        } else {
          this.terminalScreen += cleaned
        }
        if (this.terminalScreen.length > 60000) {
          this.terminalScreen = this.terminalScreen.slice(-40000)
        }
        const revision = ++this.terminalRenderRevision, scope = this.sessionKey() + '/' + id
        const rendered = scope === this.terminalRendererScope ? new Promise<void>((resolve, reject) => {
          const timer = setTimeout(() => {
            if (this.terminalRenderPending?.revision === revision) this.terminalRenderPending = undefined
            reject(new Error('Terminal render timeout'))
          }, 10000)
          this.terminalRenderPending = { scope, revision, resolve, reject, timer }
        }) : Promise.resolve()
        this.publish()
        await rendered
      },
      (info: TerminalInfo, canWrite: boolean): void => {
        if (this.activeTerminalId !== id || this.terminalAttachment !== attachment) return
        const idx = this.terminals.findIndex(t => t.id === id)
        if (idx >= 0) {
          this.terminals[idx] = info
        }
        this.terminalWritable = canWrite
        if (canWrite) {
          this.terminalStatus = ''
          if (!applied) {
            applied = true
            void attachment.resize(
              Math.min(this.terminalDimensions.cols, env.maxCols),
              Math.min(this.terminalDimensions.rows, env.maxRows)
            ).catch(e => {
              this.terminalError = sessionToolsError(e)
              this.publish()
            })
          }
        } else {
          applied = false
          this.terminalStatus = info.state === 'running'
            ? '当前终端输入权已被其他连接接管，请重新打开终端。'
            : '终端已结束'
        }
        this.publish()
      }
    )
    this.terminalAttachment = attachment
    void attachment.follow().catch(err => {
      if (this.activeTerminalId !== id || this.terminalAttachment !== attachment) return
      this.terminalWritable = false
      this.terminalError = sessionToolsError(err)
      this.publish()
    })
  }

  private async writeTerminal(data: string): Promise<void> {
    if (!data) return
    const attachment = this.terminalAttachment
    if (!this.terminalWritable || !attachment) return
    await attachment.write(data).catch(() => {
      if (this.terminalAttachment !== attachment) return
      this.terminalWritable = false
      this.terminalError = '终端连接已断开；输入不会自动重发。'
      this.publish()
    })
  }

  private async closeTerminal(): Promise<void> {
    const id = this.activeTerminalId
    if (!id) return
    this.setTerminalRenderer(this.terminalRendererScope, false)
    this.terminalAttachment?.dispose()
    this.terminalAttachment = undefined
    const remaining = this.terminals.filter(t => t.id !== id)
    this.terminals = remaining
    const session = this.session
    if (session) {
      void this.connection.requireSessionTools(session.sessionId).closeTerminal(session.sessionId, id)
        .catch(e => { this.terminalError = sessionToolsError(e); this.publish() })
    }
    if (remaining.length > 0) {
      this.activeTerminalId = remaining[0].id
      await this.attachTerminal(this.activeTerminalId)
    } else {
      this.activeTerminalId = undefined
      this.terminalScreen = ''
      this.terminalWritable = false
      this.terminalStatus = ''
      this.terminalError = ''
      this.publish()
    }
  }
  private async toggleCompactHistory(): Promise<void> {
    this.requireConnected()
    const next = !this.compactHistory
    await this.connection.configureHistory(next)
    this.compactHistory = next
    await prefWrite(this.compactKey(), JSON.stringify({ value: next }))
    this.notice = next ? '已开启紧凑历史。' : '已关闭紧凑历史。'
  }
  /** Subagent children only; forks carry a parent but are ordinary conversations. */
  private childRows(): CatalogRow[] {
    const session = this.session
    if (session === undefined) return []
    return this.sessions
      .filter(item => isSubagentSession(item) && item.parentSessionId === session.sessionId)
      .map(item => ({
        id: item.sessionId, name: resolveSessionDisplayTitle(item) ?? item.title ?? '子任务',
        description: item.running ? '回复中' : '子任务', favorite: false, backend: item.backend ?? 'harness', count: 0, archived: false,
      }))
  }
  private async loadInfo(): Promise<void> {
    const session = this.session
    if (!session) { this.info = []; this.publish(); return }
    const workspace = this.workspaces.find(item => item.sessionIds.includes(session.sessionId))
    const backend = workspace?.backend ?? session.backend ?? 'harness'
    const rows: InfoRow[] = [
      { label: '会话', value: sessionName(session) },
      { label: '工作区', value: workspace?.title ?? '未分组' },
      { label: '主机', value: this.host?.name ?? '不可用' },
      { label: '后端', value: backend },
      { label: '工作区目录', value: workspace?.path ?? '不可用' },
    ]
    if (session.cwd !== undefined && session.cwd !== workspace?.path) rows.push({ label: '会话目录', value: session.cwd })
    if (workspace !== undefined) rows.push({ label: '工作区会话数', value: group(workspace.sessionIds.length) })
    rows.push({ label: '更新时间', value: dayOf(session.updatedAt) })
    this.info = rows
    await this.loadNetworkDetails()
  }
  /** Host network & link diagnostics: ICE, RTT, bitrate, endpoints and crypto details. */
  private async loadNetworkDetails(): Promise<void> {
    const stats = this.connection.getStats()
    const details = await this.connection.getNetworkDetails().catch(() => undefined)
    const sections: NetworkSection[] = []

    // 1. 安全连接
    const prefText = this.transportPreference === 'relay' ? '仅控制转发'
      : this.transportPreference === 'turn' ? '仅穿透中继'
      : '自动优选 (LAN/P2P 直连优先)'
    const probeOrderText = this.transportPreference === 'relay' ? 'Relay'
      : this.transportPreference === 'turn' ? 'TURN → Relay'
      : 'LAN → P2P → TURN → Relay'
    const secureRows: NetworkRow[] = [
      { label: '连接方式', value: connectionPath(stats?.mode) },
      { label: '传输策略', value: prefText },
      { label: '探测顺序', value: probeOrderText },
      { label: '安全保护', value: 'Noise IK · ChaCha20-Poly1305' },
    ]
    if (details?.controlChannelUrl) {
      secureRows.push({ label: '控制信令服务器', value: controlServerName(details.controlChannelUrl), mono: true })
    }
    sections.push({ title: '安全连接', rows: secureRows })

    // 2. 链路与网络详情
    const netRows: NetworkRow[] = []
    const rtt = details?.webRtc?.currentRoundTripTimeMs ?? stats?.rttMs
    if (rtt !== undefined) {
      netRows.push({ label: '往返延迟 (RTT)', value: `${Math.round(rtt)} ms` })
    }
    if (details?.webRtc?.availableOutgoingBitrate !== undefined) {
      netRows.push({ label: '可用上行带宽', value: formatBitrate(details.webRtc.availableOutgoingBitrate) })
    }
    if (details?.webRtc?.protocol !== undefined) {
      netRows.push({ label: '网络协议', value: protocolText(details.webRtc.protocol, details.webRtc.relayProtocol) })
    }
    if (details?.webRtc) {
      netRows.push({
        label: '候选路径',
        value: candidatePathText(details.webRtc.localCandidateType, details.webRtc.localAddressScope, details.webRtc.remoteCandidateType, details.webRtc.remoteAddressScope),
      })
      netRows.push({ label: '手机端点', value: details.webRtc.localAddress ?? '服务器转发未公开', mono: !!details.webRtc.localAddress })
      netRows.push({ label: '电脑端点', value: details.webRtc.remoteAddress ?? '服务器转发未公开', mono: !!details.webRtc.remoteAddress })
    } else {
      netRows.push({ label: '手机端点', value: '服务器转发未公开' })
      netRows.push({ label: '电脑端点', value: '服务器转发未公开' })
    }
    const connectedAt = details?.connectedAt
    if (connectedAt) {
      netRows.push({ label: '连接时间', value: new Date(connectedAt).toLocaleString() })
    }
    const sent = details?.webRtc?.bytesSent ?? stats?.bytesSent ?? 0
    const received = details?.webRtc?.bytesReceived ?? stats?.bytesReceived ?? 0
    if (sent > 0 || received > 0) {
      netRows.push({ label: '本次流量', value: `${formatBytes(sent)} 发送 · ${formatBytes(received)} 接收` })
    }
    sections.push({ title: '网络详情', rows: netRows })

    this.networkSections = sections
    this.publish()
  }
  /** The Host plugin inventory, joined with live entries and settings forms. */
  private async loadPlugins(): Promise<void> {
    this.requireConnected()
    const proxy = this.connection.requireProxy()
    let bundles: unknown[]
    let plugins: unknown[]
    let settings: HarnessSettingsDescribe
    try {
      [bundles, plugins, settings] = await Promise.all([
        proxy.pluginListBundles(), proxy.pluginListPlugins(),
        proxy.settingsDescribe().catch((): HarnessSettingsDescribe => ({ writable: false, namespaces: [] })),
      ])
    } catch (error) {
      // An older Host rejects the plugin-manager endpoints outright; show the same
      // upgrade guidance Android does instead of the raw gateway error.
      throw new Error(sessionToolsError(error))
    }
    this.pluginViews = joinInventory(bundles, plugins, settings, harmonyAdaptedPlugins())
    this.settingsWritable = settings.writable
    const rows: PluginRow[] = []
    for (const section of PLUGIN_SECTIONS) {
      const items = this.pluginViews.filter((view: PluginBundleView) => view.category === section.category)
      if (items.length === 0) continue
      rows.push({
        id: `section:${section.category}`, level: 'section', parent: '', name: section.title(),
        description: section.hint(), category: section.category, enabled: false, available: true,
        readOnly: true, official: false, version: '', error: '', feature: '', upgrade: '', form: '',
      })
      for (const view of items) {
        rows.push({
          id: view.name, level: 'bundle', parent: '', name: view.title, description: view.description ?? '',
          category: view.category, enabled: view.enabled, available: view.available, official: view.official,
          readOnly: view.readOnly || (!view.available && !view.enabled), version: view.version ?? '',
          error: view.error ?? '', feature: view.remoteFeature ?? '', upgrade: view.upgradeFor ?? '', form: '',
        })
        for (const entry of view.rows) {
          rows.push({
            id: entry.entryId === undefined ? '' : `row:${entry.entryId}`, level: 'component', parent: view.title,
            name: entry.title, description: entry.description ?? entry.moduleName, category: view.category,
            enabled: entry.enabled, available: view.available, official: false,
            readOnly: entry.readOnly || !view.enabled, version: '', error: '', feature: '', upgrade: '',
            form: entry.settings === undefined || entry.entryId === undefined ? '' : entry.entryId,
          })
        }
      }
    }
    this.pluginRows = rows
    this.publish()
  }
  /** `restart-required`, `overridden` and `cancelled` each read differently on a phone. */
  private async togglePlugin(id: string, enabled: boolean): Promise<void> {
    this.requireConnected()
    if (id === '') throw new Error(strings.plugins.toggleFailed)
    const entry = id.startsWith('row:')
    const result = await this.connection.requireProxy()
      .pluginSetEnabled(entry ? 'plugin' : 'bundle', entry ? id.slice(4) : id, enabled)
    await this.loadPlugins()
    this.notice = result.application === 'restart-required' ? strings.plugins.restartRequired
      : result.application === 'overridden' ? strings.plugins.overridden
        : result.application === 'cancelled' ? strings.plugins.cancelled
          : enabled ? strings.plugins.enabledLabel : strings.plugins.disabledLabel
  }
  /** One settings namespace per Loader entry, read at a revision and written back against it. */
  private async openPluginForm(entryId: string): Promise<void> {
    this.requireConnected()
    const entry = this.pluginViews.flatMap(view => view.rows).find(item => item.entryId === entryId)
    const form = entry?.settings
    if (entry === undefined || form === undefined) throw new Error(strings.plugins.noSettings)
    this.formEntry = entryId
    this.formNs = form.ns
    this.formRevision = form.revision
    this.formTitle = entry.title
    this.formFields = schemaFields(form.schema)
    const current = (form.value ?? {}) as Record<string, unknown>
    const user = (form.user ?? {}) as Record<string, unknown>
    // Only the keys the person set over the composition defaults can be unset again.
    this.formOverridden = this.formFields
      .filter(field => Object.prototype.hasOwnProperty.call(user, field.key))
      .map(field => field.key)
    this.formRows = this.formFields.map((field: SchemaField): FormRow => ({
      key: field.key, kind: field.kind,
      value: fieldText(current[field.key] ?? field.defaultValue, field),
      description: field.description ?? field.key,
      bounds: [field.min === undefined ? '' : `≥ ${field.min}`, field.max === undefined ? '' : `≤ ${field.max}`,
        field.defaultValue === undefined ? '' : `${strings.plugins.defaultValue} ${String(field.defaultValue)}`]
        .filter(part => part !== '').join(' · '),
      secret: field.secret === true,
    }))
    this.publish()
  }
  private async savePluginForm(text: string): Promise<void> {
    this.requireConnected()
    if (!this.settingsWritable) throw new Error(strings.plugins.settingsReadOnly)
    let edits: Record<string, string> = {}
    try { edits = JSON.parse(text === '' ? '{}' : text) as Record<string, string> } catch { throw new Error(strings.plugins.saveFailed) }
    const ops: HarnessSettingsPathOp[] = []
    for (const row of this.formRows) {
      const next = edits[row.key]
      // Fields the phone cannot render stay untouched, exactly as on Android.
      if (next === undefined || next === row.value || row.kind === 'unsupported') continue
      if (row.kind === 'number') {
        const field = this.formFields.find(item => item.key === row.key)
        const value = Number(next.trim())
        if (next.trim() === '' || !Number.isFinite(value)
          || (field?.integer === true && !Number.isInteger(value))
          || (field?.min !== undefined && value < field.min)
          || (field?.max !== undefined && value > field.max)) throw new Error(strings.plugins.invalidNumber)
      }
      ops.push({ op: 'set', path: [row.key], value: fieldValue(row.kind, next) })
    }
    if (ops.length === 0) { this.notice = strings.plugins.saved; return }
    await this.connection.requireProxy().settingsMutate(this.formNs, ops, this.formRevision)
    this.notice = strings.plugins.saved
    // The Host bumps the namespace revision on write, so the form is read back.
    await this.loadPlugins()
    await this.openPluginForm(this.formEntry)
  }
  /** Unsetting the overridden keys restores the composition defaults. */
  private async resetPluginForm(): Promise<void> {
    this.requireConnected()
    if (!this.settingsWritable) throw new Error(strings.plugins.settingsReadOnly)
    if (this.formOverridden.length === 0) { this.notice = strings.plugins.saved; return }
    const ops: HarnessSettingsPathOp[] = this.formOverridden.map((key): HarnessSettingsPathOp => ({ op: 'unset', path: [key] }))
    await this.connection.requireProxy().settingsMutate(this.formNs, ops, this.formRevision)
    this.notice = strings.plugins.saved
    await this.loadPlugins()
    await this.openPluginForm(this.formEntry)
  }
  /** Automation tasks: the Host schedule catalog, nearest planned run first. */
  private activityRows(): Array<{ id: string; category: string; title: string; detail: string; status: string; session: string }> {
    const values = (this.session?.projections?.values ?? {}) as Record<string, unknown>
    const rows: Array<{ id: string; category: string; title: string; detail: string; status: string; session: string }> = []
    const object = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
    if (Array.isArray(values.todos)) values.todos.forEach((raw,index) => {
      const row = object(raw)
      if (typeof row.content === 'string') rows.push({id:`todo:${index}`,category:'todos',title:row.content,detail:'',status:text(row.status),session:''})
    })
    const projection = object(values.goal), goal = object(projection.goal)
    if (typeof goal.objective === 'string') rows.push({id:'goal',category:'goal',title:goal.objective,detail:text(object(goal.blockedReason).message),status:text(goal.phase),session:''})
    const team = object(values.agentTeam)
    if (Array.isArray(team.members)) for (const raw of team.members) {
      const row = object(raw)
      rows.push({id:text(row.id),category:'team',title:text(row.name)||text(row.id),detail:text(row.description)||text(row.error),status:text(row.phase),session:text(row.id)})
    }
    if (Array.isArray(team.tasks)) for (const raw of team.tasks) {
      const row=object(raw)
      rows.push({id:text(row.id),category:'team',title:text(row.subject),detail:text(row.description),status:text(row.status),session:text(row.ownerId)})
    }
    for (const row of this.childRows()) rows.push({id:row.id,category:'subagents',title:row.name,detail:row.description,status:'',session:row.id})
    return rows
  }
  private async manageSession(id: string, operation: string, name: string): Promise<void> {
    this.requireConnected()
    const target = this.sessions.find(row => row.sessionId === id)
    if (!target || (target.backend ?? 'harness') !== 'harness') throw new Error('当前后端不支持此会话操作。')
    const generation = this.generation, proxy = this.connection.requireProxy()
    if (operation === 'pin') await proxy.workspacePinSession(id)
    else if (operation === 'unpin') await proxy.workspaceUnpinSession(id)
    else if (operation === 'unarchive') await proxy.workspaceUnarchiveSession(id)
    else if (operation === 'rename') { if (!name.trim()) throw new Error('请输入名称。'); await proxy.sessionRename(id, name.trim()) }
    else if (operation === 'fork') {
      const result = await proxy.sessionFork(id)
      if (generation !== this.generation) return
      await this.loadCatalog(); await this.openSession(result.sessionId); return
    } else throw new Error('未知会话操作。')
    if (generation === this.generation) await this.loadCatalog()
  }
  private hostDirectory: { path: string; parent?: string; entries: Array<{ name: string; path: string }> } = { path: '', entries: [] }
  private async browseHostDirectory(path: string): Promise<void> {
    this.requireConnected(); const generation = this.generation
    const result = await this.connection.requireProxy().hostListDirectory(path || undefined)
    if (generation === this.generation) this.hostDirectory = result
  }
  private async saveTask(raw: string): Promise<void> {
    this.requireConnected()
    const input = JSON.parse(raw) as { id?: string; session: string; request: ScheduleCreateRequest; change?: ScheduleTimingChange }
    const proxy = this.connection.requireProxy(), generation = this.generation
    if (input.id) {
      const entry = this.scheduleEntries.find(row => row.id === input.id && row.sessionId === input.session)
      if (!entry) throw new Error('请刷新任务列表。')
      const { sessionId: _session, status: _status, lastDelivery: _delivery, ...expected } = entry
      const result = await proxy.scheduleUpdate({ sessionId: input.session, id: input.id, expected: expected as ScheduleRecord,
        title: input.request.title, prompt: input.request.prompt, ...(input.change ? { change: input.change } : {}) })
      if (!('updated' in result) || !result.updated) throw new Error('任务已变更或结束，请刷新后重试。')
    } else await proxy.scheduleCreate(input.session, input.request)
    if (generation === this.generation) await this.loadTasks()
  }
  private async loadTasks(): Promise<void> {
    this.requireConnected()
    const entries = await this.connection.requireProxy().scheduleCatalog()
    this.scheduleEntries = entries
    this.taskRows = entries
      .slice()
      .sort((a, b) => Date.parse(a.scheduledAt) - Date.parse(b.scheduledAt))
      .map((entry: ScheduleCatalogEntry): TaskRow => ({
        id: entry.id, session: entry.sessionId, title: entry.title, prompt: entry.prompt,
        active: entry.status === 'active',
        status: entry.status === 'active' ? strings.automation.statusActive : strings.automation.statusInactive,
        schedule: scheduleLabel(entry), kind: entry.kind,
        next: entry.status === 'active' ? stampOf(entry.scheduledAt) : '',
        last: entry.lastDelivery === undefined ? '' : stampOf(entry.lastDelivery.deliveredAt),
      }))
    this.recordRows = []
    this.publish()
  }
  private async deleteTask(id: string, sessionId: string): Promise<void> {
    this.requireConnected()
    const result = await this.connection.requireProxy().scheduleDelete(sessionId, id)
    if (result.deleted !== true) throw new Error(strings.automation.deleteFailed)
    this.taskRows = this.taskRows.filter(row => !(row.id === id && row.session === sessionId))
    this.recordRows = []
    this.notice = strings.automation.deleted
    this.publish()
  }
  private async loadTaskHistory(id: string, sessionId: string): Promise<void> {
    this.requireConnected()
    const task = this.taskRows.find(row => row.id === id && row.session === sessionId)
    const result = await this.connection.requireProxy().scheduleHistory(sessionId, id)
    this.recordsTitle = task === undefined || task.title === '' ? strings.automation.detailRecords : task.title
    this.recordRows = (result.records ?? []).map((record: ScheduleDeliveryRecord): RecordRow => ({
      id: `${record.scheduledAt}|${record.messageId}`,
      delivered: stampOf(record.deliveredAt), scheduled: stampOf(record.scheduledAt),
      prompt: record.prompt ?? '',
    }))
    this.publish()
  }
  /** Host DS Bot team: bot entries, main bot status, roles, and models. */
  private async loadChatImages(id: string): Promise<void> {
    this.requireConnected()
    const row = this.messages.find(item => item.id === id), session = this.session, selection = this.selection
    if (!row || (row.kind !== 'message' && row.kind !== 'tool') || !session) return
    const loader = createChatImageLoader({ sessionId: session.sessionId,
      assertCurrent: () => { if (selection !== this.selection || !this.connected) throw new Error('会话已切换。') },
      attachment: (sessionId, image, signal) => this.connection.readSessionImageAttachment(sessionId, chatImageAttachmentReference(image), signal),
      workspace: async (path, signal) => {
        const preview = await loadWorkspacePreview(this.connection.requireSessionTools(session.sessionId), session.sessionId, path, 'image', signal)
        return { data: preview.data, mimeType: preview.mimeType }
      },
    })
    for (const [index,image] of (row.images ?? []).entries()) {
      const uri = await loader(image, this.imageAbort.signal)
      if (selection !== this.selection) return
      this.imageCache.set(`${id}:${index}`, uri)
    }
  }
  private async routeLink(value: string): Promise<void> {
    if (!value || value.length > 8192 || /[\u0000-\u001f]/.test(value)) throw new Error('链接无效。')
    const bot = this.botState ? botMentionTarget(value, this.botState.bots) : undefined
    if (bot) { await this.openBotSession(bot); return }
    if (value.startsWith('dsh-session:')) {
      const target = new URL(value)
      const id = target.searchParams.get('sessionId') ?? target.pathname.replace(/^\//,'')
      if (!this.sessions.some(row => row.sessionId === id)) throw new Error('对话不在当前主机目录中。')
      await this.openSession(id); return
    }
    if (/^https?:\/\//i.test(value) || value.startsWith('mailto:')) { await this.openBrowserUrl(value); return }
    if (/^(javascript|data|blob|intent|content):/i.test(value)) throw new Error('链接协议不允许。')
    await this.previewFile(decodeURIComponent(value.replace(/^workspace:/,'')))
  }
  private botLabels(): Record<string,string> {
    return { submit: strings.bots.submit, confirm: strings.bots.confirm, reject: strings.bots.reject,
      html: strings.bots.htmlFallback, unknown: strings.bots.unknownCard, invalid: strings.bots.invalidViewAnswer,
      sending: this.translate('正在提交'), sent: this.translate('已提交'), failed: this.translate('提交失败，请重试') }
  }
  private async readBotDetails(mode: string, model: string): Promise<void> {
    if (!['usage','schedules','models','efforts'].includes(mode)) throw new Error('未知智能体读取操作。')
    const generation = this.generation
    const result = botObject(await this.connection.requireBotClient().call(mode as BotOperation, mode === 'efforts' ? { ref: model } : mode === 'usage' ? { timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone } : null))
    if (generation !== this.generation) return
    if (mode === 'models') this.botModelOptions = botObjects(result.models).map(row => ({ id: text(row.ref) || text(row.id), name: text(row.name) || text(row.ref) || text(row.id) }))
    else if (mode === 'efforts') this.botEffortOptions = (Array.isArray(result.efforts) ? result.efforts : []).map(row => typeof row === 'string' ? { id: row, name: row } : { id: text(botObject(row).id), name: text(botObject(row).name) || text(botObject(row).id) })
    else if (mode === 'schedules') this.botReport = botObjects(result.tasks).map((row,index) => ({ id: text(row.id) || String(index), title: text(row.title), text: [text(row.prompt),text(row.scheduledAt)||text(row.time),text(row.timeZone)].filter(Boolean).join('\n'), state: '' }))
    else {
      const rows = Array.isArray(result.rows) ? result.rows.filter(Array.isArray) as unknown[][] : []
      this.botReport = botObjects(result.owners).map((owner,index) => {
        const owned = rows.filter(row => row[1] === index)
        const sum = (at: number) => owned.reduce((value,row)=>value+(typeof row[at] === 'number' ? row[at] as number : 0),0)
        return { id: String(index), title: text(owner.name), text: `${strings.bots.inputTokens}: ${sum(4)} · ${strings.bots.outputTokens}: ${sum(7)} · ${strings.bots.calls}: ${sum(8)}`, state: '' }
      })
    }
  }
  private async botOperation(operation: string, raw: string): Promise<void> {
    this.requireConnected()
    if (!(BOT_OPERATIONS as readonly string[]).includes(operation)) throw new Error('不允许的 Bot 操作。')
    if (this.botState?.readOnly !== undefined) throw new Error(this.botState.readOnly || strings.bots.sessionUnavailable)
    await this.connection.requireBotClient().call(operation as BotOperation, JSON.parse(raw))
    await this.loadBots()
  }
  private async loadBots(): Promise<void> {
    this.requireConnected()
    try {
      const state = await this.connection.requireBotClient().state()
      this.botState = state
      this.bots = state.bots.map(b => ({
        id: b.id,
        name: b.name,
        role: b.role || '智能体',
        model: b.model || '',
        color: b.color || '#4B78E6',
        main: b.main,
      }))
    } catch (error) {
      this.bots = []
      throw new Error(safeError(error))
    }
  }
  private async openBotSession(id: string): Promise<void> {
    this.requireConnected()
    const resolved = await this.connection.requireBotClient().resolveSession(id)
    if (!this.sessions.some(row => row.sessionId === resolved.session.sessionId)) this.sessions.push(resolved.session)
    await this.openSession(resolved.session.sessionId)
    this.hostModes[this.browseScope()] = 'bot'; await prefWrite('hostModes', JSON.stringify(this.hostModes))
    this.botState = resolved.state; this.botTarget = id; this.botExtras = []; this.botHistory = []; this.botCursor = undefined
    await this.refreshBotConversation()
  }
  private async loadBotEarlier(): Promise<void> {
    if (!this.session || !this.botTarget || this.botCursor === null) return
    const selection = this.selection
    const value = botObject(await this.connection.requireBotClient().call('earlier', { sessionId: this.session.sessionId, ...(this.botCursor === undefined ? {} : { cursor: this.botCursor }) }))
    if (selection !== this.selection) return
    this.botCursor = value.cursor ?? null
    const page = createNativeRpcId()
    const entries = [...botObjects(value.items), ...botObjects(value.btw).filter(row => row.botId === this.botTarget)]
    this.botHistory = [...entries.map((row,index) => ({ id: `${page}:${text(row.id) || index}`, title: text(row.kind), text: text(row.text) || text(row.answer), state: text(row.status), view: row.kind === 'view' ? JSON.stringify({ ...row, disabled: true, labels: this.botLabels() }) : '' })), ...this.botHistory]
  }
  private async refreshBotConversation(): Promise<void> {
    if (this.botTimer) clearTimeout(this.botTimer)
    this.botPoll?.abort()
    if (!this.botTarget || !this.session || !this.connected) return
    const selection = this.selection, control = this.botPoll = new AbortController()
    try {
      const state = await this.connection.requireBotClient().state(control.signal)
      if (selection !== this.selection || control.signal.aborted) return
      this.botState = state
      const pending = botObject(state.views?.[this.session.sessionId])
      this.botView = Object.keys(pending).length ? JSON.stringify({ ...pending, disabled: state.readOnly !== undefined, labels: this.botLabels() }) : ''
      const room = state.rooms.find(row=>row.id===this.botTarget)
      if (room) {
        const progress = await this.connection.requireBotClient().call('room-progress', { roomId: room.id }, control.signal)
        if (selection !== this.selection || control.signal.aborted) return
        this.botExtras = botObjects(progress).flatMap(row=>botObjects(row.replies)).map((row,index)=>({ id: text(row.id)||String(index), title: text(row.name), text: text(row.text), state: text(row.status) }))
      }
      this.schedulePublish()
    } finally {
      if (selection === this.selection && (this.foreground || residentTaskActive()) && this.connected && !control.signal.aborted) this.botTimer = setTimeout(() => { void this.refreshBotConversation().catch(() => {}) }, 2500)
    }
  }
  private async selectMode(preset: string): Promise<void> {
    this.requireConnected(); const session = this.session
    if (!session || !preset) throw new Error('请先打开会话。')
    if (session.agentPreset === preset) return
    try {
      await this.connection.requireProxy().agentPresetSelect(session.sessionId, preset)
      session.agentPreset = preset
      this.modes = this.modes.map(row => ({ ...row, current: row.id === preset }))
      this.notice = `已选择模式：${this.modes.find(row => row.id === preset)?.name ?? preset}`
    } catch {
      this.error = session.blank ? '模式切换没有成功，请检查连接后重试。' : '这段对话已经开始，模式只能在开始之前更改。请新建对话后再选择。'
    }
  }
  private async selectPermission(preset: string): Promise<void> {
    this.requireConnected(); const session = this.session
    if (!session || !preset) throw new Error('请先打开会话。')
    if(session.backend === 'codex') {
      if(!isCodexPermissionPreset(preset)) throw new Error('权限预设无效。')
      await this.connection.requireCodex().request('thread/resume',{threadId:codexThreadId(session),permissionPreset:preset})
      const updated=withCodexPermission(session,preset);this.session=updated
      this.sessions=this.sessions.map(row=>row.sessionId===session.sessionId?updated:row)
    } else if((session.backend??'harness')==='harness') await this.connection.requireProxy().sessionSelectPermission(session.sessionId, preset)
    else throw new Error('当前后端不支持切换权限。')
    this.permissions = this.permissions.map(row => ({ ...row, current: row.id === preset }))
    this.notice = `已设置操作权限：${this.permissions.find(row => row.id === preset)?.name ?? preset}`
  }
  private async queueAction(itemId: string, mode: string): Promise<void> {
    this.requireConnected(); const session = this.session
    if (!session || !itemId) throw new Error('请先打开会话。')
    if (mode !== 'remove' && mode !== 'steer') throw new Error('只支持移出队列或立即发送。')
    await this.connection.requireProxy().sessionUpdateQueue(session.sessionId, itemId, { kind: mode })
    this.notice = mode === 'remove' ? '已移出队列。' : '已请求立即发送。'
  }
  private async savePrompt(input: Input): Promise<void> {
    const id = input.id ?? ''
    const title = (input.name ?? '').trim()
    const text = (input.text ?? '').trim()
    if (!title || !text) throw new Error('提示词需要名称和内容。')
    if (title.length > 60 || text.length > 4000) throw new Error('提示词过长。')
    const existing = this.prompts.findIndex(row => row.id === id)
    const row = { id: existing < 0 ? `prompt-${Date.now()}` : id, title, text }
    this.prompts = existing < 0 ? [...this.prompts, row] : this.prompts.map((item, index) => index === existing ? row : item)
    this.removedPrompts = this.removedPrompts.filter(item => item !== row.id)
    this.savePrompts()
    this.notice = `已保存提示词“${title}”。`
  }
  private async deletePrompt(id: string): Promise<void> {
    if (!id) throw new Error('请选择要删除的提示词。')
    this.prompts = this.prompts.filter(row => row.id !== id)
    if (this.isBuiltIn(id)) this.removedPrompts = [...this.removedPrompts, id]
    this.savePrompts()
  }
  private async deleteWorkspace(id: string): Promise<void> {
    this.requireConnected()
    const workspace = this.workspaces.find(row => row.workspaceId === id)
    if (!workspace) throw new Error('工作区不存在，请刷新。')
    if (workspace.backend && workspace.backend !== 'harness') throw new Error('CodeX 与 ACP 工作区请在电脑端管理。')
    await this.connection.requireProxy().workspaceDelete(id)
    if (this.workspace?.workspaceId === id) { this.workspace = undefined; this.view = 'workspaces' }
    this.favorites = this.favorites.filter(row => row !== id)
    this.saveViewPrefs()
    await this.loadCatalog()
    this.notice = '已删除工作区。'
  }
  private async moveWorkspace(id: string, direction: string): Promise<void> {
    this.requireConnected()
    const ordered = this.workspaces.filter(row => (row.backend ?? 'harness') === this.backend)
    const index = ordered.findIndex(row => row.workspaceId === id)
    if (index < 0) throw new Error('工作区不存在，请刷新。')
    const target = direction === 'up' ? index - 1 : index + 1
    if (target < 0 || target >= ordered.length) throw new Error('已经到达列表两端。')
    // Moving up means landing before the row above it; moving down lands before
    // the row after the neighbour (undefined appends to the end).
    const before = direction === 'up' ? ordered[target].workspaceId : ordered[target + 1]?.workspaceId
    await (before === undefined
      ? this.connection.requireProxy().workspaceInsertBefore(id)
      : this.connection.requireProxy().workspaceInsertBefore(id, before))
    this.orderBy = 'manual'
    this.saveViewPrefs()
    await this.loadCatalog()
  }
  /** Mirrors Android: an untouched conversation is empty and not explicitly started. */
  private sessionIsBlank(): boolean {
    const session = this.session
    return session !== undefined && this.messages.length === 0 && session.blank !== false
  }
  private async moveSession(workspaceId: string): Promise<void> {
    this.requireConnected()
    const session = this.session
    const target = this.workspaces.find(row => row.workspaceId === workspaceId)
    if (!session || !target) throw new Error('请先打开会话并选择目标工作区。')
    if (!this.sessionIsBlank()) throw new Error('这段对话已经在其他目录开始，工作目录不能更改。')
    const previousId = session.sessionId
    this.workspace = target
    await this.newSession()
    await this.connection.requireProxy().workspaceArchiveSession(previousId)
    this.archived = await this.connection.requireProxy().workspaceList().then(list =>
      Array.isArray(list.archivedSessionIds) ? list.archivedSessionIds : this.archived)
    this.notice = `已在“${target.title || target.path}”中新建对话。`
  }
  /** Merge only the display-bearing projection fields; a failed refresh stays silent. */
  private async refreshTitles(): Promise<void> {
    const generation = this.generation
    try {
      const rows = await this.connection.requireProxy().sessionList()
      if (generation !== this.generation || !this.connected) return
      for (const row of rows) {
        if (resolveSessionDisplayTitle(row) === undefined) continue
        const local = this.sessions.find(s => s.sessionId === row.sessionId)
        if (!local) continue
        local.title = row.title; local.projections = row.projections; local.blank = row.blank
        if (this.session?.sessionId === row.sessionId) this.session = local
      }
      this.schedulePublish()
    } catch { /* Titles are cosmetic; never surface a refresh failure as a connection error. */ }
  }
  async handleNotificationNavigation(hostId: string, sessionId: string): Promise<void> {
    if (!sessionId) return
    if (this.connected && this.host?.deviceId === hostId) {
      if (this.session?.sessionId !== sessionId) {
        await this.openSession(sessionId)
      }
      this.view = 'chat'
      this.publish()
      return
    }
    this.pendingNotificationSession = { hostId, sessionId }
    if (this.credentials && this.devices.length > 0) {
      const device = this.devices.find(d => d.deviceId === hostId && d.trusted)
      if (device) {
        await this.connectHost(hostId)
      }
    }
  }
  validateImageAttachments(raw: string): void {
    this.requireConnected()
    if (!this.session) throw new Error('请先打开会话。')
    validateImageInput(this.session, JSON.parse(raw) as Array<{ data: string; mediaType: string }>)
  }
  async downloadWorkspaceFile(path: string, write: (bytes: Uint8Array) => Promise<void>): Promise<void> {
    this.requireConnected()
    if (!this.session || this.downloadBusy) throw new Error('文件下载暂不可用')
    const selection = this.selection, generation = this.generation, session = this.session.sessionId
    const ticket = ++this.downloadRevision
    this.downloadBusy = true; this.downloadBytes = 0; this.publish()
    try {
      await this.download.run(this.connection.requireSessionTools(session), session, path,
        () => generation === this.generation && selection === this.selection && this.connected,
        write, bytes => { this.downloadBytes = bytes; this.schedulePublish() })
    } catch (error) {
      if (ticket === this.downloadRevision) { this.error = safeError(error); this.publish() }
      throw error
    } finally { if (ticket === this.downloadRevision) { this.downloadBusy = false; this.publish() } }
  }
  private observedTasks(): ObservedTask[] {
    return this.sessions.map(session => {
      const selected = session.sessionId === this.session?.sessionId
      const messages = selected ? this.messages : this.observedMessages.get(session.sessionId) ?? []
      const inputs = messages.filter(item => (item.kind === 'approval' && item.outcome === undefined) || (item.kind === 'question' && item.outcome === undefined && item.questionState !== 'continued'))
      const reply = [...messages].reverse().find(item => item.kind === 'message' && item.role === 'assistant')
      return { id: session.sessionId, title: sessionName(session), backend: session.backend,
        watched: selected || this.recents.includes(session.sessionId) || this.pinned.includes(session.sessionId),
        running: selected ? this.running : session.running, updatedAt: session.updatedAt,
        inputIds: inputs.map(item => item.id), summary: reply?.kind === 'message' ? reply.text.replace(/```[\s\S]*?```/g,' ').replace(/[`*_>#|]+/g,' ').replace(/\s+/g,' ').trim().slice(0,240) : '' }
    })
  }
  private syncTaskNotifications(): void {
    if (!this.connected || !this.host) return
    const rows = this.observedTasks(), selected = this.session?.sessionId ?? ''
    for (const notice of this.taskNotifications.observe(rows, selected, this.foreground, this.notificationsEnabled)) {
      // The selected conversation's live subscriptions already deliver these.
      if (notice.id === selected) continue
      void publishTaskNotification(this.context, this.host.deviceId, notice.id, notice.title,
        notice.kind === 'ended' ? strings.comfort.taskEnded : strings.comfort.taskInput)
    }
    if (this.notificationTimer) return
    this.notificationTimer = setTimeout(() => {
      this.notificationTimer = undefined
      if (!this.host || !this.connected || !this.notificationsEnabled) { updateActivityNotification(this.context); return }
      const task = activeTask(this.observedTasks(), this.session?.sessionId ?? '')
      updateActivityNotification(this.context, {
        hostId: this.host.deviceId, sessionId: task?.id ?? '', title: task?.title ?? this.host.name,
        status: task ? (task.inputIds.length ? strings.comfort.liveTaskWaiting : strings.comfort.liveTaskRunning) : this.translate(this.status),
        summary: task?.summary ?? (residentTaskError() || this.translate('主机已连接')), updatedAt: task?.updatedAt ?? 0,
      })
    }, 800)
  }
  private notifyTaskEnded(): void {
    if (this.foreground || !this.notificationsEnabled || !this.session || !this.host) return
    void publishTaskNotification(
      this.context,
      this.host.deviceId,
      this.session.sessionId,
      sessionName(this.session),
      this.translate('任务已结束，点此查看结果'),
    )
  }
  private notifyInputNeeded(itemId?: string): void {
    if (this.foreground || !this.notificationsEnabled || !this.session || !this.host) return
    if (itemId && this.notifiedInputs.has(itemId)) return
    if (itemId) this.notifiedInputs.add(itemId)
    void publishTaskNotification(
      this.context,
      this.host.deviceId,
      this.session.sessionId,
      sessionName(this.session),
      this.translate('需要你确认，点此打开对话'),
    )
  }
  private async openSession(id: string): Promise<void> {
    this.requireConnected()
    this.download.cancel(); ++this.downloadRevision; this.downloadBusy = false
    if (this.session) this.observedMessages.set(this.session.sessionId, this.messages.slice(-100))
    this.stagedFiles = []; this.stagedData.clear(); this.botTarget = ''; this.botView = ''; this.botExtras = []; this.botHistory = []; this.botPoll?.abort(); if (this.botTimer) clearTimeout(this.botTimer)
    const session = this.sessions.find(s => s.sessionId === id)
    if (!session) throw new Error('会话不存在，请刷新工作区。')
    const selection = ++this.selection
    await this.stream?.close(); this.stream = undefined
    this.activity.stop(); this.imageAbort.abort(); this.imageAbort = new AbortController(); this.imageCache.clear()
    this.session = session;
    const legacyKey = `${this.server}/${this.host?.deviceId}/${session.sessionId}`
    if (this.legacyDraftOwner === this.account && this.drafts[legacyKey] && !this.drafts[this.sessionKey()]) { this.drafts[this.sessionKey()] = this.drafts[legacyKey]; delete this.drafts[legacyKey]; this.saveDrafts() }
    this.messages = []; this.models = undefined; this.modelWarning = ''; this.hasMore = false
    this.notifiedInputs.clear()
    // Android re-applies the stored history density every time a session opens.
    this.compactHistory = (JSON.parse(await prefRead(this.compactKey()) || '{}') as { value?: boolean }).value === true
    await this.connection.configureHistory(this.compactHistory).catch(() => undefined)
    this.skills = []; this.files = []; this.filePath = ''; this.filePreview = undefined
    this.setTerminalRenderer(this.terminalRendererScope, false)
    this.terminalAttachment?.dispose(); this.terminalAttachment = undefined
    this.terminalRaw = ''; this.terminalChunk = ''; this.terminalReset = true; ++this.terminalRenderRevision; this.terminals = []; this.activeTerminalId = undefined
    this.terminalScreen = ''; this.terminalWritable = false
    this.terminalStatus = ''; this.terminalError = ''; this.terminalBusy = false
    this.info = []
    this.view = 'chat'; this.running = session.running;
    if (this.sharedText) this.stageSharedText(this.sharedText)
    this.publish()
    this.recents = [id, ...this.recents.filter(row => row !== id)].slice(0, 50)
    this.saveViewPrefs()
    this.feedbackByMessage.clear()
    if (!session.backend || session.backend === 'harness') {
      const ratings = await this.connection.requireProxy().messageFeedbackList(id).catch(() => undefined)
      if (selection !== this.selection) return
      for (const row of ratings ?? []) this.feedbackByMessage.set(row.messageId, row.rating)
      const history = await this.connection.requireProxy().sessionHistory(id, undefined, 60, session.parentSessionId)
      if (selection !== this.selection) return
      const live = this.messages
      this.messages = foldHistory(history.events, id)
      for (const item of live) if (!this.messages.some(old => old.id === item.id)) this.messages.push(item)
      this.hasMore = history.hasMore; this.beforeSeq = minimumSeq(history.events)
    } else if (session.backend === 'codex') {
      const client = this.connection.requireCodex(); const nativeId = codexThreadId(session)
      const [read, history] = await Promise.all([
        readCodexSession(client, nativeId),
        readCodexHistoryPage(client, nativeId, undefined, 16),
      ])
      if (selection !== this.selection) return
      const timeline = createCodexTimelineState({ ...read.thread, turns: [] })
      if (!timeline) throw new Error('CodeX 历史格式无效。')
      this.codexState = withActiveCodexTurn(timeline, history.activeTurnId)
      this.messages = foldHistory(history.events, session.sessionId, true)
      this.hasMore = history.hasMore; this.beforeSeq = oldestSeq(history.events)
      this.running = history.activeTurnId !== undefined
      const stream = await client.subscribe(nativeId, frame => {
        if (selection !== this.selection || !this.codexState) return
        const prev = this.codexState
        this.codexState = reduceCodexTimelineFrame(this.codexState, frame)
        const previousItems = new Map(prev.items.map(item => [item.id, item]))
        const live = codexItemsToChat(this.codexState.items.filter(item => previousItems.get(item.id) !== item))
        if (live.length > 0) {
          this.messages = mergeCodexLive(this.messages, live)
        }
        const approval = this.codexState.approval
        if (approval && !this.messages.some(item => item.kind === 'approval' && item.approvalId === approval.requestHandle)) {
          this.messages.push({ kind: 'approval', id: approval.requestHandle, sessionId: session.sessionId, approvalId: approval.requestHandle, toolName: approval.command ?? approval.kind, reason: approval.reason, createdAt: Date.now() })
        }
        const wasRunning = this.running
        this.running = this.codexState.session.status === 'running' || this.codexState.session.status === 'waiting'
        if (wasRunning && !this.running) this.notifyTaskEnded()
        if (approval) this.notifyInputNeeded(approval.requestHandle)
        this.schedulePublish()
      }, undefined, () => { if (selection === this.selection) { this.error = '会话流已关闭，请重新打开会话。'; this.running = false; this.publish() } })
      if (selection !== this.selection) { await stream.close(); return }
      this.stream = stream
    } else {
      const client = this.acp(session.backend); const nativeId = session.nativeId ?? id.split(':').slice(1).join(':')
      await client.call('session/load', { sessionId: nativeId, cwd: session.cwd, mcpServers: [], backend: session.backend })
      if (selection !== this.selection) return
      const stream = await client.openStream(nativeId, frame => {
        if (selection !== this.selection) return
        const wasRunning = this.running
        this.messages = applyCursorFrame(this.messages, session.sessionId, frame)
        const params = frame.frame.params as { update?: { sessionUpdate?: string } } | undefined
        if (params?.update?.sessionUpdate === 'prompt_completed' || params?.update?.sessionUpdate === 'prompt_failed') {
          this.running = false
          if (wasRunning) this.notifyTaskEnded()
        }
        for (const item of this.messages) {
          if ((item.kind === 'approval' && item.outcome === undefined) || (item.kind === 'question' && item.outcome === undefined)) {
            this.notifyInputNeeded(item.id)
          }
        }
        this.schedulePublish()
      }, () => { if (selection === this.selection) { this.error = '会话流已关闭，请重新打开会话。'; this.running = false; this.publish() } })
      if (selection !== this.selection) { await stream.close(); return }
      this.stream = stream
      const history = await client.transferCall('dsh/sessionHistory', { sessionId: nativeId, backend: session.backend }) as { events: unknown[] }
      if (selection !== this.selection) return
      if (!Array.isArray(history.events)) throw new Error('历史响应格式无效。')
      this.messages = mergeAcpHistoryAndLive(foldAcpHistory(history.events, id), this.messages)
    }
    if (selection === this.selection) {
      if ((session.backend ?? 'harness') === 'harness') this.activity.start(this.connection.requireSessionTools(session.sessionId), session.sessionId)
      await this.loadModels()
      if (selection === this.selection && this.connected) await this.browse.visit(this.browseScope(), session.sessionId).catch(() => { this.notice = '会话已打开，但未能保存浏览位置。' })
    }
  }
  private async loadModels(): Promise<void> {
    const selection = this.selection
    const session = this.session; if (!session) return
    try {
      let models: SessionModels
      if (!session.backend || session.backend === 'harness') models = await this.connection.requireProxy().sessionModels(session.sessionId)
      else if (session.backend === 'codex') models = await loadCodexModels(this.connection.requireCodex(), this.codexSelections.get(session.sessionId) ?? codexModelSelectionFromSession(session))
      else models = await loadAcpModels(this.acp(this.session?.backend ?? 'cursor'), session.nativeId!, session.backend)
      if (selection === this.selection) this.models = models
    } catch { if (selection === this.selection) { this.models = undefined; this.modelWarning = '模型目录暂不可用，将沿用主机当前模型。' } }
  }
  private async newSession(): Promise<void> {
    const generation = this.generation
    this.requireConnected()
    const workspace = this.workspace ?? this.backendWorkspaces().find(w => !w.sessionIds.every(id => this.archived.includes(id)))
      ?? this.workspaces.find(w => (w.backend ?? 'harness') === this.backend)
    if (!workspace) throw new Error('请先选择工作区。')
    let session: RemoteSession
    if (workspace.backend === 'codex') {
      const preset = this.defaultPermission === 'default' ? 'workspace-write' : this.defaultPermission
      const result = await this.connection.requireCodex().request('thread/start', { cwd: workspace.path, permissionPreset: preset }) as { thread?: unknown }
      const projected = createCodexTimelineState(result.thread as Parameters<typeof createCodexTimelineState>[0])
      if (!projected) throw new Error('CodeX 会话响应无效。')
      session = withCodexPermission(codexSession(projected.session), preset as 'workspace-write' | 'danger-full-access')
    }
    else if (workspace.backend && workspace.backend !== 'harness') {
      const created = await this.acp(workspace.backend).createSession(workspace.path, undefined, workspace.backend)
      const creators: Record<string, (input: { acpSessionId: string; cwd?: string; title?: string }) => RemoteSession> = {
        cursor: createCursorSession, pi: createPiSession, claude: createClaudeSession,
        opencode: createOpencodeSession, antigravity: createAntigravitySession, hermes: createHermesSession,
      }
      const create = creators[workspace.backend]
      if (!create) throw new Error(`不支持的后端：${workspace.backend}`)
      session = create({ acpSessionId: created.sessionId, cwd: workspace.path })
    } else { const created = await this.connection.requireProxy().sessionCreate(workspace.workspaceId); session = { sessionId: created.sessionId, backend: 'harness', blank: true, running: false, updatedAt: Date.now() } }
    if (generation !== this.generation) throw new Error('连接已切换，请在原主机刷新查看新会话。')
    if((session.backend??'harness')==='harness'&&this.defaultPermission!=='default') {
      await this.connection.requireProxy().sessionSelectPermission(session.sessionId,this.defaultPermission)
      if(generation!==this.generation)return
      const confirmed=await this.connection.requireProxy().sessionList()
      const selected=confirmed.find(row=>row.sessionId===session.sessionId)
      if(sessionPermissions(selected??session)?.currentValue!==this.defaultPermission)throw new Error('主机未确认新对话权限，请重新打开检查。')
      session=selected!
    }
    this.sessions.unshift(session); workspace.sessionIds.unshift(session.sessionId)
    await this.openSession(session.sessionId)
  }
  private async newWorkspace(path: string): Promise<void> {
    this.requireConnected(); path = path.trim()
    if (!path) throw new Error('请选择主机目录。')
    const generation = this.generation
    if (this.backend === 'harness') await this.connection.requireProxy().workspaceCreate(path)
    else if (this.backend === 'codex') await createCodexWorkspace(this.connection.requireCodex(), path, createNativeRpcId())
    else {
      await this.connection.requireProxy().hostListDirectory(path)
      if (generation !== this.generation) return
      const create = { cursor: createCursorWorkspace, pi: createPiWorkspace, claude: createClaudeWorkspace, antigravity: createAntigravityWorkspace, opencode: createOpencodeWorkspace, hermes: createHermesWorkspace }[this.backend]
      if (!create) throw new Error('后端不支持目录注册。')
      const workspace = create(path)
      this.registeredWorkspaces = [...this.registeredWorkspaces.filter(row => row.workspaceId !== workspace.workspaceId), workspace]
    }
    if (generation === this.generation) await this.loadCatalog()
  }
  private async prompt(input: Input): Promise<void> {
    this.requireConnected(); const session = this.session
    if (!session) return
    const files = this.stagedFiles.filter(row => row.scope === this.sessionKey()), fileSelection = this.selection, generation = this.generation
    for (const file of files) {
      if (!file.path) file.path = await uploadFile((method,args,signal)=>this.connection.rpc(method,args,signal),session.sessionId,file.name,this.stagedData.get(file.id) ?? '',()=>fileSelection === this.selection && generation === this.generation && this.connected,this.imageAbort.signal)
      if (fileSelection !== this.selection || generation !== this.generation) throw new Error('会话已切换。')
    }
    if (files.length) {
      input = { ...input, text: (input.text ?? '').trimEnd() + '\n\n' + files.map(row => '@' + (/\s|"/.test(row.path) ? JSON.stringify(row.path) : row.path)).join(' ') }
    }
    const images = input.images ?? (input.image ? [{ data: input.image, mediaType: input.mediaType ?? 'image/jpeg' }] : [])
    if (!(input.text ?? '').trim() && images.length === 0) return
    const backend = session.backend ?? 'harness'
    if (this.botTarget && this.botState) {
      if (images.length > 0) throw new Error('Bot 消息暂不接受图片。')
      const request = botMessageRequest(this.botState, this.botTarget, input.text ?? '')
      await this.connection.requireBotClient().call(request.endpoint, request.payload)
      await this.refreshBotConversation(); return
    }
    validateImageInput(session, images)
    const selection = this.selection
    this.running = true; for (const file of files) this.stagedData.delete(file.id); this.stagedFiles = this.stagedFiles.filter(row => !files.includes(row)); this.publish()
    try {
      if (backend === 'harness') await this.connection.requireProxy().sessionPrompt(session.sessionId, input.text ?? '', undefined,
        images)
      else if (backend === 'codex') {
        const content: unknown[] = [...((input.text ?? '').length ? [{ type: 'text', text: input.text }] : []), ...images.map(image => ({ type: 'image', url: `data:${image.mediaType};base64,${image.data}` }))]
        const chosen = this.codexSelections.get(session.sessionId) ?? this.models?.current
        const client = this.connection.requireCodex()
        await client.request('thread/resume', { threadId: codexThreadId(session), permissionPreset: codexPermissionPreset(session), ...(chosen?.provider === 'codex' ? { model: chosen.model } : {}) })
        await client.request('turn/start', { threadId: codexThreadId(session), input: content, ...(chosen?.provider === 'codex' ? { model: chosen.model, ...(chosen.reasoningEffort ? { effort: chosen.reasoningEffort } : {}) } : {}) })
      } else {
        const response = await this.acp(session.backend!).prompt(session.nativeId!, input.text ?? '', undefined,
          images.map(image => ({ type: 'image', mimeType: image.mediaType, data: image.data })), backend)
        if (selection === this.selection && (response as { stopReason?: string })?.stopReason !== 'in_progress') this.running = false
      }
    } catch (error) {
      if (selection === this.selection) {
        this.running = false
        this.failedSends.push({ id: createNativeRpcId(), scope: this.sessionKey(), text: input.text ?? '', image: input.image, mediaType: input.mediaType, images: images.map(image=>({...image})), state: 'unconfirmed', error: safeError(error) })
        this.failedSends = this.failedSends.slice(-20)
      }
      throw error
    }
  }
  private async interrupt(): Promise<void> {
    this.requireConnected(); const session = this.session; if (!session) return
    if (!session.backend || session.backend === 'harness') await this.connection.requireProxy().sessionCancel(session.sessionId)
    else if (session.backend === 'codex') {
      if (!this.codexState?.activeTurnId) throw new Error('尚未收到可中断的 CodeX 回复标识。')
      await this.connection.requireCodex().interrupt(codexThreadId(session), this.codexState.activeTurnId)
    } else await this.acp(this.session?.backend ?? 'cursor').cancel(session.nativeId!)
    this.notice = '已请求停止，等待主机确认。'
  }
  private async approval(input: Input): Promise<void> {
    this.requireConnected(); const session = this.session
    const item = this.messages.find(row => row.kind === 'approval' && row.id === input.id)
    if (!session || item?.kind !== 'approval' || item.outcome) throw new Error('此审批已失效。')
    if (this.pendingApprovals.has(item.id)) throw new Error('审批正在提交。')
    if (input.decision !== 'allow_once' && input.decision !== 'deny') throw new Error('只支持允许一次或拒绝。')
    this.pendingApprovals.add(item.id)
    try {
    const allowed = input.decision === 'allow_once'
    if (!session.backend || session.backend === 'harness') await this.connection.requireProxy().respondApproval(item.frameRpcId ?? '', session.sessionId, item.approvalId, allowed ? 'allowed-once' : 'rejected')
    else if (session.backend === 'codex') await this.connection.requireCodex().respond(item.approvalId, allowed ? 'accept' : 'decline')
    else await this.acp(this.session?.backend ?? 'cursor').respond(item.approvalId, allowed ? 'allow-once' : 'reject-once')
    item.outcome = allowed ? 'allowed-once' : 'rejected'
    } finally { this.pendingApprovals.delete(item.id) }
  }
  private async answerQuestion(input: Input): Promise<void> {
    this.requireConnected()
    const item = this.messages.find(row => row.kind === 'question' && row.id === input.id)
    if (!this.session || item?.kind !== 'question' || item.outcome || !item.frameRpcId || !input.answers) throw new Error('此问题已失效。')
    if (this.pendingApprovals.has(item.id)) throw new Error('回答正在提交。')
    this.pendingApprovals.add(item.id)
    try {
      await this.connection.requireProxy().respondQuestion(item.frameRpcId, this.session.sessionId, { answers: input.answers })
      item.outcome = 'answered'
    } finally { this.pendingApprovals.delete(item.id) }
  }
  private async selectModel(input: Input): Promise<void> {
    this.requireConnected(); const session = this.session; if (!session || this.running) throw new Error('请在回复结束后切换模型。')
    const selection = { provider: input.provider ?? '', model: input.model ?? '', ...(input.effort ? { reasoningEffort: input.effort } : {}) }
    if (!session.backend || session.backend === 'harness') await this.connection.requireProxy().sessionSelectModel(session.sessionId, selection)
    else if (session.backend === 'codex') {
      if (selection.provider !== 'codex' || !this.models?.groups.some(group => group.id === selection.provider && group.models.some(model => model.id === selection.model))) throw new Error('模型不在主机目录中。')
      this.codexSelections.set(session.sessionId, selection)
      this.notice = '模型将在下一条消息发送时提交给主机。'
    }
    else await selectAcpModel(this.acp(this.session?.backend ?? 'cursor'), session.nativeId!, session.backend, selection)
    await this.loadModels()
  }
  private async olderHistory(): Promise<void> {
    if (!this.session || !this.hasMore || this.beforeSeq === undefined) return
    const selection = this.selection
    if (this.session.backend === 'codex') {
      const page = await readCodexHistoryPage(this.connection.requireCodex(), codexThreadId(this.session), this.beforeSeq, 60)
      if (selection !== this.selection || !this.session) return
      const older = foldHistory(page.events, this.session.sessionId, true)
      this.messages = prependHistory(older, this.messages)
      this.beforeSeq = oldestSeq(page.events); this.hasMore = page.hasMore
    } else if (!this.session.backend || this.session.backend === 'harness') {
      const page = await this.connection.requireProxy().sessionHistory(this.session.sessionId, this.beforeSeq, 60, this.session.parentSessionId)
      if (selection !== this.selection || !this.session) return
      const older = foldHistory(page.events, this.session.sessionId)
      this.messages = prependHistory(older, this.messages)
      this.beforeSeq = oldestSeq(page.events); this.hasMore = page.hasMore
    }
  }
  private onFrame(frame: MuxStreamFrame): void {
    const payload = frame.payload
    if (payload.type === 'session/projection' && payload.sessionId && typeof payload.key === 'string') {
      const key = `${payload.sessionId}|${payload.key}`, previous = this.projectionSeq.get(key)
      if (payload.seq !== undefined && previous !== undefined && payload.seq < previous) return
      if (payload.seq !== undefined) this.projectionSeq.set(key, payload.seq)
      const update = (session: RemoteSession): RemoteSession => session.sessionId !== payload.sessionId ? session : {
        ...session, projections: { ...session.projections, values: { ...session.projections?.values, [payload.key!]: payload.value } }
      }
      this.sessions = this.sessions.map(update)
      if (this.session) this.session = update(this.session)
      this.schedulePublish(); return
    }
    const lifecycle = sessionRunningForMuxFrame(frame)
    if (lifecycle !== undefined) this.sessions = this.sessions.map(row => row.sessionId === payload.sessionId ? { ...row, running: lifecycle } : row)
    if (payload.sessionId && payload.sessionId !== this.session?.sessionId) {
      if (this.recents.includes(payload.sessionId) || this.pinned.includes(payload.sessionId)) {
        this.observedMessages.set(payload.sessionId, applyMuxFrame(this.observedMessages.get(payload.sessionId) ?? [], frame).slice(-100))
        if (this.observedMessages.size > 50) this.observedMessages.delete(this.observedMessages.keys().next().value!)
      }
      this.schedulePublish()
    }
    if (this.session?.backend && this.session.backend !== 'harness') return
    if (!this.session || frame.payload.sessionId !== this.session.sessionId) return
    const wasRunning = this.running
    this.messages = applyMuxFrame(this.messages, frame)
    const running = sessionRunningForMuxFrame(frame); if (running !== undefined) this.running = running
    // The Host names a session from its first prompt, so pull the projection back
    // when a run ends instead of leaving a locally created blank row untitled.
    if (wasRunning && !this.running) {
      void this.refreshTitles()
      this.notifyTaskEnded()
    }
    for (const item of this.messages) {
      if ((item.kind === 'approval' && item.outcome === undefined) || (item.kind === 'question' && item.outcome === undefined)) {
        this.notifyInputNeeded(item.id)
      }
    }
    this.schedulePublish()
  }
  private acp(backend: string) {
    if (backend === 'hermes') return this.connection.requireHermes()
    if (backend === 'pi') return this.connection.requirePi()
    if (backend === 'claude') return this.connection.requireClaude()
    if (backend === 'antigravity') return this.connection.requireAntigravity()
    if (backend === 'opencode') return this.connection.requireOpencode()
    return this.connection.requireCursor()
  }
  private requireConnected(): void { if (!this.connected) throw new Error('请先连接主机。') }
  private async disconnect(navigate = true, invalidate = true, muteAutoConnect = true): Promise<void> {
    this.download.cancel(); ++this.downloadRevision; this.downloadBusy = false
    this.taskNotifications.reset(); this.observedMessages.clear()
    if (this.notificationTimer) clearTimeout(this.notificationTimer)
    this.notificationTimer = undefined
    updateActivityNotification(this.context)
    this.setTerminalRenderer(this.terminalRendererScope, false)
    this.botHistory = []
    this.activity.stop(); this.imageAbort.abort(); this.imageCache.clear(); this.botState = undefined; this.botTarget = ''; this.botView = ''; this.botExtras = []; this.botPoll?.abort(); if (this.botTimer) clearTimeout(this.botTimer); this.failedSends = []; this.stagedFiles = []; this.stagedData.clear(); this.terminalRaw = ''; this.projectionSeq.clear(); this.registeredWorkspaces = []
    if (invalidate) ++this.cancellation
    ++this.generation; ++this.selection
    // An explicit 断开 is user intent: auto-connect stays off until the next
    // successful connect. Backgrounding passes false so returning can recover.
    if (muteAutoConnect) this.autoConnectMuted = true
    this.connected = false; this.phase = 'disconnected'; this.armed = false
    void stopResidentTask(this.context)
    this.retryable = true; this.recoveryExhausted = false
    this.status = '未连接'; this.running = false
    this.stream = undefined; await this.connection.close()
    this.host = undefined; this.session = undefined; this.workspace = undefined; this.models = undefined; this.codexState = undefined
    this.messages = []; this.workspaces = []; this.sessions = []; this.codexSelections.clear(); this.pendingApprovals.clear()
    this.notifiedInputs.clear()
    this.archived = []; this.favorites = []; this.recents = []; this.collapsed = []
    this.visibleCounts = {}; this.feedbackByMessage.clear(); this.backend = 'harness'
    this.skills = []; this.files = []; this.filePath = ''; this.filePreview = undefined
    this.terminalAttachment?.dispose(); this.terminalAttachment = undefined
    this.terminalRaw = ''; this.terminalChunk = ''; this.terminalReset = true; ++this.terminalRenderRevision; this.terminals = []; this.activeTerminalId = undefined
    this.terminalScreen = ''; this.terminalWritable = false
    this.terminalStatus = ''; this.terminalError = ''; this.terminalBusy = false
    this.info = []; this.modes = []; this.permissions = []
    this.pluginViews = []; this.pluginRows = []; this.settingsWritable = false
    this.formEntry = ''; this.formNs = ''; this.formTitle = ''; this.formFields = []
    this.formOverridden = []; this.formRows = []
    this.taskRows = []; this.recordRows = []; this.recordsTitle = ''; this.bots = []; this.networkSections = []
    if (navigate) this.view = this.credentials ? 'devices' : 'login'
  }
  private async logout(): Promise<void> {
    const key = this.lastHostKey()
    this.stopQr(); await this.disconnect(); await vaultDelete(this.key('credentials'))
    this.credentials = undefined; this.account = ''; this.devices = []; this.candidate = undefined; this.view = 'login'
    this.lastConnectedDeviceId = ''; await prefWrite(key, '')
  }
  async dispose(): Promise<void> { this.stopQr(); if (this.emitTimer) clearTimeout(this.emitTimer); this.listener = () => undefined; try { await this.flushDrafts() } finally { await this.disconnect() } }
  private schedulePublish(): void { if (!this.emitTimer) this.emitTimer = setTimeout(() => { this.emitTimer = undefined; this.publish() }, 50) }
  private publish(): void {
    const sessionIds = new Set(this.workspace?.sessionIds ?? [])
    const harness = !this.session?.backend || this.session.backend === 'harness'
    const sessionKey = this.sessionKey()
    const queueRows: QueueRow[] = this.session && harness ? this.queueItems(this.session) : []
    const artifacts = (harness && this.host && this.session)
      ? projectUiArtifacts(this.messages, this.host.deviceId, this.session.sessionId)
      : []
    const artifactsByToolId = new Map<string, UiArtifact[]>()
    const updatedByTurn = new Map<string, string[]>()
    for (const art of artifacts) {
      const list = artifactsByToolId.get(art.uiId) ?? []
      list.push(art)
      artifactsByToolId.set(art.uiId, list)
      if (art.updatedTurn && art.updatedTurn !== art.turn) {
        const ulist = updatedByTurn.get(art.updatedTurn) ?? []
        ulist.push(`${art.title || '交互式 UI'} 已更新至版本 v${art.version}；请参见上方原始卡片。`)
        updatedByTurn.set(art.updatedTurn, ulist)
      }
    }
    const hidden = this.botTarget ? this.botState?.exchangeTurns?.[this.session?.sessionId ?? ''] : undefined
    const hiddenTurns = new Set(Array.isArray(hidden) ? hidden.map(String) : [])
    const rows: Row[] = this.messages.filter(item => item.kind === 'approval' || item.kind === 'question' || item.turn === undefined || !hiddenTurns.has(item.turn)).map(item => {
      const base = {
        id: item.id, kind: item.kind, images: [] as string[],
        category: item.kind === 'message' ? (item.context ? 'context' : item.role) : 'tool',
        turn: item.turn ?? '', clock: clockOf(item), preview: previewOf(item),
        attachments: (item.kind === 'message' || item.kind === 'tool' ? item.images ?? [] : []).length,
        actionable: item.kind === 'message' && harness && !item.context && item.role !== 'system' && !item.streaming && item.text.length > 0,
        feedback: this.feedbackByMessage.get(item.id) ?? '', tokens: tokensOf(item), usageDetail: usageOf(item, this.session, this.models?.current),
        turnStatus: item.kind === 'message' && (item.role !== 'assistant' || item.context) ? '' : item.turnEnd?.reason ?? '',
        turnDetail: item.kind === 'message' && (item.role !== 'assistant' || item.context) ? '' : item.turnEnd?.detail ?? '',
      }
      if (item.kind === 'message') {
        const failureDetail = item.role === 'assistant' && !item.context && item.turnEnd?.reason === 'failed' ? (item.turnEnd.detail || '回复失败') : ''
        const body = item.role === 'assistant' || item.role === 'user' ? heartbeatMessageBody(item.text, item.role) : undefined
        const text = this.botTarget && this.botState ? linkBotMentions(body || item.text || failureDetail, this.botState.bots, this.botTarget) : body || item.text || failureDetail
        const detail = item.reasoning ?? ''
        return { ...base, heartbeatRaw: body ? item.text : '', title: item.role === 'user' ? '你' : item.role === 'assistant' ? '助手' : (failureDetail ? '错误' : '系统'), text, detail, pending: false, images: (item.images ?? []).flatMap((image,index) => { const cached = this.imageCache.get(`${item.id}:${index}`); return cached ? [cached] : image.uri?.startsWith('data:image/') ? [image.uri] : [] }) }
      }
      if (item.kind === 'tool') {
        const directArts = artifactsByToolId.get(item.id)
        const rowArtifacts = directArts && directArts.length > 0 ? directArts.map(artifactToRow) : undefined
        const updatedArts = item.turn ? updatedByTurn.get(item.turn) : undefined
        const parsedReplies = (item.state === 'finished')
          ? parseBotReplies(item.resultDetail?.text)
          : undefined
        const botReplies: BotReplyRow[] | undefined = (parsedReplies && parsedReplies.length > 0)
          ? parsedReplies.map(r => ({
              name: text(r.name) || (r.kind === 'user' ? '你的回答' : (strings.bots.title ?? '智能体')),
              color: text(r.color),
              text: text(r.text) || text(r.kind),
              kind: text(r.kind),
            }))
          : undefined
        const groupRelay = (item.toolKey ?? item.toolName) === 'group_relay'
        return {
          ...base,
          title: (groupRelay && botReplies) ? '群组协作 · 已完成' : `${item.toolName} · ${item.state}`,
          text: (groupRelay && botReplies) ? '' : (item.summary ?? ''),
          detail: [item.arguments, item.callDetail?.text, item.resultDetail?.text].filter(Boolean).join('\n'),
          pending: false,
          uiArtifacts: rowArtifacts,
          updatedArtifacts: updatedArts,
          botReplies,
        }
      }
      if (item.kind === 'approval') return { ...base, title: item.toolName, text: item.reason ?? '工具请求执行权限', detail: item.outcome ?? '', pending: !item.outcome && this.connected }
      return { ...base, kind: 'question', title: '主机提问', text: '', detail: item.outcome ?? '', pending: !item.outcome && this.connected, questions: item.questions }
    })
    const archived = new Set(this.archived)
    const visibleSessions = this.sessions.filter(s => !archived.has(s.sessionId))
    const scoped = (rows: RemoteSession[]): CatalogRow[] => rows
      .map(s => ({ id: s.sessionId, name: sessionName(s), description: `${s.backend ?? 'harness'}${s.running ? ' · 回复中' : ''}`, favorite: this.pinned.includes(s.sessionId), backend: s.backend ?? 'harness', count: 0, archived: archived.has(s.sessionId) }))
    this.listener(JSON.stringify({
      sessionKey, stagedFiles: this.stagedFiles.filter(row => row.scope === sessionKey).map(({scope,...row}) => row),
      terminalRaw: this.terminalRaw, terminalChunk: this.terminalChunk, terminalReset: this.terminalReset, terminalRenderRevision: this.terminalRenderRevision, botTarget: this.botTarget, botReadOnly: this.botState?.readOnly === undefined ? '' : this.botState.readOnly || strings.bots.sessionUnavailable, botView: this.botView, botExtras: [...this.botHistory, ...this.botExtras],
      botAsides: this.botState ? botObjects(this.botState.btwCards?.[this.botTarget]).filter(row => row.botId === this.botTarget && row.partId === this.session?.sessionId).map(row => ({ id: text(row.id), title: text(row.question), text: text(row.answer) || text(row.error), state: text(row.status) })) : [],
      botReport: this.botReport, botModelOptions: this.botModelOptions, botEffortOptions: this.botEffortOptions,
      botDefinitions: this.botState?.bots ?? [], botRooms: this.botState?.rooms ?? [],
      botApprovals: (this.botState?.approvals ?? []).map(row => ({ id: text(row.id), title: text(row.tool), detail: text(row.reason), session: text(row.botId) })),
      botQuestions: Object.entries(this.botState?.questions ?? {}).flatMap(([session,row]) => {
        if (!row || typeof row !== 'object') return []
        const value = row as Record<string, unknown>
        return [{ id: text(value.id), title: text(value.question) || text(value.text), detail: text(value.description), session }]
      }),
      taskDefinitions: this.scheduleEntries, autoConnectHost: this.autoConnectHost, draftRevision: this.draftRevision,
      failedSends: this.failedSends.filter(row => row.scope === this.sessionKey()).map(({image, images, mediaType, scope, ...row}) => ({...row, hasImage: !!image || !!images?.length})),
      pinnedSessionIds: this.pinned, hostDirectory: this.hostDirectory,
      activity: { rows: this.activityRows(), jobs: this.activity.jobs, loading: this.activity.loading, error: this.activity.error, output: this.activity.output, outputJob: this.activity.outputJob, lossy: this.activity.lossy },
      statusBarVisible: this.statusBarVisible, defaultPermission: this.defaultPermission,
      resumeSessionEnabled: this.browse.resume,
      readingPosition: this.session ? this.browse.read(this.browseScope(), this.session.sessionId) : { key: '', offset: 0, atBottom: true } as ReadingPosition,
      ...imageInputLimits(this.session),
      appVersion: HARMONY_VERSION, updateVersion: this.updateVersion, backgroundActive: residentTaskActive(), backgroundError: residentTaskError(), downloadBusy: this.downloadBusy, downloadBytes: this.downloadBytes,
      view: this.view, server: this.server, account: this.account, busy: this.busy, connected: this.connected,
      status: this.status, error: this.translate(this.error), notice: this.translate(this.notice), running: this.running, hasMore: this.hasMore,
      recovering: this.willRetry(), canReconnect: this.host !== undefined && !this.connected && this.phase !== 'connecting',
      sessionBackend: this.session?.backend ?? 'harness',
      hostName: this.host?.name ?? '',
      autoConnectName: this.lastConnectedDeviceId.length > 0 && this.devices.some(d => d.deviceId === this.lastConnectedDeviceId)
        ? this.devices.find(d => d.deviceId === this.lastConnectedDeviceId)!.name : '',
      qrUrl: this.qr?.scanUrl ?? '',
      candidate: this.candidate ? { id: this.candidate.deviceId, name: this.candidate.name, fingerprint: this.candidate.fingerprint, trusted: this.candidate.trusted, online: this.candidate.online === true } : { id: '', name: '', fingerprint: '', trusted: false, online: false },
      devices: this.devices.map(d => ({ id: d.deviceId, name: d.name, description: `${d.platform} · ${d.online ? '在线' : '离线'}`, online: d.online, trusted: d.trusted })),
      workspaces: this.workspaces.filter(w => (w.backend ?? 'harness') === this.backend).map(w => ({
        id: w.workspaceId, name: w.title || w.path, description: `${w.backend ?? 'harness'} · ${w.path}`,
        favorite: this.favorites.includes(w.workspaceId), backend: w.backend ?? 'harness',
        count: w.sessionIds.filter(id => !archived.has(id)).length, archived: false,
      })),
      managedSessions: scoped(this.sessions),
      sessions: scoped((this.workspace ? visibleSessions.filter(s => sessionIds.has(s.sessionId)) : visibleSessions)
        .sort((a, b) => this.orderBy === 'updated' ? b.updatedAt - a.updatedAt : 0)),
      backends: this.backendTabs(),
      backend: this.backend, groupBy: this.groupBy, orderBy: this.orderBy, archiveFilter: this.archiveFilter,
      archivedCount: this.archived.length,
      overview: this.overviewRows(archived), workspaceOverview: this.overviewRows(archived, 'workspace'),
      title: this.view === 'chat' ? (this.session ? sessionName(this.session) : '新对话') : this.view === 'sessions' ? this.workspace?.title ?? '会话' : this.host?.name ?? 'DSH Remote',
      workspaceTitle: (this.workspace ?? this.workspaces.find(row => row.sessionIds.includes(this.session?.sessionId ?? '')))?.title ?? '未分组',
      rows, modelWarning: this.modelWarning,
      draft: this.drafts[sessionKey] ?? '',
      queue: queueRows, modes: this.modes, permissions: this.permissions, panelWarning: this.panelWarning,
      skills: this.skills, filePath: this.filePath, files: this.files,
      filePreview: this.filePreview === undefined ? {
        path: '', name: '', kind: 'text', text: '', lines: 0, eof: true,
        data: '', mimeType: '', missingFonts: [], error: '', offset: 1,
      } : this.filePreview,
      compactHistory: this.compactHistory, children: this.childRows(), info: this.info,
      languagePreference: this.languagePreference, themePreference: this.themePreference,
      typographyDensity: this.typographyDensity,
      notificationsEnabled: this.notificationsEnabled,
      transportPreference: this.transportPreference,
      plugins: this.pluginRows, settingsWritable: this.settingsWritable,
      form: this.formRows, formTitle: this.formTitle, formResettable: this.formOverridden.length > 0,
      tasks: this.taskRows, records: this.recordRows, recordsTitle: this.recordsTitle,
      bots: this.bots,
      networkSections: this.networkSections,
      terminals: this.terminals.map((item: TerminalInfo): TerminalRow => ({
        id: item.id,
        title: terminalLabel(item),
        shell: item.shell?.name ?? '',
        state: item.state,
      })),
      activeTerminalId: this.activeTerminalId ?? '',
      terminalScreen: this.terminalScreen,
      terminalWritable: this.terminalWritable,
      terminalStatus: this.terminalStatus,
      terminalError: this.terminalError,
      terminalBusy: this.terminalBusy,
      prompts: this.prompts.map((row: CustomPrompt): PromptRow =>
        ({ id: row.id, title: row.title, text: row.text, builtIn: this.isBuiltIn(row.id) })),
      sessionBlank: this.sessionIsBlank(),
      currentMode: this.session?.agentPreset ?? '',
      workspaceOptions: this.workspaces.filter((row: WorkspaceView) => (row.backend ?? 'harness') === this.backend)
        .map((row: WorkspaceView): CatalogRow => ({
          id: row.workspaceId, name: row.title || row.path, description: row.path,
          favorite: this.favorites.includes(row.workspaceId), backend: row.backend ?? 'harness',
          count: row.sessionIds.length, archived: false,
        })),
      models: (this.models?.groups ?? []).flatMap(group => group.models.map(model => ({ id: `${group.id}/${model.id}`, provider: group.id, model: model.id, name: `${group.name} · ${model.name}`, efforts: model.reasoning?.efforts ?? [] }))),
      selectedModel: this.models ? `${this.models.current.provider}/${this.models.current.model}` : '',
    }))
    this.ensureRecovery().update()
    this.syncTaskNotifications()
  }
}
/** Plugins this port renders natively; the wording follows the phone's language. */
function harmonyAdaptedPlugins(): Readonly<Record<string, AdaptedPluginInfo>> {
  return {
    'deepseek-harness-intelligent-ui': {
      title: 'Intelligent UI', feature: (): string => strings.plugins.intelligentUiFeature, settingsSince: '0.2.10',
    },
  }
}
/** The plugin page's sections, in Android's order. */
const PLUGIN_SECTIONS: Array<{ category: PluginCategory; title: () => string; hint: () => string }> = [
  { category: 'remote', title: (): string => strings.plugins.categoryRemote, hint: (): string => strings.plugins.categoryRemoteHint },
  { category: 'installed', title: (): string => strings.plugins.categoryInstalled, hint: (): string => '' },
  { category: 'experimental', title: (): string => strings.plugins.categoryExperimental, hint: (): string => '' },
]
/** Android's frequency column; these labels are short enough to build without Intl. */
function scheduleLabel(entry: ScheduleCatalogEntry): string {
  const time = (entry.time ?? '').replace(/\.\d+$/u, '').replace(/:00$/u, '')
  if (entry.kind === 'daily') return strings.automation.frequencyDaily(time, entry.timeZone)
  if (entry.kind === 'weekly') return strings.automation.frequencyWeekly((entry.weekdays ?? []).join(', '), time, entry.timeZone)
  if (entry.kind === 'every') {
    const seconds = entry.everySeconds ?? 60
    return seconds % 3600 === 0
      ? strings.automation.frequencyEvery(seconds / 3600, 'h')
      : strings.automation.frequencyEvery(Math.round(seconds / 60), 'm')
  }
  if (entry.kind === 'cron') return strings.automation.frequencyCron(entry.expression ?? '')
  return strings.automation.frequencyOnce
}
/** Schedule stamps are assembled by hand because Ark's Intl coverage varies by device. */
function stampOf(value: string): string {
  const time = Date.parse(value)
  if (Number.isNaN(time)) return value
  const date = new Date(time)
  return `${dayOf(time)} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
}
/** A settings field crosses the ArkUI boundary as text and is coerced back on save. */
function fieldText(value: unknown, field: SchemaField): string {
  if (field.kind === 'boolean') return value === true ? 'true' : 'false'
  if (field.kind === 'string-list') {
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string').join('\n') : ''
  }
  if (typeof value === 'number' || typeof value === 'string') return String(value)
  return ''
}
function fieldValue(kind: string, text: string): unknown {
  if (kind === 'boolean') return text === 'true'
  if (kind === 'number') { const value = Number(text.trim()); return Number.isFinite(value) ? value : 0 }
  if (kind === 'string-list') return text.split('\n').map(item => item.trim()).filter(item => item.length > 0)
  return text
}
/** Ark's Intl coverage varies by device, so dates and digit groups are formatted by hand. */
function dayOf(time: number): string {
  const date = new Date(time)
  return `${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}`
}
function group(value: number): string { return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ',') }
function minimumSeq(events: Array<{ event: { seq: number } }>): number | undefined { return events.length ? Math.min(...events.map(e => e.event.seq)) : undefined }
/** Official Harness rows keep the name in projections; the top-level title is usually absent. */
function sessionName(session: RemoteSession): string { return resolveSessionDisplayTitle(session) ?? '新对话' }
/** History without an upstream timestamp must not inherit the time it was loaded. */
function timeOf(item: ChatItem): number | undefined {
  if (item.nativeTime !== undefined && Number.isFinite(item.nativeTime) && item.nativeTime > 0) return item.nativeTime
  if (item.nativeSeq === undefined && Number.isFinite(item.createdAt) && item.createdAt > 0) return item.createdAt
  return undefined
}
function clockOf(item: ChatItem): string {
  const time = timeOf(item)
  if (time === undefined) return '--:--'
  const date = new Date(time)
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
}
/** Same disclosure preview as the Android trajectory entry. */
function previewOf(item: ChatItem): string {
  if (item.kind !== 'message') return ''
  const source = item.text.trim() || item.reasoning?.trim()
    || (item.turnEnd?.reason === 'failed' ? (item.turnEnd.detail || '回复失败') : '')
    || ((item.images?.length ?? 0) > 0 ? '图片' : '无文本内容')
  return source.replace(/^#{1,6}\s+/gm, '').replace(/\*\*|`/g, '').trim()
}
function tokensOf(item: ChatItem): string {
  if (item.kind !== 'message' || item.usage === undefined) return ''
  const total = item.usage.totalTokens ?? (item.usage.inputTokens + item.usage.outputTokens)
  return total > 0 ? `${group(total)} tokens` : ''
}
function usageOf(item: ChatItem, session?: RemoteSession, current?: SessionModels['current']): string {
  if (item.kind !== 'message' || !item.usage) return ''
  const usage = item.usage, labels = strings.messageActions
  const model = (item as unknown as { model?: string }).model ?? (usage as { model?: string }).model
    ?? (current ? [current.provider,current.model].filter(Boolean).join('/') : session?.backend)
  const lines = model ? [`${labels.providerModel}: ${model}`] : []
  lines.push(`${labels.uncachedInput}: ${group(Math.max(0,(usage.inputTokens ?? 0)-(usage.cacheReadTokens ?? 0)))} tok`)
  if (usage.cacheReadTokens) lines.push(`${labels.cacheRead}: ${group(usage.cacheReadTokens)} tok`)
  if (usage.cacheWriteTokens) lines.push(`${labels.cacheWrite}: ${group(usage.cacheWriteTokens)} tok`)
  lines.push(`${labels.output}: ${group(usage.outputTokens ?? 0)} tok`)
  if (usage.reasoningTokens) lines.push(`${labels.reasoning}: ${group(usage.reasoningTokens)} tok`)
  return lines.join('\n')
}
function safeError(error: unknown): string {
  const code = (error as { code?: string })?.code
  if (code === 'PEER_IDENTITY_MISMATCH') return '主机身份验证失败，连接已阻止。'
  if (code === 'AUTH_REQUIRED' || code === 'AUTH_EXPIRED') return '授权已失效，请重新登录。'
  // Server error codes share Android's localized table; the raw English text is never useful on a phone.
  const friendly = code === undefined ? undefined : (strings.errors as unknown as Record<string, string>)[code]
  if (friendly !== undefined) return friendly
  // Some Server builds carry only the message; an offline Host must not read as a generic failure.
  if (/is offline/i.test(error instanceof Error ? error.message : '')) {
    return (strings.errors as unknown as Record<string, string>).DEVICE_OFFLINE
  }
  // HTTP adapters and upstream API errors already redact raw network payloads.
  const message = error instanceof Error ? error.message : '操作失败，请重试。'
  return message.length < 240 && !/Bearer |eyJ[A-Za-z0-9_-]{20}|privateKey|refreshToken|accessToken/.test(message) ? message : '操作失败，请检查网络与主机状态。'
}

export function connectionPath(mode: string | undefined): string {
  const names: Record<string, string> = {
    Relay: '服务器转发',
    WebRTC: '点对点直连',
    P2P: '点对点直连',
    LAN: '局域网直连',
    TURN: 'TURN 中继',
    Disconnected: '未连接',
  }
  return mode === undefined ? '不可用' : (names[mode] ?? mode)
}

export function controlServerName(value: string): string {
  try { return new URL(value).host }
  catch { return '不可用' }
}

export function protocolText(protocol: string, relayProtocol?: string): string {
  return relayProtocol === undefined
    ? protocol.toUpperCase()
    : `${protocol.toUpperCase()} · TURN/${relayProtocol.toUpperCase()}`
}

export function candidatePathText(localType?: string, localScope?: string, remoteType?: string, remoteScope?: string): string {
  const candidate = (candidateType?: string, scope?: string) => [candidateType, scope].filter(Boolean).join(' · ') || '未知'
  return `${candidate(localType, localScope)} → ${candidate(remoteType, remoteScope)}`
}

export function formatBitrate(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)} Mbps`
  if (value >= 1_000) return `${Math.round(value / 1_000)} Kbps`
  return `${Math.round(value)} bps`
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
}
