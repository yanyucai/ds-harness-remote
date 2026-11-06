/** Mirrors the runtime's JSON input for actions that carry a single field. */
export interface ActionInput { id?: string; mode?: string; backend?: string; rating?: string; name?: string; text?: string; offset?: number; enabled?: boolean }
export interface ActivityRow { id: string; category: string; title: string; detail: string; status: string; session: string }
export interface JobRow { id: string; label: string; status: string; progress?: string; detail?: string; startedAt?: number; finishedAt?: number }
export interface ActivityState { rows: ActivityRow[]; jobs: JobRow[]; loading: boolean; error: string; output: string; outputJob: string; lossy: boolean }
export interface DirectoryEntry { name: string; path: string; hidden?: boolean }
export interface HostDirectory { path: string; home?: string; crumbs?: DirectoryEntry[]; entries: DirectoryEntry[]; truncated?: boolean }
export interface TaskDefinition { id: string; sessionId: string; kind: string; title: string; prompt: string; scheduledAt: string; status: string; afterSeconds?: number; everySeconds?: number; time?: string; timeZone?: string; weekdays?: number[]; expression?: string }
export interface BotDefinition { id: string; sessionId: string; name: string; role: string; instructions: string; model: string; effort: string; main: boolean }
export interface BotRoom { id: string; name: string; members: string[]; notice: string; admin: string; paused?: boolean }
export interface BotRequest { id: string; title: string; detail: string; session: string }
export interface ReadingPosition { key: string; offset: number; atBottom: boolean }
export interface PresetRow { id: string; name: string; description: string; current: boolean; broken: boolean }
export interface SkillRow { id: string; name: string; description: string }
export interface FileRow { id: string; name: string; kind: string; size: string }
export interface FilePreview {
  path: string; name: string; kind: string; text: string; lines: number; eof: boolean;
  data: string; mimeType: string; missingFonts: string[]; error: string; offset: number;
}
export interface InfoRow { label: string; value: string }
/** One plugin-page line: a section header, a bundle, or one of its components. */
export interface PluginRow {
  id: string; level: string; parent: string; name: string; description: string; category: string
  enabled: boolean; available: boolean; readOnly: boolean; official: boolean; version: string
  error: string; feature: string; upgrade: string; form: string
}
export interface FormRow { key: string; kind: string; value: string; description: string; bounds: string; secret: boolean }
export interface TaskRow {
  id: string; session: string; title: string; prompt: string; status: string; active: boolean
  schedule: string; kind: string; next: string; last: string
}
export interface RecordRow { id: string; delivered: string; scheduled: string; prompt: string }
export interface QueueRow { id: string; preview: string; host: boolean }
export interface PromptRow { id: string; title: string; text: string; builtIn: boolean }
export interface CatalogRow { id: string; name: string; description: string; favorite: boolean; backend: string; count: number; archived: boolean }
export interface DeviceRow extends CatalogRow { online: boolean; trusted: boolean }
export interface BackendTab { id: string; name: string; count: number }
export interface OverviewRow {
  id: string; kind: string; target: string; name: string; description: string; meta: string
  favorite: boolean; expanded: boolean; remaining: number; selected: boolean; hidden: boolean
}
export interface QuestionOption { label: string; description?: string }
export interface UserQuestion { id: string; question: string; detail?: string; header?: string; options?: QuestionOption[]; multiSelect?: boolean }
export interface QuestionAnswer { id: string; selected: string[]; custom?: string }
export interface UiArtifactRow {
  uiId: string; kind: string; title: string; version: number;
  turn: string; updatedTurn: string; summary: string; html: string; payload: string; actionText: string;
}
export interface BotReplyRow { name: string; color: string; text: string; kind: string }
export interface BotEntryRow { id: string; name: string; role: string; model: string; color: string; main: boolean }
export interface TimelineRow {
  heartbeatRaw?: string
  turnStatus?: string; turnDetail?: string
  id: string; kind: string; title: string; text: string; detail: string; pending: boolean; images: string[]
  questions?: UserQuestion[]; uiArtifacts?: UiArtifactRow[]; updatedArtifacts?: string[]; botReplies?: BotReplyRow[]
  category: string; turn: string; clock: string; preview: string; attachments: number
  actionable: boolean; feedback: string; tokens: string; usageDetail: string
}
export interface ModelEffort { id: string; name: string }
export interface ModelRow { id: string; provider: string; model: string; name: string; efforts: ModelEffort[] }
export interface Candidate { id: string; name: string; fingerprint: string; trusted: boolean; online: boolean }
export interface TerminalRow { id: string; title: string; shell: string; state: string }
export interface NetworkRow { label: string; value: string; mono?: boolean }
export interface NetworkSection { title: string; rows: NetworkRow[] }
export interface NamedOption { id: string; name: string }
export interface BotExtra { id: string; title: string; text: string; state: string; view?: string }
export interface StagedFile { id: string; name: string; path: string }
export interface FailedSend { id: string; text: string; error: string; state: string; hasImage: boolean }
export interface ViewState {
  imageAllowed: boolean; imageMaxCount: number; imageMaxBytes: number;
  appVersion: string; updateVersion: string; backgroundActive: boolean; backgroundError: string; downloadBusy: boolean; downloadBytes: number;
  botReport: BotExtra[]; botModelOptions: NamedOption[]; botEffortOptions: NamedOption[];
  stagedFiles: StagedFile[];
  managedSessions: CatalogRow[]; workspaceTitle: string; botTarget: string; botReadOnly: string; botView: string; botExtras: BotExtra[]; botAsides: BotExtra[];
  draftRevision: number; autoConnectHost: boolean; failedSends: FailedSend[];
  statusBarVisible: boolean; defaultPermission: string;
  pinnedSessionIds: string[]; terminalRaw: string; terminalChunk: string; terminalReset: boolean; terminalRenderRevision: number; hostDirectory: HostDirectory; activity: ActivityState;
  botDefinitions: BotDefinition[]; botRooms: BotRoom[]; botApprovals: BotRequest[]; botQuestions: BotRequest[]; taskDefinitions: TaskDefinition[];
  resumeSessionEnabled: boolean; readingPosition: ReadingPosition;
  sessionKey: string; view: string; server: string; account: string; busy: boolean; connected: boolean;
  status: string; error: string; notice: string; running: boolean; hasMore: boolean;
  qrUrl: string; candidate: Candidate; devices: DeviceRow[]; workspaces: CatalogRow[];
  sessions: CatalogRow[]; title: string; rows: TimelineRow[]; models: ModelRow[];
  modelWarning: string; selectedModel: string;
  backends: BackendTab[]; backend: string; overview: OverviewRow[]; workspaceOverview: OverviewRow[];
  groupBy: string; orderBy: string; archiveFilter: string; archivedCount: number;
  draft: string; queue: QueueRow[]; modes: PresetRow[]; permissions: PresetRow[]; panelWarning: string;
  skills: SkillRow[]; filePath: string; files: FileRow[]; filePreview: FilePreview;
  compactHistory: boolean; children: CatalogRow[]; info: InfoRow[];
  languagePreference: string; themePreference: string; typographyDensity: string;
  notificationsEnabled: boolean;
  transportPreference: string;
  plugins: PluginRow[]; settingsWritable: boolean;
  form: FormRow[]; formTitle: string; formResettable: boolean;
  tasks: TaskRow[]; records: RecordRow[]; recordsTitle: string;
  terminals: TerminalRow[]; activeTerminalId: string;
  terminalScreen: string; terminalWritable: boolean; terminalStatus: string; terminalError: string; terminalBusy: boolean;
  bots: BotEntryRow[];
  networkSections: NetworkSection[];
  prompts: PromptRow[]; sessionBlank: boolean; currentMode: string; workspaceOptions: CatalogRow[];
  recovering: boolean; canReconnect: boolean; sessionBackend: string; autoConnectName: string;
  hostName: string;
}
export function emptyState(): ViewState {
  return {
    imageAllowed: true, imageMaxCount: 4, imageMaxBytes: 8388608,
    appVersion: '', updateVersion: '', backgroundActive: false, backgroundError: '', downloadBusy: false, downloadBytes: 0,
    botReport: [], botModelOptions: [], botEffortOptions: [],
    stagedFiles: [],
    managedSessions: [], workspaceTitle: '', botTarget: '', botReadOnly: '', botView: '', botExtras: [], botAsides: [],
    draftRevision: 0, autoConnectHost: true, failedSends: [],
    statusBarVisible: true, defaultPermission: 'default',
    pinnedSessionIds: [], terminalRaw: '', terminalChunk: '', terminalReset: true, terminalRenderRevision: 0, hostDirectory: { path: '', entries: [] },
    activity: { rows: [], jobs: [], loading: false, error: '', output: '', outputJob: '', lossy: false },
    botDefinitions: [], botRooms: [], botApprovals: [], botQuestions: [], taskDefinitions: [],
    resumeSessionEnabled: false, readingPosition: { key: '', offset: 0, atBottom: true },
    sessionKey: '', view: 'login', server: 'https://dsh.r2049.cn', account: '', busy: true, connected: false,
    status: '初始化安全存储', error: '', notice: '', running: false, hasMore: false, qrUrl: '',
    candidate: { id: '', name: '', fingerprint: '', trusted: false, online: false }, devices: [], workspaces: [],
    sessions: [], title: 'DSH Remote', rows: [], models: [], modelWarning: '', selectedModel: '',
    backends: [], backend: 'harness', overview: [], workspaceOverview: [], groupBy: 'workspace', orderBy: 'updated',
    archiveFilter: 'hidden', archivedCount: 0,
    draft: '', queue: [], modes: [], permissions: [], panelWarning: '', prompts: [],
    skills: [], filePath: '', files: [], filePreview: {
      path: '', name: '', kind: 'text', text: '', lines: 0, eof: true,
      data: '', mimeType: '', missingFonts: [], error: '', offset: 1,
    },
    compactHistory: false, children: [], info: [],
    languagePreference: 'zh-CN', themePreference: 'system', typographyDensity: 'compact',
    notificationsEnabled: true,
    transportPreference: 'auto',
    plugins: [], settingsWritable: false, form: [], formTitle: '', formResettable: false,
    tasks: [], records: [], recordsTitle: '',
    terminals: [], activeTerminalId: '',
    terminalScreen: '', terminalWritable: false, terminalStatus: '', terminalError: '', terminalBusy: false,
    bots: [],
    networkSections: [],
    sessionBlank: false, currentMode: '', workspaceOptions: [],
    recovering: false, canReconnect: false, sessionBackend: 'harness', autoConnectName: ''
    , hostName: ''
  }
}
