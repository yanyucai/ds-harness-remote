import { saveWorkspaceFile } from '../components/FileSave'
import photoAccessHelper from '@ohos.file.photoAccessHelper'
import cameraPicker from '@ohos.multimedia.cameraPicker'
import cameraKit from '@ohos.multimedia.camera'
import picker from '@ohos.file.picker'
import fileUri from '@ohos.file.fileuri'
import common from '@ohos.app.ability.common'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import promptAction from '@ohos.promptAction'
import { AlignmentPanel } from '../components/AlignmentPanel'
import { LocalSurface } from '../components/LocalSurface'
import { RtcSurface } from '../components/RtcSurface'
import { runtime } from '../RuntimeHost'
import { ViewState, TimelineRow, CatalogRow, DeviceRow, ModelRow, ModelEffort, UserQuestion, QuestionOption, QuestionAnswer, emptyState } from '../models/ViewState'
import { ActivityRow, JobRow, BackendTab, OverviewRow, ActionInput, StagedFile, BotExtra, FailedSend, PresetRow, QueueRow, PromptRow } from '../models/ViewState'
import { SkillRow, FileRow, InfoRow, PluginRow, FormRow, TaskRow, RecordRow, TerminalRow, UiArtifactRow, BotReplyRow, BotEntryRow, NetworkRow, NetworkSection } from '../models/ViewState'

interface PromptAttachment { data: string; mediaType: string; name?: string }
interface BotPending { id: string }
interface SurfaceEvent { type?: string; url?: string; text?: string; data?: string; cols?: number; rows?: number }
interface PrefOption { id: string; name: string }

@Component
struct QuestionForm {
  @Prop questions: UserQuestion[] = []
  onSubmit: (answers: QuestionAnswer[]) => void = () => {}
  @State selected: string[][] = []
  @State custom: string[] = []

  aboutToAppear(): void {
    this.selected = this.questions.map((): string[] => [])
    this.custom = this.questions.map((): string => '')
  }
  private answers(): QuestionAnswer[] {
    return this.questions.map((question: UserQuestion, index: number): QuestionAnswer => ({
      id: question.id, selected: this.selected[index] || [], custom: this.custom[index] || ''
    }))
  }
  build() {
    Column({ space: 12 }) {
      ForEach(this.questions, (question: UserQuestion, index: number) => {
        Text(question.question).fontSize(16).width('100%')
        if (question.detail) { Text(question.detail).fontSize(13).width('100%') }
        ForEach(question.options || [], (option: QuestionOption) => {
          Button((this.selected[index]?.includes(option.label) ? '✓ ' : '') + option.label)
            .fontSize(14).width('100%').backgroundColor(this.selected[index]?.includes(option.label) ? '#4B78E6' : $r('sys.color.comp_background_tertiary'))
            .fontColor(this.selected[index]?.includes(option.label) ? Color.White : $r('sys.color.font_primary'))
            .onClick(() => {
              this.selected = this.selected.map((values: string[], row: number): string[] => {
                if (row !== index) return values
                if (values.includes(option.label)) return values.filter((value: string) => value !== option.label)
                return question.multiSelect ? values.concat([option.label]) : [option.label]
              })
            })
        })
        TextInput({ text: this.custom[index] || '', placeholder: runtime.translate('补充回答（可选）') })
          .onChange((value: string) => { this.custom = this.custom.map((old: string, row: number) => row === index ? value : old) })
      })
      Button(runtime.translate('提交回答')).backgroundColor('#4B78E6').onClick(() => { this.onSubmit(this.answers()) })
    }.width('100%')
  }
}

@Component
struct TimelineCard {
  @Prop scope: string = ''
  @Prop dark: boolean = false
  @State imagePreview: string = ''
  @Prop row: TimelineRow
  @Prop density: string = 'compact'
  onApproval: (id: string, decision: string) => void = () => {}
  onQuestion: (id: string, answers: QuestionAnswer[]) => void = () => {}
  onFork: (id: string) => void = () => {}
  onFeedback: (id: string, rating: string) => void = () => {}
  @State expanded: boolean = false

  @Builder
  fullImage() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(this.imagePreview).width('100%').height('100%').objectFit(ImageFit.Contain)
      Button(runtime.translate('关闭')).onClick(() => { this.imagePreview = '' })
    }.backgroundColor(Color.Black).width('100%').height('100%')
  }
  private fs(size: number): number {
    return this.density === 'standard' ? size : Math.max(10, size - 1)
  }

  build() {
    Column({ space: 10 }) {
      Text(this.row.title)
        .fontSize(this.fs(13)).fontWeight(FontWeight.Medium)
        .fontColor(this.row.kind === 'approval' ? '#B66A16' : $r('sys.color.font_secondary'))
        .width('100%')
      if (this.row.turnStatus) {
        Text(runtime.translate(this.row.turnStatus === 'failed' ? '回复失败' : this.row.turnStatus === 'stopped' ? '已停止' : '已完成'))
          .fontSize(this.fs(12)).width('100%')
          .fontColor(this.row.turnStatus === 'failed' ? '#C64B43' : $r('sys.color.font_secondary'))
      }
      if (this.row.text) {
        LocalSurface({ scope: this.scope, dark: this.dark, payload: JSON.stringify({ text: this.row.text, dark: this.dark, density: this.density, copyLabel: runtime.translate('复制') }),
          onAction: async (raw: string): Promise<boolean> => {
            const value: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
            return runtime.perform('openLink', JSON.stringify({ text: value.url }))
          } })
      }
      if (this.row.turnDetail && this.row.turnDetail !== this.row.text) {
        Text(this.row.turnDetail).fontSize(this.fs(13)).width('100%').copyOption(CopyOptions.LocalDevice)
          .fontColor(this.row.turnStatus === 'failed' ? '#C64B43' : $r('sys.color.font_secondary'))
      }
      if (this.row.attachments > this.row.images.length) {
        Button(`加载图片 (${this.row.attachments})`).onClick(() => { runtime.perform('imageLoad', JSON.stringify({ id: this.row.id })).catch(() => {}) })
      }
      ForEach(this.row.images, (source: string) => {
        if (source.startsWith('data:image/')) {
          Image(source).width('100%').constraintSize({ maxHeight: 280 }).objectFit(ImageFit.Contain)
            .onClick(() => { this.imagePreview = source })
            .bindContentCover(this.imagePreview.length > 0, this.fullImage())
        }
      })
      if (this.row.heartbeatRaw) {
        Button(runtime.translate(this.expanded ? '收起原文' : '查看原文')).onClick(() => { this.expanded = !this.expanded })
        if (this.expanded) Text(this.row.heartbeatRaw).fontSize(this.fs(12)).fontFamily('monospace').width('100%').copyOption(CopyOptions.LocalDevice)
      }
      if (this.row.detail) {
        Text(runtime.translate(this.expanded ? '收起详情 ∧' : '查看思考 / 详情 ∨')).fontSize(this.fs(13))
          .fontColor('#4B78E6').width('100%').onClick(() => { this.expanded = !this.expanded })
        if (this.expanded) {
          Text(this.row.detail).fontSize(this.fs(13)).lineHeight(this.fs(20)).fontColor($r('sys.color.font_secondary'))
            .copyOption(CopyOptions.LocalDevice).width('100%')
        }
      }
      if (this.row.actionable) {
        Row({ space: 10 }) {
          Button(runtime.translate('引用')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#4B78E6')
            .onClick(() => { runtime.perform('quote', JSON.stringify({ id: this.row.id })).catch(() => {}) })
          Button(runtime.translate('复制')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#4B78E6')
            .onClick(() => { runtime.perform('copyMessage', JSON.stringify({ id: this.row.id })).catch(() => {}) })
          Button(runtime.translate('分享')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#4B78E6')
            .onClick(() => { runtime.perform('shareMessage', JSON.stringify({ id: this.row.id })).catch(() => {}) })
          Button(runtime.translate('分支')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#4B78E6')
            .onClick(() => { this.onFork(this.row.id) })
          Button(runtime.translate(this.row.feedback === 'positive' ? '已赞' : '赞')).fontSize(12).height(30)
            .backgroundColor(this.row.feedback === 'positive' ? '#20386B' : Color.Transparent)
            .fontColor(this.row.feedback === 'positive' ? '#8FB0F7' : $r('sys.color.font_secondary'))
            .onClick(() => { this.onFeedback(this.row.id, 'positive') })
          Button(runtime.translate(this.row.feedback === 'negative' ? '已踩' : '踩')).fontSize(12).height(30)
            .backgroundColor(this.row.feedback === 'negative' ? '#4A2C2C' : Color.Transparent)
            .fontColor(this.row.feedback === 'negative' ? '#E2938B' : $r('sys.color.font_secondary'))
            .onClick(() => { this.onFeedback(this.row.id, 'negative') })
          Blank()
          Text(this.row.tokens).fontSize(11).fontColor($r('sys.color.font_secondary'))
            .accessibilityText(runtime.translate('本轮用量') + ' ' + this.row.tokens)
            .onClick(() => { if (this.row.usageDetail) promptAction.showDialog({ title: runtime.translate('本轮用量'), message: this.row.usageDetail, buttons: [{ text: runtime.translate('关闭'), color: '#4B78E6' }] }) })
          Text(this.row.clock).fontSize(11).fontColor($r('sys.color.font_secondary'))
        }.width('100%').alignItems(VerticalAlign.Center)
      } else if (this.row.clock.length > 0) {
        Text(this.row.clock).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
          .textAlign(this.row.title === '你' ? TextAlign.End : TextAlign.Start)
      }
      if (this.row.kind === 'question' && this.row.pending) {
        QuestionForm({ questions: this.row.questions || [], onSubmit: (answers: QuestionAnswer[]) => { this.onQuestion(this.row.id, answers) } })
      }
      if (this.row.uiArtifacts && this.row.uiArtifacts.length > 0) {
        ForEach(this.row.uiArtifacts, (ui: UiArtifactRow) => {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('🎛').fontSize(16)
              Text(ui.title).fontSize(14).fontWeight(FontWeight.Bold).layoutWeight(1)
              Text(`v${ui.version}`).fontSize(11).fontColor('#4B78E6')
                .backgroundColor('#1A4B78E6').padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(4)
            }.width('100%')

            if (ui.summary.length > 0) {
              Text(ui.summary).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            }

            LocalSurface({ kind: 'intelligent', payload: ui.payload,
              onAction: async (raw: string): Promise<boolean> => {
                const message: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
                return runtime.perform('uiAction', JSON.stringify({ id: ui.uiId, name: String(ui.version), mode: this.scope, text: message.text }))
              } })
            if (false) {
              Row() {
                Blank()
                Button(runtime.translate('执行操作')).fontSize(12).height(30).backgroundColor('#4B78E6')
                  .onClick(() => {
                    promptAction.showDialog({
                      title: '发送 UI 操作？',
                      message: `确定要向会话发送以下操作吗？\n\n${ui.actionText}`,
                      buttons: [
                        { text: '取消', color: '#888888' },
                        { text: '发送', color: '#4B78E6' }
                      ]
                    }).then((result: promptAction.ShowDialogSuccessResponse) => {
                      if (result.index === 1) {
                        runtime.perform('uiAction', JSON.stringify({ text: ui.actionText })).catch(() => {})
                      }
                    })
                  })
              }.width('100%')
            }
          }
          .width('100%').padding(12).borderRadius(12)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .margin({ top: 4, bottom: 4 })
        }, (ui: UiArtifactRow) => `ui|${ui.uiId}|${ui.version}`)
      }
      if (this.row.updatedArtifacts && this.row.updatedArtifacts.length > 0) {
        ForEach(this.row.updatedArtifacts, (hint: string) => {
          Text(hint).fontSize(12).fontColor($r('sys.color.font_secondary')).margin({ top: 4 })
        }, (hint: string) => hint)
      }
      if (this.row.botReplies && this.row.botReplies.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.row.botReplies, (reply: BotReplyRow) => {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text(reply.name).fontSize(12).fontWeight(FontWeight.Bold)
                  .fontColor(reply.color.length > 0 ? reply.color : '#4B78E6')
                if (reply.kind.length > 0 && reply.kind !== 'user') {
                  Text(reply.kind).fontSize(10).fontColor($r('sys.color.font_secondary'))
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 }).borderRadius(4)
                }
              }.width('100%')
              Text(reply.text).fontSize(this.fs(14)).lineHeight(this.fs(20))
                .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice).width('100%')
            }
            .width('100%').padding(10).borderRadius(10)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
          }, (reply: BotReplyRow, index: number) => `botReply|${index}|${reply.name}|${reply.text.length}`)
        }.width('100%').margin({ top: 4, bottom: 4 })
      }
      if (this.row.kind === 'approval' && this.row.pending) {
        Row({ space: 12 }) {
          Button(runtime.translate('拒绝')).type(ButtonType.Normal).borderRadius(12)
            .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
            .onClick(() => { this.onApproval(this.row.id, 'deny') })
          Button(runtime.translate('允许一次')).type(ButtonType.Normal).borderRadius(12).backgroundColor('#4B78E6')
            .onClick(() => { this.onApproval(this.row.id, 'allow_once') })
        }
        .width('100%').justifyContent(FlexAlign.End)
      }
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(16).borderRadius(18)
    .backgroundColor(this.row.title === '你' ? $r('sys.color.comp_background_tertiary') : $r('sys.color.comp_background_primary'))
  }
}

@Component
struct TraceEntry {
  @Prop row: TimelineRow
  label: string = ''
  onFork: (id: string) => void = () => {}
  onFeedback: (id: string, rating: string) => void = () => {}
  @State expanded: boolean = false

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.label).fontSize(12).fontColor($r('sys.color.font_secondary'))
        Text(runtime.translate(this.row.turn.length > 0 ? `轮次 ${this.row.turn}` : '')).fontSize(11)
          .fontColor($r('sys.color.font_secondary')).maxLines(1)
        Blank()
        Text(this.row.clock).fontSize(11).fontColor($r('sys.color.font_secondary'))
        Text(this.expanded ? '⌄' : '›').fontSize(14).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      if (this.expanded) {
        TimelineCard({ row: this.row, onFork: this.onFork, onFeedback: this.onFeedback })
      } else {
        Text(this.row.preview).fontSize(13).maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary')).width('100%')
        if (this.row.attachments > 0) {
          Text(runtime.translate(`${this.row.attachments} 张图片`)).fontSize(11).fontColor($r('sys.color.font_secondary'))
        }
      }
    }.width('100%').padding(12).borderRadius(14)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .onClick(() => { this.expanded = !this.expanded })
  }
}

@Entry
@Component
struct Index {
  @State state: ViewState = emptyState()
  @State server: string = 'https://dsh.r2049.cn'
  @State email: string = ''
  @State password: string = ''
  @State draft: string = ''
  @State query: string = ''
  @State directory: string = ''
  @State image: string = ''
  @State promptImages: PromptAttachment[] = []
  @State mediaType: string = ''
  @State imageError: string = ''
  @State showModels: boolean = false
  @State selectedModel: number = 0
  @State effort: string = ''
  @State rename: string = ''
  @State traceMode: boolean = false
  @State traceQuery: string = ''
  @State traceCategory: string = 'all'
  @State showMore: boolean = false
  @State showPromptForm: boolean = false
  @State promptId: string = ''
  @State promptTitle: string = ''
  @State promptText: string = ''
  @State manageTarget: CatalogRow | undefined = undefined
  @State workspaceName: string = ''
  @State confirmDelete: string = ''
  @State confirmForget: boolean = false
  // Android keeps the session list in a drawer over the workspace page, and the
  // composer's 更多操作 as a stack of drill-down screens. Both are local overlay
  // state here: the runtime view stack stays workspaces / sessions / chat.
  @State drawerOpen: boolean = false
  @State drawerSearch: boolean = false
  @State drawerOptions: boolean = false
  @State panelPage: string = ''
  @State promptPage: string = ''
  @State showPrompts: boolean = false
  @State showChildren: boolean = false
  @State showInfo: boolean = false
  // Android's 插件 and 自动化任务 pages, plus their drill-downs, as local overlays.
  @State showPlugins: boolean = false
  @State showPluginForm: boolean = false
  @State showTasks: boolean = false
  @State showRecords: boolean = false
  @State alignmentPanel: string = ''
  @State expandedComposer: boolean = false
  @State pageWidth: number = 400
  @State pageHeight: number = 800
  @State showHostSwitcher: boolean = false
  @State showSettings: boolean = false
  @State savingFile: boolean = false
  @State fileSaveMessage: string = ''
  @State showBots: boolean = false
  @State showNetwork: boolean = false
  @State showTerminal: boolean = false
  @State terminalInput: string = ''
  @State taskFilter: string = 'all'
  @State confirmTask: string = ''
  @State formDraft: string[] = []
  @State formFlags: boolean[] = []
  private lastForm: string = ''
  private scroller: Scroller = new Scroller()
  private terminalScroll: Scroller = new Scroller()
  private lastView: string = ''
  private lastSession: string = ''
  private readingSession: string = ''
  private readingTimer: number = -1
  private restoringReading: boolean = false
  private firstVisibleRow: number = 0
  private pinnedToBottom: boolean = true
  private timelineSignature: string = ''

  aboutToAppear(): void {
    runtime.setListener((raw: string) => {
      const next: ViewState = JSON.parse(raw) as ViewState
      if (next.view !== this.lastView) { this.query = ''; this.traceMode = false; this.lastView = next.view }
      if (next.sessionKey !== this.lastSession) {
        // The outgoing conversation keeps its text draft; attachments never persist.
        if (this.lastSession.length > 0 && this.draft.length > 0) {
          runtime.perform('saveDraft', JSON.stringify({ id: this.lastSession, text: this.draft } as ActionInput)).catch(() => {})
        }
        this.draft = next.draft; this.image = ''; this.promptImages = []; this.lastSession = next.sessionKey
      }
      if (next.draftRevision !== this.state.draftRevision && next.sessionKey === this.lastSession) this.draft = next.draft
      // The settings form keeps its edits until the runtime publishes new values.
      const signature: string = next.form.map((row: FormRow): string => `${row.key}|${row.value}`).join('\n')
      if (signature !== this.lastForm) {
        this.lastForm = signature
        this.formDraft = next.form.map((row: FormRow): string => row.value)
        this.formFlags = next.form.map((row: FormRow): boolean => row.value === 'true')
      }
      this.state = next
      this.restoreReadingPosition()
      if (!this.server || (this.server === 'https://dsh.r2049.cn' && next.server)) this.server = next.server
      if (!next.connected) {
        this.alignmentPanel = ''
        this.image = ''; this.promptImages = []; this.showModels = false; this.traceMode = false
        this.expandedComposer = false
        this.showMore = false; this.showPromptForm = false; this.manageTarget = undefined
        // A drawer that lost its host must not stay open over the device list.
        this.drawerOpen = false; this.drawerSearch = false; this.drawerOptions = false
        this.showPrompts = false; this.panelPage = ''; this.promptPage = ''
        this.showChildren = false; this.showInfo = false
        this.showPlugins = false; this.showPluginForm = false
        this.showTasks = false; this.showRecords = false; this.confirmTask = ''
        this.showBots = false
        this.showNetwork = false
        this.showTerminal = false
      }
    })
    runtime.initialize().catch(() => {})
  }


  aboutToDisappear(): void {
    this.saveReadingPosition()
    if (this.readingTimer >= 0) clearTimeout(this.readingTimer)
  }

  private saveReadingPosition(): void {
    if (this.restoringReading || this.traceMode || this.state.view !== 'chat' || this.state.rows.length === 0) return
    try {
      this.pinnedToBottom = this.scroller.isAtEnd()
      const index: number = Math.max(0, this.firstVisibleRow - (this.state.hasMore ? 1 : 0))
      const row: TimelineRow = this.state.rows[Math.min(index, this.state.rows.length - 1)]
      runtime.perform('saveReadingPosition', JSON.stringify({
        id: this.state.sessionKey, key: row.id,
        offset: Math.max(0, this.scroller.currentOffset().yOffset), atBottom: this.pinnedToBottom
      })).catch(() => {})
    } catch {}
  }

  private restoreReadingPosition(): void {
    if (this.state.view !== 'chat') { this.readingSession = ''; this.timelineSignature = ''; return }
    if (this.traceMode || this.state.busy || !this.state.connected || this.state.rows.length === 0 || this.readingTimer >= 0) return
    const session: string = this.state.sessionKey
    const last: TimelineRow = this.state.rows[this.state.rows.length - 1]
    const signature: string = `${this.state.rows.length}|${last.id}|${last.text.length}|${last.detail.length}`
    const initial: boolean = this.readingSession !== session
    if (!initial && (!this.pinnedToBottom || this.timelineSignature === signature)) return
    this.timelineSignature = signature
    this.restoringReading = true
    this.readingTimer = setTimeout(() => {
      this.readingTimer = -1
      if (this.state.sessionKey !== session || this.state.view !== 'chat' || this.traceMode) { this.restoringReading = false; return }
      const position = this.state.readingPosition
      try {
        if (initial && !position.atBottom) {
          const index: number = this.state.rows.findIndex((row: TimelineRow) => row.id === position.key)
          if (index >= 0) this.scroller.scrollToIndex(index + (this.state.hasMore ? 1 : 0), false, ScrollAlign.START)
          else this.scroller.scrollTo({ xOffset: 0, yOffset: position.key.length > 0 ? 0 : position.offset, animation: false })
          this.pinnedToBottom = false
        } else {
          this.scroller.scrollEdge(Edge.Bottom)
          this.pinnedToBottom = true
        }
        this.readingSession = session
      } catch {}
      this.restoringReading = false
    }, 100)
  }

  private invoke(action: string, id: string = ''): void {
    if (['back', 'session', 'disconnect', 'workspace', 'logout'].includes(action)) this.saveReadingPosition()
    runtime.perform(action, JSON.stringify({ id: id })).catch(() => {})
  }
  private send(action: string, payload: ActionInput): void {
    runtime.perform(action, JSON.stringify(payload)).catch(() => {})
  }
  private backendLabel(tab: BackendTab): string {
    return tab.count > 0 ? `${tab.name} ${tab.count}` : tab.name
  }
  private hostName(): string { return this.state.hostName.length > 0 ? this.state.hostName : '主机对话' }
  /** Android greets each backend differently inside an empty conversation. */
  private welcomeTitle(): string {
    const backend: string = this.state.sessionBackend
    if (backend === 'codex') { return '继续 CodeX 对话' }
    if (backend === 'cursor') { return '继续 Cursor 对话' }
    if (backend === 'antigravity') { return '继续 Antigravity 对话' }
    if (backend === 'opencode') { return '继续 OpenCode 对话' }
    if (backend === 'claude') { return '继续 Claude 对话' }
    if (backend === 'pi') { return '继续 Pi 对话' }
    return '继续这段对话'
  }
  private welcomeBody(): string {
    const backend: string = this.state.sessionBackend
    if (backend === 'codex') { return '告诉 CodeX 你想检查、解释或修改什么，也可以添加图片。命令或文件修改需要确认时，会直接显示在对话中。' }
    if (backend === 'cursor') { return '告诉 Cursor 你想检查、解释或修改什么。权限请求会直接显示在对话中；当前远程仅支持文本 Prompt。' }
    if (backend === 'antigravity') { return '告诉 AGY 你想检查、解释或修改什么，也可以添加图片。' }
    if (backend === 'opencode') { return '告诉 OpenCode 你想检查、解释或修改什么。' }
    if (backend === 'claude') { return '告诉 Claude 你想检查、解释或修改什么。' }
    if (backend === 'pi') { return '告诉 Pi 你想检查、解释或修改什么。' }
    return '告诉 DeepSeek Harness 你想检查、解释或修改什么，也可以添加图片。如果需要你确认操作，会直接显示在对话中。'
  }
  private policyHint(): string {
    const backend: string = this.state.sessionBackend
    if (backend === 'codex') { return '对话全程加密，远程操作受 CodeX 权限控制。' }
    if (backend === 'cursor') { return '对话全程加密，远程操作受 Cursor ACP 权限控制；当前仅支持文本消息。' }
    if (backend === 'pi') { return '对话全程加密，远程操作受 Pi ACP 权限控制；当前仅支持文本消息。' }
    if (backend === 'opencode') { return '消息全程加密，远程操作受 OpenCode ACP 权限控制。' }
    if (backend === 'claude') { return '消息全程加密，远程操作受 Claude ACP 权限控制。' }
    if (backend === 'antigravity') { return '消息全程加密。图片存入电脑端私有临时缓存，由 AGY 图片工具读取。' }
    return '对话全程加密，远程操作受 DeepSeek Harness 权限控制。'
  }
  private categoryLabel(category: string): string {
    if (category === 'all') { return '全部' }
    if (category === 'system') { return '系统' }
    if (category === 'user') { return '用户' }
    if (category === 'context') { return '上下文' }
    if (category === 'assistant') { return '助手' }
    return '工具'
  }
  /** Mirrors the Android trajectory filter: category first, then a whole-row search. */
  private traceRows(): TimelineRow[] {
    const needle: string = this.traceQuery.trim().toLowerCase()
    return this.state.rows.filter((row: TimelineRow) => (this.traceCategory === 'all' || row.category === this.traceCategory)
      && (needle.length === 0 || `${row.preview}\n${row.text}\n${row.detail}\n${row.turn}`.toLowerCase().includes(needle)))
  }

  private forkRow(id: string): void { this.send('fork', { id: id }) }
  private rateRow(id: string, rating: string): void { this.send('feedback', { id: id, rating: rating }) }
  private openMore(): void {
    this.panelPage = ''
    this.showMore = true
    this.send('morePanel', {})
  }
  private openPrompts(): void {
    this.promptPage = ''
    this.showPrompts = true
  }
  private closeDrawer(): void { this.drawerOpen = false; this.drawerSearch = false; this.drawerOptions = false }
  /** Opening the drawer restores Android's defaults, so a stale archive filter can never empty it. */
  private openDrawer(): void { this.drawerOpen = true; this.send('openDrawer', {}) }
  /** The value column of each 更多操作 row, matching Android's labels. */
  private modeValue(): string {
    const current: PresetRow | undefined = this.state.modes.find((row: PresetRow) => row.current)
    return current === undefined ? '默认' : current.name
  }
  private permissionValue(): string {
    const current: PresetRow | undefined = this.state.permissions.find((row: PresetRow) => row.current)
    return current === undefined ? '未设置' : current.name
  }
  private workspaceValue(): string {
    return this.state.workspaceTitle || runtime.translate('未分组')
  }
  private terminalValue(): string {
    if (this.state.activeTerminalId.length > 0) {
      for (let i = 0; i < this.state.terminals.length; i++) {
        if (this.state.terminals[i].id === this.state.activeTerminalId) {
          return this.state.terminals[i].title
        }
      }
    }
    return this.state.terminals.length > 0 ? `${this.state.terminals.length} 个` : '新建终端'
  }
  private startPrompt(prompt: PromptRow): void {
    this.showPrompts = false; this.promptPage = ''
    runtime.perform('prompt', JSON.stringify({ text: prompt.text })).catch(() => {})
  }
  private editPrompt(prompt: PromptRow): void {
    this.promptId = prompt.id; this.promptTitle = prompt.title; this.promptText = prompt.text
    this.showPrompts = false; this.showPromptForm = true
  }
  onBackPress(): boolean {
    if (this.showHostSwitcher) { this.showHostSwitcher = false; return true }
    if (this.alignmentPanel || this.showSettings || this.showTerminal || this.showMore || this.showPlugins || this.showTasks || this.showRecords || this.showBots || this.showNetwork || this.showPrompts || this.showPromptForm || this.showChildren || this.showInfo || this.showPluginForm || this.manageTarget) { this.closePanels(); return true }
    if (this.drawerOpen) { this.closeDrawer(); return true }
    if (this.state.view === 'chat' || this.state.view === 'sessions' || this.state.view === 'trust' || this.state.view === 'botHome') { this.invoke('back'); return true }
    return false
  }
  private closePanels(): void {
    this.alignmentPanel = ''; this.showHostSwitcher = false
    this.showMore = false; this.showPromptForm = false; this.manageTarget = undefined; this.confirmDelete = ''
    this.showPrompts = false; this.panelPage = ''; this.promptPage = ''
    this.drawerOpen = false; this.drawerSearch = false; this.drawerOptions = false
    this.showChildren = false; this.showInfo = false
    this.showPlugins = false; this.showPluginForm = false
    this.showTasks = false; this.showRecords = false; this.confirmTask = ''
    this.showSettings = false
    this.showBots = false
    this.showNetwork = false
    this.showTerminal = false
    this.terminalInput = ''
  }
  private openNetwork(): void {
    this.showNetwork = true
    this.send('networkDetails', {})
  }
  private networkStatusSummary(): string {
    if (this.state.networkSections.length > 0 && this.state.networkSections[0].rows.length > 0) {
      return this.state.networkSections[0].rows[0].value
    }
    return '查看详情'
  }
  private openBots(): void {
    this.showBots = true
    this.send('bots', {})
  }
  private openPlugins(): void {
    this.showPlugins = true
    this.send('plugins', {})
  }
  private openTasks(): void {
    this.taskFilter = 'all'; this.confirmTask = ''
    this.showTasks = true
    this.send('tasks', {})
  }
  /** Android's status filter, cycled 全部 → 已开启 → 已结束. */
  private nextTaskFilter(): string {
    if (this.taskFilter === 'all') { return 'active' }
    return this.taskFilter === 'active' ? 'inactive' : 'all'
  }
  private taskFilterLabel(): string {
    if (this.taskFilter === 'active') { return '已开启' }
    return this.taskFilter === 'inactive' ? '已结束' : '全部'
  }
  private shownTasks(): TaskRow[] {
    if (this.taskFilter === 'all') { return this.state.tasks }
    return this.state.tasks.filter((row: TaskRow) => (this.taskFilter === 'active') === row.active)
  }
  /** The meta line under a bundle, assembled like Android's detail card. */
  private pluginMeta(row: PluginRow): string {
    const parts: string[] = []
    if (!row.available) { parts.push('未安装：请在电脑端安装后使用') }
    else if (row.readOnly) { parts.push('不可远程修改') }
    if (row.version.length > 0) { parts.push(`版本 ${row.version}`) }
    if (row.level === 'bundle') { parts.push(row.id) }
    if (row.upgrade.length > 0) { parts.push(`升级到 ${row.upgrade} 后可在手机上修改设置`) }
    return parts.join(' · ')
  }
  /** Settings travel back as one JSON object of text values, coerced by the runtime. */
  private formPayload(): string {
    const parts: string[] = this.state.form.map((row: FormRow, index: number): string => {
      const value: string = row.kind === 'boolean'
        ? (this.formFlags[index] === true ? 'true' : 'false')
        : (this.formDraft[index] ?? row.value)
      return `${JSON.stringify(row.key)}:${JSON.stringify(value)}`
    })
    return `{${parts.join(',')}}`
  }

  /** Android's 更多操作 is a stack of screens: cards, then rows that drill in. */
  @Builder
  sheetTitle(title: string, back: boolean) {
    Row({ space: 8 }) {
      if (back) {
        Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary')).onClick(() => { this.panelPage = '' })
      }
      Text(runtime.translate(title)).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
      Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
        .onClick(() => { this.closePanels() })
    }.width('100%')
  }
  @Builder
  optionRow(icon: string, label: string, value: string, page: string) {
    Row({ space: 12 }) {
      Text(icon).fontSize(17).width(24).textAlign(TextAlign.Center).fontColor('#4B78E6')
      Text(label).fontSize(15).layoutWeight(1)
      Text(value).fontSize(13).fontColor($r('sys.color.font_secondary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 150 })
      Text('›').fontSize(17).fontColor($r('sys.color.font_secondary'))
    }.width('100%').height(52).padding({ left: 2, right: 2 })
      .onClick(() => { this.openPanelPage(page) })
  }
  /** Drill-down pages that read the Host load their roster on entry, like Android's pickers. */
  private openPanelPage(page: string): void {
    if (page === 'terminal') {
      this.showMore = false
      this.showTerminal = true
      this.send('openTerminal', {})
      return
    }
    if (page === 'bots') {
      this.showMore = false
      this.openBots()
      return
    }
    if (page === 'network') {
      this.showMore = false
      this.openNetwork()
      return
    }
    this.panelPage = page
    if (page === 'skills') { this.send('skills', {}) }
    else if (page === 'files') { this.send('files', { id: '' }) }
  }
  /** One preset per row, with its description, as Android's pickers show them. */
  @Builder
  presetPage(items: PresetRow[], empty: string, action: string) {
    if (items.length === 0) {
      Text(empty).fontSize(13).fontColor($r('sys.color.font_secondary')).padding(20).width('100%')
    } else {
      List({ space: 2 }) {
        ForEach(items, (item: PresetRow) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(item.name).fontSize(15).width('100%')
                  .fontWeight(item.current ? FontWeight.Bold : FontWeight.Normal)
                Text(item.description).fontSize(12).fontColor($r('sys.color.font_secondary'))
                  .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (item.current) { Text('✓').fontSize(17).fontColor('#4B78E6') }
            }.width('100%').padding({ top: 10, bottom: 10 })
          }.enabled(!item.broken && !item.current && !this.state.busy)
            .onClick(() => { this.showMore = false; this.panelPage = ''; this.send(action, { id: item.id }) })
        }, (item: PresetRow) => `${item.id}|${item.current}|${item.broken}|${item.name}|${item.description}`)
      }.width('100%').constraintSize({ maxHeight: 330 })
    }
  }

  @Builder
  morePanel() {
    Column({ space: 10 }) {
      if (this.panelPage === '') {
        this.sheetTitle('更多操作', false)
        Row({ space: 12 }) {
          Button(runtime.translate('拍照')).layoutWeight(1).height(56).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(!this.state.busy).onClick(() => { this.showMore = false; this.panelPage = ''; this.takePhoto() })
          Button(runtime.translate('相册')).layoutWeight(1).height(56).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(!this.state.busy).onClick(() => { this.showMore = false; this.panelPage = ''; this.pickImage() })
          Button(runtime.translate('文件')).layoutWeight(1).height(56).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(!this.state.busy).onClick(() => { this.showMore = false; this.panelPage = ''; this.pickDocument() })
        }.width('100%')
        if (this.state.panelWarning.length > 0) {
          Text(this.state.panelWarning).fontSize(12).fontColor('#9D6B20').width('100%')
        }
        Divider().color($r('sys.color.comp_background_tertiary'))
        this.optionRow('🗂', '工作区', this.workspaceValue(), 'workspace')
        this.optionRow('◈', '模式', this.modeValue(), 'mode')
        this.optionRow('⛨', '操作权限', this.permissionValue(), 'permission')
        this.optionRow('⌘', 'Slash 命令', `${this.state.skills.length} 个`, 'skills')
        this.optionRow('📄', '工作区文件', this.state.filePath, 'files')
        this.optionRow('💻', '终端', this.terminalValue(), 'terminal')
        this.optionRow('🤖', 'Bot 团队', this.state.bots.length > 0 ? `${this.state.bots.length} 个成员` : '查看', 'bots')
        this.optionRow('🌐', '网络与链路', this.networkStatusSummary(), 'network')
        Row({ space: 12 }) {
          Text('⏱').fontSize(17).width(24).textAlign(TextAlign.Center).fontColor('#4B78E6')
          Text(runtime.translate('紧凑历史')).fontSize(15).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.state.compactHistory })
            .selectedColor('#4B78E6').enabled(!this.state.busy)
            .onChange((on: boolean) => { if (on !== this.state.compactHistory) { this.send('compactHistory', {}) } })
        }.width('100%').height(52).padding({ left: 2, right: 2 })
      } else if (this.panelPage === 'mode') {
        this.sheetTitle('选择模式', true)
        this.presetPage(this.state.modes, '这台主机没有可用的模式预设。', 'selectMode')
      } else if (this.panelPage === 'permission') {
        this.sheetTitle('操作权限', true)
        this.presetPage(this.state.permissions, '当前主机未发布操作权限预设。', 'selectPermission')
      } else if (this.panelPage === 'skills') {
        this.sheetTitle('Slash 命令', true)
        if (this.state.skills.length === 0) {
          Text(runtime.translate('这台主机没有可用的 Slash 命令。')).fontSize(13).fontColor($r('sys.color.font_secondary')).padding(20).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.skills, (item: SkillRow) => {
              ListItem() {
                Column({ space: 3 }) {
                  Text(`/${item.name}`).fontSize(15).width('100%').fontFamily('monospace')
                  Text(item.description).fontSize(12).fontColor($r('sys.color.font_secondary'))
                    .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 10 })
              }.enabled(!this.state.busy)
                .onClick(() => { this.showMore = false; this.panelPage = ''; this.send('command', { text: `/${item.name}` }) })
            }, (item: SkillRow) => `skill|${item.id}|${item.name}|${item.description}`)
          }.width('100%').constraintSize({ maxHeight: 330 })
        }
      } else if (this.panelPage === 'files') {
        this.sheetTitle('工作区文件', true)
        Text(runtime.translate(this.state.filePath.length > 0 ? this.state.filePath : '会话工作区根目录'))
          .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%').fontFamily('monospace')
        if (this.state.files.length === 0) {
          Text(runtime.translate('正在加载目录，或该目录为空。')).fontSize(13).fontColor($r('sys.color.font_secondary')).padding(20).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.files, (item: FileRow) => {
              ListItem() {
                Row({ space: 10 }) {
                  Text(item.kind === 'directory' ? '📁' : '📄').fontSize(16).width(24).textAlign(TextAlign.Center)
                  Text(item.name).fontSize(15).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.size).fontSize(12).fontColor($r('sys.color.font_secondary'))
                }.width('100%').padding({ top: 10, bottom: 10 })
              }.enabled(!this.state.busy)
                .onClick(() => {
                  if (item.kind === 'directory') {
                    const next: string = this.state.filePath.length > 0 ? `${this.state.filePath}/${item.name}` : item.name
                    this.send('files', { id: next })
                  } else {
                    const next: string = this.state.filePath.length > 0 ? `${this.state.filePath}/${item.name}` : item.name
                    this.send('readFile', { id: next })
                  }
                })
            }, (item: FileRow) => `file|${item.id}|${item.kind}|${item.name}|${item.size}`)
          }.width('100%').constraintSize({ maxHeight: 330 })
        }
        if (this.state.filePreview.path.length > 0) {
          Divider().color($r('sys.color.comp_background_tertiary'))
          Row({ space: 8 }) {
            Text(this.state.filePreview.name).fontSize(14).layoutWeight(1).fontFamily('monospace').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(runtime.translate('只读')).fontSize(10).fontColor('#4B78E6').backgroundColor('#1A4B78E6')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(4)
            Button('✕').accessibilityText(runtime.translate('关闭')).fontSize(15).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
              .onClick(() => { this.send('closeFile', {}) })
          }.width('100%')
          Row({ space: 8 }) {
            Button(runtime.translate(this.savingFile ? '正在下载' : '保存到手机')).enabled(!this.savingFile && this.state.connected)
              .accessibilityText(runtime.translate('保存到手机')).onClick(() => { this.saveCurrentFile() })
            if (this.state.downloadBusy) {
              Text(`${Math.round(this.state.downloadBytes / 1024)} KiB`).fontSize(12).layoutWeight(1)
              Button(runtime.translate('取消下载')).onClick(() => { this.send('cancelDownload', {}) })
            }
          }.width('100%')
          if (this.fileSaveMessage) Text(this.fileSaveMessage).fontSize(12).width('100%')
          if (this.state.filePreview.error.length > 0) {
            Column({ space: 8 }) {
              Text(this.state.filePreview.error).fontSize(12).fontColor($r('sys.color.warning')).width('100%')
              Button(runtime.translate('重试')).fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                .onClick(() => { this.send('readFile', { id: this.state.filePreview.path, offset: this.state.filePreview.offset } as ActionInput) })
            }.width('100%').padding(10).backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(10)
          } else if (this.state.filePreview.kind === 'text') {
            Scroll() {
              Text(this.state.filePreview.text).fontSize(12).fontFamily('monospace').width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }.constraintSize({ maxHeight: 240 }).width('100%')
            Row() {
              Text(this.state.filePreview.eof
                ? `第 ${this.state.filePreview.offset}–${this.state.filePreview.offset + Math.max(0, this.state.filePreview.lines - 1)} 行（已到末尾）`
                : `第 ${this.state.filePreview.offset}–${this.state.filePreview.offset + Math.max(0, this.state.filePreview.lines - 1)} 行`)
                .fontSize(11).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
              if (this.state.filePreview.offset > 1) {
                Button(runtime.translate('上一页')).fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                  .onClick(() => { this.send('readFile', { id: this.state.filePreview.path, offset: Math.max(1, this.state.filePreview.offset - 200) } as ActionInput) })
              }
              if (!this.state.filePreview.eof && this.state.filePreview.lines > 0) {
                Button(runtime.translate('下一页')).fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                  .onClick(() => { this.send('readFile', { id: this.state.filePreview.path, offset: this.state.filePreview.offset + this.state.filePreview.lines } as ActionInput) })
              }
            }.width('100%')
          } else if (this.state.filePreview.kind === 'image') {
            Scroll() {
              Image(`data:${this.state.filePreview.mimeType};base64,${this.state.filePreview.data}`)
                .objectFit(ImageFit.Contain).width('100%')
            }.constraintSize({ maxHeight: 260 }).width('100%')
            Text(runtime.translate('图片只读预览')).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
          } else if (this.state.filePreview.kind === 'pdf' || this.state.filePreview.kind === 'office') {
            LocalSurface({ kind: 'pdf', payload: JSON.stringify(this.state.filePreview.data) })
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text(this.state.filePreview.kind === 'office' ? '📑 Office 文档 (PDF 转码)' : '📕 PDF 文档')
                  .fontSize(13).fontWeight(FontWeight.Medium)
              }.width('100%')
              if (this.state.filePreview.missingFonts.length > 0) {
                Text(`缺少字体: ${this.state.filePreview.missingFonts.join(', ')}`)
                  .fontSize(11).fontColor($r('sys.color.warning')).width('100%')
              }
              Text(this.state.filePreview.kind === 'office'
                ? '由主机 officeToPdf 引擎渲染为标准化 PDF 产物，完整保留版式结构与图文排版。'
                : '标准化 PDF 产物，已在移动端完成格式校验。')
                .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            }.padding(12).backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(12).width('100%')
          } else {
            Text(runtime.translate('此文件类型暂不支持在移动端直接预览，请在电脑端查看。'))
              .fontSize(12).fontColor($r('sys.color.font_secondary')).padding(12).width('100%')
          }
        }
      } else {
        this.sheetTitle('选择工作区', true)
        Text(runtime.translate('把当前对话移到所选工作区')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
        if (this.state.workspaceOptions.length === 0) {
          Text(runtime.translate('还没有可用的工作区。请在电脑端添加项目目录。')).fontSize(13)
            .fontColor($r('sys.color.font_secondary')).padding(20).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.workspaceOptions, (item: CatalogRow) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(item.name).fontSize(15).width('100%')
                    Text(item.description).fontSize(12).fontColor($r('sys.color.font_secondary'))
                      .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text(`${item.count}`).fontSize(12).fontColor($r('sys.color.font_secondary'))
                }.width('100%').padding({ top: 10, bottom: 10 })
              }.enabled(!this.state.busy)
                .onClick(() => { this.showMore = false; this.panelPage = ''; this.send('moveSession', { id: item.id }) })
            // ArkUI reuses an item whenever its key is unchanged, so every rendered field belongs in the key.
            }, (item: CatalogRow) => `move|${item.id}|${item.name}|${item.description}|${item.count}|${item.favorite}`)
          }.width('100%').constraintSize({ maxHeight: 330 })
        }
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's title-bar 子任务 popover: child sessions only, tapping opens one. */
  @Builder
  childrenSheet() {
    Column({ space: 10 }) {
      this.sheetTitle(`子任务 ${this.state.children.length}`, false)
      if (this.state.children.length === 0) {
        Text(runtime.translate('这段对话没有子任务会话。')).fontSize(13).fontColor($r('sys.color.font_secondary')).padding(20).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.state.children, (item: CatalogRow) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(item.name).fontSize(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.description).fontSize(12).fontColor(item.description === '回复中' ? '#4B78E6' : $r('sys.color.font_secondary'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('›').fontSize(17).fontColor($r('sys.color.font_secondary'))
              }.width('100%').padding({ top: 10, bottom: 10 })
            }.enabled(!this.state.busy)
              .onClick(() => { this.showChildren = false; this.send('session', { id: item.id }) })
          }, (item: CatalogRow) => `child|${item.id}|${item.name}|${item.description}`)
        }.width('100%').constraintSize({ maxHeight: 330 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's 对话信息 sheet: workspace, host, backend and directories. */
  @Builder
  infoSheet() {
    Column({ space: 10 }) {
      this.sheetTitle('对话与连接信息', false)
      Scroll() {
        Column({ space: 10 }) {
          Text(runtime.translate('会话与工作区')).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_secondary')).width('100%')
          Column({ space: 2 }) {
            ForEach(this.state.info, (row: InfoRow) => {
              Column({ space: 2 }) {
                Text(row.label).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                Text(row.value).fontSize(14).width('100%').copyOption(CopyOptions.LocalDevice)
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
            }, (row: InfoRow) => `info|${row.label}|${row.value}`)
          }.width('100%').padding(10).borderRadius(12).backgroundColor($r('sys.color.comp_background_tertiary'))

          if (this.state.networkSections.length > 0) {
            ForEach(this.state.networkSections, (sec: NetworkSection) => {
              Text(sec.title).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_secondary')).width('100%')
              Column({ space: 2 }) {
                ForEach(sec.rows, (row: NetworkRow) => {
                  Column({ space: 2 }) {
                    Text(row.label).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                    Text(row.value).fontSize(14).width('100%')
                      .fontFamily(row.mono ? 'monospace' : 'sans-serif')
                      .copyOption(CopyOptions.LocalDevice)
                  }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
                }, (row: NetworkRow) => `net|${row.label}|${row.value}`)
              }.width('100%').padding(10).borderRadius(12).backgroundColor($r('sys.color.comp_background_tertiary'))
            }, (sec: NetworkSection) => `sec|${sec.title}`)
          }
        }.width('100%')
      }.constraintSize({ maxHeight: 460 }).width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  badge(text: string) {
    Text(text).fontSize(10).fontColor('#4B78E6').borderRadius(8)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor($r('sys.color.comp_background_tertiary'))
  }

  /** Android's plugin manager: three sections, a switch per bundle and per component. */
  @Builder
  pluginsSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('插件')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary')).enabled(!this.state.busy)
          .onClick(() => { this.send('plugins', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate('启用和配置电脑上的插件')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      if (!this.state.settingsWritable) {
        Text(runtime.translate('Host 当前配置不可写入')).fontSize(12).fontColor('#9D6B20').width('100%')
      }
      if (this.state.plugins.length === 0) {
        Text(runtime.translate(this.state.busy ? '正在加载插件…' : 'Host 上没有可管理的插件')).fontSize(13)
          .fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.state.plugins, (row: PluginRow) => {
            ListItem() {
              if (row.level === 'section') {
                Column({ space: 2 }) {
                  Text(row.name).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
                  if (row.description.length > 0) {
                    Text(row.description).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
                  }
                }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 2 })
              } else {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(row.name).fontSize(15).layoutWeight(1).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .fontWeight(row.level === 'bundle' ? FontWeight.Bold : FontWeight.Normal)
                      if (row.level === 'bundle' && row.official) { this.badge('官方') }
                      if (row.level === 'bundle' && row.category === 'remote') { this.badge('移动端适配') }
                      if (row.level === 'bundle' && row.category === 'experimental') { this.badge('实验性') }
                    }.width('100%').alignItems(VerticalAlign.Center)
                    if (row.description.length > 0) {
                      Text(row.description).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (row.feature.length > 0) {
                      Text(row.feature).fontSize(11).fontColor('#4B78E6').width('100%')
                    }
                    if (this.pluginMeta(row).length > 0) {
                      Text(this.pluginMeta(row)).fontSize(11).width('100%').maxLines(2)
                        .fontColor(row.available ? $r('sys.color.font_secondary') : '#9D6B20')
                    }
                    if (row.error.length > 0) {
                      Text(row.error).fontSize(11).fontColor('#C64B43').width('100%')
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (row.form.length > 0 && row.enabled) {
                    Button(runtime.translate('设置')).fontSize(12).height(32).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                      .enabled(!this.state.busy)
                      .onClick(() => { this.showPlugins = false; this.showPluginForm = true; this.send('pluginForm', { id: row.form }) })
                  }
                  Toggle({ type: ToggleType.Switch, isOn: row.enabled }).selectedColor('#4B78E6')
                    .enabled(row.id.length > 0 && !row.readOnly && !this.state.busy)
                    .onChange((on: boolean) => {
                      if (on !== row.enabled) { this.send('pluginToggle', { id: row.id, mode: on ? 'on' : 'off' }) }
                    })
                }.width('100%').alignItems(VerticalAlign.Center).padding({
                  left: row.level === 'component' ? 16 : 2, right: 2, top: 10, bottom: 10 })
              }
            }
          // Every rendered field belongs in the key, or ArkUI reuses a stale row.
          }, (row: PluginRow) => `plugin|${row.id}|${row.level}|${row.name}|${row.description}|${row.category}`
            + `|${row.enabled}|${row.readOnly}|${row.available}|${row.official}|${row.version}|${row.error}`
            + `|${row.feature}|${row.upgrade}|${row.form}`)
        }.width('100%').constraintSize({ maxHeight: 430 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** The schema-derived settings form of one plugin component. */
  @Builder
  pluginFormSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.showPluginForm = false; this.openPlugins() })
        Text(this.state.formTitle).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate(this.state.settingsWritable ? '保存后立即生效，无需重启' : 'Host 当前配置不可写入'))
        .fontSize(12).fontColor(this.state.settingsWritable ? $r('sys.color.font_secondary') : '#9D6B20').width('100%')
      if (this.state.form.length === 0) {
        Text(runtime.translate('该组件没有可配置项')).fontSize(13).fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
      } else {
        Scroll() {
          Column({ space: 14 }) {
            ForEach(this.state.form, (row: FormRow, index: number) => {
              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(row.description).fontSize(14).width('100%')
                    Text(row.key).fontSize(11).fontFamily('monospace').width('100%')
                      .fontColor($r('sys.color.font_secondary'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (row.kind === 'boolean') {
                    Toggle({ type: ToggleType.Switch, isOn: this.formFlags[index] === true }).selectedColor('#4B78E6')
                      .enabled(this.state.settingsWritable && !this.state.busy)
                      .onChange((on: boolean) => {
                        this.formFlags = this.formFlags.map((old: boolean, at: number): boolean => at === index ? on : old)
                      })
                  }
                }.width('100%').alignItems(VerticalAlign.Center)
                if (row.kind === 'string-list') {
                  TextArea({ text: this.formDraft[index] ?? '', placeholder: runtime.translate('每行一项') })
                    .constraintSize({ minHeight: 70, maxHeight: 150 })
                    .enabled(this.state.settingsWritable && !this.state.busy)
                    .onChange((value: string) => {
                      this.formDraft = this.formDraft.map((old: string, at: number): string => at === index ? value : old)
                    })
                } else if (row.kind === 'string' || row.kind === 'number') {
                  TextInput({ text: this.formDraft[index] ?? '' })
                    .type(row.kind === 'number' ? InputType.Number : InputType.Normal)
                    .enabled(this.state.settingsWritable && !this.state.busy)
                    .onChange((value: string) => {
                      this.formDraft = this.formDraft.map((old: string, at: number): string => at === index ? value : old)
                    })
                } else if (row.kind === 'unsupported') {
                  Text(runtime.translate('此项请在电脑端修改')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                }
                if (row.bounds.length > 0) {
                  Text(row.bounds).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (row: FormRow) => `form|${row.key}|${row.kind}|${row.value}|${row.description}|${row.bounds}`)
          }.width('100%')
        }.constraintSize({ maxHeight: 380 }).width('100%')
        Row({ space: 10 }) {
          Button(runtime.translate('保存')).layoutWeight(1).backgroundColor('#4B78E6')
            .enabled(this.state.settingsWritable && !this.state.busy)
            .onClick(() => {
              runtime.perform('pluginSave', JSON.stringify({ text: this.formPayload() } as ActionInput)).catch(() => {})
            })
          if (this.state.formResettable) {
            Button(runtime.translate('恢复默认')).layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
              .enabled(this.state.settingsWritable && !this.state.busy)
              .onClick(() => { runtime.perform('pluginReset', JSON.stringify({} as ActionInput)).catch(() => {}) })
          }
        }.width('100%')
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's 自动化任务 list: status filter, rule summary, records and delete. */
  @Builder
  tasksSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('自动化任务')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.taskFilterLabel()).fontSize(12).height(32).backgroundColor(Color.Transparent)
          .fontColor('#4B78E6').onClick(() => { this.taskFilter = this.nextTaskFilter() })
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary')).enabled(!this.state.busy)
          .onClick(() => { this.send('tasks', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate('启用/停用与安卓版一致，仅改变本次客户端列表状态。')).fontSize(11).fontColor($r('sys.color.font_secondary'))
      Button(runtime.translate('新建 / 编辑任务')).onClick(() => { this.showTasks = false; this.alignmentPanel = 'tasks' })
      if (this.shownTasks().length === 0) {
        Text(this.state.busy ? '正在加载任务…'
          : (this.state.tasks.length === 0 ? '还没有自动化任务，在会话中创建的任务会显示在这里' : '没有匹配的自动化任务'))
          .fontSize(13).fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
      } else {
        List({ space: 4 }) {
          ForEach(this.shownTasks(), (row: TaskRow) => {
            ListItem() {
              Column({ space: 5 }) {
                Row({ space: 8 }) {
                  Text(row.title).fontSize(15).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.status).fontSize(11)
                    .fontColor(row.active ? '#39966C' : $r('sys.color.font_secondary'))
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(row.schedule).fontSize(12).fontColor('#4B78E6').width('100%')
                if (row.next.length > 0) {
                  Text(runtime.translate(`下次计划时间：${row.next}`)).fontSize(11).width('100%')
                    .fontColor($r('sys.color.font_secondary'))
                }
                if (row.last.length > 0) {
                  Text(runtime.translate(`上次触发：${row.last}`)).fontSize(11).width('100%')
                    .fontColor($r('sys.color.font_secondary'))
                }
                Text(row.prompt).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.confirmTask === row.id) {
                  Text(runtime.translate('任务将停止触发，并连同其已保存的运行记录一并删除。原会话及其消息仍然保留。'))
                    .fontSize(11).fontColor('#C64B43').width('100%')
                }
                Row({ space: 8 }) {
                  Blank()
                  Button(runtime.translate(row.active ? '停用' : '启用')).fontSize(12).onClick(() => { this.send('taskToggle', { id: row.id, name: row.session }) })
                  Button(runtime.translate('运行记录')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                    .enabled(!this.state.busy)
                    .onClick(() => {
                      this.showTasks = false; this.showRecords = true
                      this.send('taskHistory', { id: row.id, name: row.session })
                    })
                  if (this.confirmTask === row.id) {
                    Button(runtime.translate('确认删除')).fontSize(12).height(30).backgroundColor('#8C3B36').fontColor(Color.White)
                      .enabled(!this.state.busy)
                      .onClick(() => {
                        this.confirmTask = ''
                        this.send('taskDelete', { id: row.id, name: row.session })
                      })
                    Button(runtime.translate('取消')).fontSize(12).height(30).backgroundColor(Color.Transparent)
                      .fontColor($r('sys.color.font_secondary')).onClick(() => { this.confirmTask = '' })
                  } else {
                    Button(runtime.translate('删除')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#C64B43')
                      .enabled(!this.state.busy).onClick(() => { this.confirmTask = row.id })
                  }
                }.width('100%')
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 10 })
            }
          }, (row: TaskRow) => `task|${row.id}|${row.session}|${row.title}|${row.status}|${row.active}`
            + `|${row.schedule}|${row.next}|${row.last}|${row.prompt}|${this.confirmTask === row.id}`)
        }.width('100%').constraintSize({ maxHeight: 430 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** One task's delivery records, newest first as the Host returns them. */
  @Builder
  recordsSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary')).onClick(() => { this.showRecords = false; this.openTasks() })
        Text(this.state.recordsTitle).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate('任务运行记录')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      if (this.state.records.length === 0) {
        Text(runtime.translate(this.state.busy ? '正在加载任务…' : '暂无任务运行记录')).fontSize(13)
          .fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.state.records, (row: RecordRow) => {
            ListItem() {
              Column({ space: 3 }) {
                Row({ space: 8 }) {
                  Text(row.delivered).fontSize(14).layoutWeight(1)
                  Text(runtime.translate(`计划 ${row.scheduled}`)).fontSize(11).fontColor($r('sys.color.font_secondary'))
                }.width('100%').alignItems(VerticalAlign.Center)
                if (row.prompt.length > 0) {
                  Text(row.prompt).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                    .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 8 })
            }
          }, (row: RecordRow) => `record|${row.id}|${row.delivered}|${row.scheduled}|${row.prompt}`)
        }.width('100%').constraintSize({ maxHeight: 400 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's 设置 sheet: language, appearance, typography density, compact history. */
  @Builder
  settingsSheet() {
    Column({ space: 14 }) {
      this.sheetTitle('设置', false)
      Scroll() {
        Column({ space: 14 }) {
          // 语言
          Column({ space: 6 }) {
            Text(runtime.translate('语言')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            List({ space: 2 }) {
              ForEach([
                { id: 'system', name: runtime.translate('跟随系统') },
                { id: 'zh-CN', name: runtime.translate('简体中文') },
                { id: 'en-US', name: 'English' },
                { id: 'zh-TW', name: runtime.translate('繁體中文') },
                { id: 'ja-JP', name: runtime.translate('日本語') },
                { id: 'es-ES', name: 'Español' },
                { id: 'de-DE', name: 'Deutsch' },
                { id: 'fr-FR', name: 'Français' },
              ], (item: PrefOption) => {
                ListItem() {
                  Row() {
                    Text(item.name).fontSize(15).layoutWeight(1)
                      .fontWeight(this.state.languagePreference === item.id ? FontWeight.Bold : FontWeight.Normal)
                    if (this.state.languagePreference === item.id) {
                      Text('✓').fontSize(16).fontColor('#4B78E6')
                    }
                  }.width('100%').padding({ top: 10, bottom: 10, left: 4, right: 4 })
                }.onClick(() => { this.send('setLanguage', { id: item.id, name: item.id }) })
              }, (item: PrefOption) => `lang|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 外观
          Column({ space: 8 }) {
            Text(runtime.translate('外观')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'system', name: runtime.translate('跟随系统') },
                { id: 'light', name: runtime.translate('浅色') },
                { id: 'dark', name: runtime.translate('深色') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(36).fontSize(13)
                  .backgroundColor(this.state.themePreference === item.id ? '#4B78E6' : $r('sys.color.comp_background_tertiary'))
                  .fontColor(this.state.themePreference === item.id ? Color.White : $r('sys.color.font_primary'))
                  .onClick(() => { this.send('setTheme', { id: item.id, name: item.id }) })
              }, (item: PrefOption) => `theme|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 排版密度
          Column({ space: 8 }) {
            Text(runtime.translate('排版密度')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('调整正文行距、段间距与气泡紧凑度')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'standard', name: runtime.translate('标准') },
                { id: 'compact', name: runtime.translate('紧凑') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(36).fontSize(13)
                  .backgroundColor(this.state.typographyDensity === item.id ? '#4B78E6' : $r('sys.color.comp_background_tertiary'))
                  .fontColor(this.state.typographyDensity === item.id ? Color.White : $r('sys.color.font_primary'))
                  .onClick(() => { this.send('setDensity', { id: item.id, name: item.id }) })
              }, (item: PrefOption) => `density|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 紧凑历史
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('会话精简模式')).fontSize(15).width('100%')
              Text(runtime.translate('缩减历史工具详情，保留正文和状态')).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.state.compactHistory })
              .selectedColor('#4B78E6').enabled(!this.state.busy)
              .onChange((on: boolean) => { if (on !== this.state.compactHistory) { this.send('compactHistory', {}) } })
          }.width('100%').height(52).padding({ left: 2, right: 2 })

          Divider().color($r('sys.color.comp_background_tertiary'))

          Row({ space: 12 }) {
            Text(runtime.translate('启动自动连接主机')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.state.autoConnectHost }).onChange((on: boolean) => { this.send('setAutoConnectHost', { enabled: on }) })
          }.width('100%')
          // 通知
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('启动恢复上次对话')).fontSize(15).width('100%')
              Text(runtime.translate('自动连接后返回上次打开的对话，默认关闭')).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.state.resumeSessionEnabled })
              .selectedColor('#4B78E6').enabled(!this.state.busy)
              .onChange((on: boolean) => { if (on !== this.state.resumeSessionEnabled) this.send('setResumeSession', { enabled: on }) })
          }.width('100%').padding({ top: 4, bottom: 4 })
          Text(runtime.translate('阅读位置会自动保存；重新打开时回到已加载历史中的相应消息')).fontSize(11)
            .fontColor($r('sys.color.font_secondary')).width('100%')

          Divider().color($r('sys.color.comp_background_tertiary'))

          Column({ space: 8 }) {
            Text(runtime.translate('通知')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(runtime.translate('任务和待确认提醒')).fontSize(15).width('100%')
                Text(runtime.translate('在应用处于后台时，接收任务完成与审批提示')).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.state.notificationsEnabled })
                .selectedColor('#4B78E6')
                .onChange((on: boolean) => {
                  if (on !== this.state.notificationsEnabled) {
                    this.send('setNotifications', { name: on ? 'true' : 'false' })
                  }
                })
            }.width('100%').padding({ top: 4, bottom: 4 })
            Button(runtime.translate('开启系统通知权限')).fontSize(13).height(36).backgroundColor($r('sys.color.comp_background_tertiary'))
              .fontColor('#4B78E6').width('100%')
              .onClick(() => { this.send('requestNotificationPermission', {}) })
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 传输与直连策略
          Column({ space: 8 }) {
            Text(runtime.translate('传输与直连策略')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('优先尝试局域网与 P2P 直连，遇到网络限制自动回退中继')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'auto', name: runtime.translate('自动优选') },
                { id: 'turn', name: runtime.translate('仅穿透中继') },
                { id: 'relay', name: runtime.translate('仅控制转发') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(36).fontSize(13)
                  .backgroundColor(this.state.transportPreference === item.id ? '#4B78E6' : $r('sys.color.comp_background_tertiary'))
                  .fontColor(this.state.transportPreference === item.id ? Color.White : $r('sys.color.font_primary'))
                  .onClick(() => { this.send('setTransportPreference', { mode: item.id }) })
              }, (item: PrefOption) => `trans|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 新对话默认权限
          Column({ space: 8 }) {
            Text(runtime.translate('新对话默认权限')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('仅影响新建的 DSH / CodeX 对话，已有对话不变')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'default', name: runtime.translate('默认') },
                { id: 'workspace-write', name: runtime.translate('工作区读写') },
                { id: 'danger-full-access', name: runtime.translate('完全权限') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(36).fontSize(12)
                  .backgroundColor(this.state.defaultPermission === item.id ? '#4B78E6' : $r('sys.color.comp_background_tertiary'))
                  .fontColor(this.state.defaultPermission === item.id ? Color.White : $r('sys.color.font_primary'))
                  .onClick(() => {
                    if (item.id !== 'danger-full-access') { this.send('setDefaultPermission', { name: item.id }); return }
                    promptAction.showDialog({ title: runtime.translate('完全权限'), message: runtime.translate('新对话可以修改文件与执行命令，不再逐次询问。'), buttons: [{ text: runtime.translate('取消'), color: '#888888' }, { text: runtime.translate('确认'), color: '#4B78E6' }] }).then((result: promptAction.ShowDialogSuccessResponse) => { if (result.index === 1) this.send('setDefaultPermission', { name: item.id }) })
                  })
              }, (item: PrefOption) => `perm|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 系统状态栏
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('系统状态栏')).fontSize(15).width('100%')
              Text(runtime.translate('在全屏与页面切换时保持系统状态栏可见')).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.state.statusBarVisible })
              .selectedColor('#4B78E6')
              .onChange((on: boolean) => { if (on !== this.state.statusBarVisible) this.send('setStatusBar', { enabled: on }) })
          }.width('100%').padding({ top: 4, bottom: 4 })

          Divider().color($r('sys.color.comp_background_tertiary'))

          // 本地数据与缓存
          Column({ space: 8 }) {
            Text(runtime.translate('本地数据与缓存')).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('清除本机保存的草稿、收藏、历史浏览位置与连接缓存')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            Button(runtime.translate('清除本地记录与缓存')).fontSize(13).height(36).backgroundColor($r('sys.color.comp_background_tertiary'))
              .fontColor('#C64B43').width('100%')
              .onClick(() => { promptAction.showDialog({ title: runtime.translate('清除本地记录与缓存'), message: runtime.translate('清除本机保存的草稿、收藏、历史浏览位置与连接缓存'), buttons: [{ text: runtime.translate('取消'), color: '#888888' }, { text: runtime.translate('确认'), color: '#C64B43' }] }).then((result: promptAction.ShowDialogSuccessResponse) => { if (result.index === 1) this.send('clearBrowseData', {}) }) })
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color($r('sys.color.comp_background_tertiary'))

          Text(runtime.translate('后台连接')).fontSize(15).fontWeight(FontWeight.Bold).width('100%')
          Text(runtime.translate(this.state.backgroundActive ? '后台持续任务已启用' : '后台持续任务未启用')).fontSize(12).width('100%')
          if (this.state.backgroundError) Text(runtime.translate(this.state.backgroundError)).fontSize(12).fontColor('#C64B43').width('100%')
          Text(runtime.translate('系统省电策略可能暂停连接，可在应用设置中检查通知与后台权限')).fontSize(12).width('100%')
          Row({ space: 8 }) {
            Button(runtime.translate('应用系统设置')).onClick(() => { this.send('appSettings', {}) })
            Button(runtime.translate('重试后台连接')).enabled(this.state.connected).onClick(() => { this.send('retryBackground', {}) })
          }.width('100%')
          Divider()
          Button(runtime.translate('检查更新')).enabled(!this.state.busy).onClick(() => { this.send('checkUpdate', {}) })
          if (this.state.updateVersion) Text(runtime.translate('最新上游版本') + ': ' + this.state.updateVersion).fontSize(12).width('100%')
          Button(runtime.translate('打开发布页')).onClick(() => { this.send('openUpdates', {}) })
          Text(runtime.translate('鸿蒙安装包需要匹配签名；请使用正式发布的 HAP 或 HoKit 覆盖安装')).fontSize(12).width('100%')
          // 版本信息
          Row() {
            Text(runtime.translate('当前版本')).fontSize(13).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            Text(this.state.appVersion).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }.width('100%').padding({ top: 4, bottom: 8 })
        }.width('100%')
      }.constraintSize({ maxHeight: 480 }).width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's Bot team roster panel: members, main bot badge, roles, models and open conversation. */
  @Builder
  botSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('Bot 团队')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary')).enabled(!this.state.busy)
          .onClick(() => { this.send('bots', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Button(runtime.translate('管理智能体与群组')).onClick(() => { this.showBots = false; this.alignmentPanel = 'bots' })
      if (this.state.bots.length === 0) {
        Text(this.state.busy ? '正在加载 Bot 团队…'
          : '这台主机暂无 Bot，或尚未启用 ds-bot 插件')
          .fontSize(13).fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
      } else {
        List({ space: 6 }) {
          ForEach(this.state.bots, (bot: BotEntryRow) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(bot.name.slice(0, 1).toUpperCase())
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  .width(36).height(36).textAlign(TextAlign.Center).borderRadius(18)
                  .backgroundColor(bot.color.length > 0 ? bot.color : '#4B78E6')
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(bot.name).fontSize(15).fontWeight(FontWeight.Medium)
                    if (bot.main) {
                      Text(runtime.translate('主 Bot')).fontSize(10).fontColor('#4B78E6')
                        .backgroundColor('#1A4B78E6').padding({ left: 4, right: 4, top: 1, bottom: 1 }).borderRadius(4)
                    }
                  }
                  Text(`${bot.role}${bot.model.length > 0 ? ' · ' + bot.model : ''}`)
                    .fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(runtime.translate('打开')).fontSize(12).height(30).backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor('#4B78E6')
                  .onClick(() => {
                    this.closePanels()
                    this.send('botSelect', { id: bot.id })
                  })
              }.width('100%').padding(10).borderRadius(12)
              .backgroundColor($r('sys.color.comp_background_primary'))
            }
          }, (bot: BotEntryRow) => `bot|${bot.id}|${bot.name}|${bot.main}`)
        }.width('100%').constraintSize({ maxHeight: 380 })
      }
    }
    .width('100%').padding(16)
    .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's 网络详情 panel: path, probe order, endpoints, RTT, bitrate, traffic. */
  @Builder
  networkSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('网络与链路详情')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_secondary')).enabled(!this.state.busy)
          .onClick(() => { this.send('networkDetails', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')
      if (this.state.networkSections.length === 0) {
        Text(runtime.translate(this.state.busy ? '正在获取网络状态…' : '网络状态暂不可用')).fontSize(13)
          .fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.state.networkSections, (sec: NetworkSection) => {
              Column({ space: 6 }) {
                Text(sec.title).fontSize(13).fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.font_secondary')).width('100%')
                Column({ space: 2 }) {
                  ForEach(sec.rows, (row: NetworkRow) => {
                    Column({ space: 3 }) {
                      Text(row.label).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
                      Text(row.value).fontSize(14).width('100%')
                        .fontFamily(row.mono ? 'monospace' : 'sans-serif')
                        .copyOption(CopyOptions.LocalDevice)
                    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
                  }, (row: NetworkRow) => `nr|${row.label}|${row.value}`)
                }.width('100%').padding(12).borderRadius(12)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (sec: NetworkSection) => `ns|${sec.title}`)
          }.width('100%')
        }.constraintSize({ maxHeight: 460 }).width('100%')
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android's terminal panel: tab strip, monospace screen, shortcut bar and command input. */
  @Builder
  terminalSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('终端')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        if (this.state.terminalBusy) {
          Text('…').fontSize(14).fontColor($r('sys.color.font_secondary'))
        }
        Button(runtime.translate('＋ 新建')).fontSize(12).height(32).backgroundColor(Color.Transparent)
          .fontColor('#4B78E6').enabled(!this.state.busy && !this.state.terminalBusy)
          .onClick(() => { this.send('createTerminal', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.closePanels() })
      }.width('100%')

      if (this.state.terminals.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.state.terminals, (item: TerminalRow) => {
              Button(item.title).fontSize(12).height(28)
                .backgroundColor(this.state.activeTerminalId === item.id ? '#4B78E6' : $r('sys.color.comp_background_tertiary'))
                .fontColor(this.state.activeTerminalId === item.id ? Color.White : $r('sys.color.font_primary'))
                .enabled(!this.state.terminalBusy)
                .onClick(() => { this.send('selectTerminal', { id: item.id }) })
            }, (item: TerminalRow) => `${item.id}|${item.title}|${item.state}`)
            if (this.state.activeTerminalId.length > 0) {
              Button(runtime.translate('结束终端')).fontSize(12).height(28).backgroundColor(Color.Transparent)
                .fontColor($r('sys.color.warning')).enabled(!this.state.terminalBusy)
                .onClick(() => { this.send('closeTerminal', {}) })
            }
          }.alignItems(VerticalAlign.Center)
        }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
      }

      if (this.state.terminalError.length > 0) {
        Row({ space: 8 }) {
          Text(this.state.terminalError).fontSize(12).fontColor($r('sys.color.warning')).layoutWeight(1)
          Button(runtime.translate('重试')).fontSize(11).height(26).backgroundColor(Color.Transparent).fontColor('#4B78E6')
            .onClick(() => { this.send('retryTerminal', {}) })
        }.width('100%').padding(6).backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(6)
      }

      Stack({ alignContent: Alignment.BottomStart }) {
        LocalSurface({ kind: 'terminal', payload: JSON.stringify({ type: 'write', scope: this.state.sessionKey + '/' + this.state.activeTerminalId, revision: this.state.terminalRenderRevision, chunk: this.state.terminalChunk, reset: this.state.terminalReset, data: this.state.terminalRaw, enabled: this.state.terminalWritable }),
          onAction: async (raw: string): Promise<boolean> => {
            const event: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
            if (event.type === 'data') return runtime.perform('writeTerminal', JSON.stringify({ text: event.data }))
            if (event.type === 'resize' || event.type === 'ready') return runtime.perform('resizeTerminal', JSON.stringify({ text: JSON.stringify({ cols: event.cols, rows: event.rows }) }))
            return false
          } })
        if (this.state.terminalStatus.length > 0 && this.state.terminalScreen.length > 0) {
          Row({ space: 6 }) {
            Text(this.state.terminalStatus).fontSize(11).fontColor('#8B949E')
          }.padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#E6101418').borderRadius(4).margin(6)
        }
      }.width('100%')

      Scroll() {
        Row({ space: 6 }) {
          Button('Ctrl+C').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x03' }) })
          Button('Tab').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\t' }) })
          Button('Esc').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b' }) })
          Button('↑').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[A' }) })
          Button('↓').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[B' }) })
          Button('←').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[D' }) })
          Button('→').fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[C' }) })
          Button(runtime.translate('退格')).fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x7f' }) })
          Button(runtime.translate('回车')).fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor('#4B78E6').enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\r' }) })
          Button(runtime.translate('清屏')).fontSize(11).height(28).backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor($r('sys.color.font_secondary'))
            .onClick(() => { this.send('clearTerminal', {}) })
        }.alignItems(VerticalAlign.Center)
      }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)

      Row({ space: 8 }) {
        TextInput({ text: this.terminalInput, placeholder: runtime.translate('输入命令或文本…') })
          .layoutWeight(1).height(36).fontSize(13).fontFamily('monospace')
          .enabled(this.state.terminalWritable)
          .onChange((value: string) => { this.terminalInput = value })
          .onSubmit(() => {
            if (this.terminalInput.length > 0) {
              this.send('writeTerminal', { text: `${this.terminalInput}\r` })
              this.terminalInput = ''
            }
          })
        Button(runtime.translate('发送')).fontSize(13).height(36).backgroundColor('#4B78E6').fontColor(Color.White)
          .enabled(this.state.terminalWritable && this.terminalInput.length > 0)
          .onClick(() => {
            if (this.terminalInput.length > 0) {
              this.send('writeTerminal', { text: `${this.terminalInput}\r` })
              this.terminalInput = ''
            }
          })
      }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** Android keeps 快捷提示词 out of 更多操作: its own list, then a manager, then an editor. */
  @Builder
  promptsPanel() {
    Column({ space: 10 }) {
      if (this.promptPage === '') {
        Row() {
          Text(runtime.translate('快捷提示词')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
            .onClick(() => { this.showPrompts = false; this.promptPage = '' })
        }.width('100%')
        if (this.state.prompts.length === 0) {
          Text(runtime.translate('没有提示词。点击「编辑提示词」增加常用提示词。')).fontSize(13)
            .fontColor($r('sys.color.font_secondary')).padding(16).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.prompts, (item: PromptRow) => {
              ListItem() {
                Column({ space: 3 }) {
                  Text(item.title).fontSize(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.text).fontSize(12).fontColor($r('sys.color.font_secondary'))
                    .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 10 })
              }.enabled(!this.state.busy).onClick(() => { this.startPrompt(item) })
            }, (item: PromptRow) => `send|${item.id}|${item.title}|${item.text}`)
          }.width('100%').constraintSize({ maxHeight: 300 })
        }
        Row({ space: 8 }) {
          Text(runtime.translate('编辑提示词')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(17).fontColor($r('sys.color.font_secondary'))
        }.width('100%').height(50).onClick(() => { this.promptPage = 'manager' })
      } else {
        Row({ space: 8 }) {
          Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.font_secondary')).onClick(() => { this.promptPage = '' })
          Text(runtime.translate('编辑提示词')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('＋').fontSize(17).width(36).height(36).backgroundColor(Color.Transparent).fontColor('#4B78E6')
            .onClick(() => {
              this.promptId = ''; this.promptTitle = ''; this.promptText = ''
              this.showPrompts = false; this.showPromptForm = true
            })
          Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
            .onClick(() => { this.showPrompts = false; this.promptPage = '' })
        }.width('100%')
        List({ space: 2 }) {
          ForEach(this.state.prompts, (item: PromptRow) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(item.title).fontSize(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(runtime.translate(item.builtIn ? '内置' : item.text)).fontSize(12).fontColor($r('sys.color.font_secondary'))
                    .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(runtime.translate('编辑')).fontSize(12).height(32).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                  .onClick(() => { this.editPrompt(item) })
                if (!item.builtIn) {
                  Button(runtime.translate('删除')).fontSize(12).height(32).backgroundColor(Color.Transparent).fontColor('#C64B43')
                    .onClick(() => { this.send('deletePrompt', { id: item.id }) })
                }
              }.width('100%').padding({ top: 8, bottom: 8 })
            }
          }, (item: PromptRow) => `edit|${item.id}|${item.title}|${item.text}|${item.builtIn}`)
        }.width('100%').constraintSize({ maxHeight: 330 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  promptForm() {
    Column({ space: 12 }) {
      Row() {
        Text(runtime.translate(this.promptId.length > 0 ? `编辑“${this.promptTitle}”` : '新建提示词')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.showPromptForm = false })
      }.width('100%')
      TextInput({ text: this.promptTitle, placeholder: runtime.translate('提示词名称') }).onChange((value: string) => { this.promptTitle = value })
      TextArea({ text: this.promptText, placeholder: runtime.translate('提示词内容') })
        .constraintSize({ minHeight: 110, maxHeight: 220 }).onChange((value: string) => { this.promptText = value })
      Row({ space: 10 }) {
        Button(runtime.translate('保存')).layoutWeight(1).backgroundColor('#4B78E6')
          .enabled(this.promptTitle.trim().length > 0 && this.promptText.trim().length > 0)
          .onClick(() => {
            runtime.perform('savePrompt', JSON.stringify({
              id: this.promptId, name: this.promptTitle, text: this.promptText,
            } as ActionInput)).catch(() => {})
            this.showPromptForm = false
          })
        Button(runtime.translate('取消')).layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => { this.showPromptForm = false })
      }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  manageSheet() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text(runtime.translate('管理工作区')).fontSize(19).fontWeight(FontWeight.Bold).width('100%')
          Text(this.manageTarget?.name ?? '').fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.manageTarget = undefined; this.confirmDelete = '' })
      }.width('100%')
      Text(this.manageTarget?.description ?? '').fontSize(12).fontColor($r('sys.color.font_secondary'))
        .width('100%').copyOption(CopyOptions.LocalDevice)
      if (this.manageTarget !== undefined && this.manageTarget.backend !== 'harness') {
        Text(runtime.translate('CodeX 与 ACP 工作区的名称、顺序和删除由电脑端管理。')).fontSize(13).fontColor('#9D6B20').width('100%')
      } else {
        Row({ space: 8 }) {
          TextInput({ text: this.workspaceName, placeholder: runtime.translate('输入工作区名称') }).layoutWeight(1)
            .onChange((value: string) => { this.workspaceName = value })
          Button(runtime.translate('保存')).enabled(this.workspaceName.trim().length > 0)
            .onClick(() => {
              const target = this.manageTarget
              if (target === undefined) return
              runtime.perform('renameWorkspace', JSON.stringify({ id: target.id, name: this.workspaceName } as ActionInput)).catch(() => {})
              this.manageTarget = undefined
            })
        }.width('100%')
        Row({ space: 10 }) {
          Button(runtime.translate('↑ 上移')).layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
            .onClick(() => { this.moveWorkspaceBy('up') })
          Button(runtime.translate('↓ 下移')).layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
            .onClick(() => { this.moveWorkspaceBy('down') })
        }.width('100%')
        if (this.confirmDelete.length === 0) {
          Button(runtime.translate('删除工作区')).width('100%').backgroundColor('#8C3B36').fontColor(Color.White)
            .onClick(() => { this.confirmDelete = 'again' })
        } else {
          Text(runtime.translate('删除将从这台主机移除该工作区及其所有对话，且无法撤销。')).fontSize(12).fontColor('#C64B43').width('100%')
          Row({ space: 10 }) {
            Button(runtime.translate('确认删除')).layoutWeight(1).backgroundColor('#8C3B36').fontColor(Color.White)
              .onClick(() => {
                const target = this.manageTarget
                if (target === undefined) return
                runtime.perform('deleteWorkspace', JSON.stringify({ id: target.id } as ActionInput)).catch(() => {})
                this.manageTarget = undefined; this.confirmDelete = ''
              })
            Button(runtime.translate('返回')).layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
              .onClick(() => { this.confirmDelete = '' })
          }.width('100%')
        }
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
  }

  private moveWorkspaceBy(direction: string): void {
    const target = this.manageTarget
    if (target === undefined) return
    runtime.perform('moveWorkspace', JSON.stringify({ id: target.id, mode: direction } as ActionInput)).catch(() => {})
  }

  @Builder
  scrim() {
    Column().width('100%').height('100%').backgroundColor('#A0000000').onClick(() => { this.closePanels() })
  }

  @Builder
  traceControls() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.traceQuery, placeholder: runtime.translate('搜索消息、工具或轮次') }).layoutWeight(1)
          .onChange((value: string) => { this.traceQuery = value })
        if (this.traceQuery.length > 0) {
          Button(runtime.translate('清空')).fontSize(12).height(34).backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.font_secondary')).onClick(() => { this.traceQuery = '' })
        }
      }
      Scroll() {
        Row({ space: 6 }) {
          ForEach(['all', 'system', 'user', 'context', 'assistant', 'tool'], (key: string) => {
            Button(this.categoryLabel(key)).fontSize(12).height(30)
              .backgroundColor(this.traceCategory === key ? '#20386B' : $r('sys.color.comp_background_tertiary'))
              .fontColor(this.traceCategory === key ? '#8FB0F7' : $r('sys.color.font_primary'))
              .onClick(() => { this.traceCategory = key })
          }, (key: string) => `${key}|${this.traceCategory === key ? 'on' : 'off'}`)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      Text(runtime.translate('仅显示已加载的真实消息；加载更早记录可扩展轨迹。'))
        .fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
    }.padding({ left: 16, right: 16, bottom: 8 }).width('100%')
  }

  private async saveCurrentFile(): Promise<void> {
    if (this.savingFile) return
    const scope: string = this.state.sessionKey
    const path: string = this.state.filePreview.path
    if (!path) return
    this.savingFile = true; this.fileSaveMessage = ''
    try {
      const destination: string = await saveWorkspaceFile(this.getUIContext().getHostContext() as common.UIAbilityContext, path, (): boolean => this.state.sessionKey === scope && this.state.connected && this.state.filePreview.path === path)
      this.fileSaveMessage = runtime.translate(destination ? '文件已保存' : '已取消保存')
    } catch (error) { this.fileSaveMessage = runtime.translate((error as Error).message) }
    finally { this.savingFile = false }
  }
  private async pickImage(): Promise<void> {
    const scope: string = this.state.sessionKey
    this.imageError = ''
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const selected = await photoPicker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: Math.max(1, this.state.imageMaxCount - this.promptImages.length) })
      if (selected.photoUris.length === 0) return
      for (const uri of selected.photoUris) await this.readImage(uri, scope)
    } catch (error) { this.imageError = runtime.translate((error as Error).message) }
  }

  /** The system camera picker needs a sandbox target; it asks for no camera permission. */
  private async takePhoto(): Promise<void> {
    const scope: string = this.state.sessionKey
    let target: string = ''
    this.imageError = ''
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      target = `${context.cacheDir}/dsh-shot-${Math.floor(Date.now() / 1000)}.jpg`
      const handle = await fs.open(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      await fs.close(handle.fd)
      const profile: cameraPicker.PickerProfile = { cameraPosition: cameraKit.CameraPosition.CAMERA_POSITION_BACK, saveUri: fileUri.getUriFromPath(target) }
      const result = await cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile)
      if (result.resultCode !== 0 || !result.resultUri) return
      await this.readImage(result.resultUri, scope)
    } catch (error) { this.imageError = runtime.translate((error as Error).message) }
    finally { if (target) { try { await fs.unlink(target) } catch {} } }
  }

  /** Images and bounded UTF-8 documents use the existing authenticated upload channel. */
  private async pickDocument(): Promise<void> {
    const scope: string = this.state.sessionKey
    this.imageError = ''
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const documentPicker = new picker.DocumentViewPicker(context)
      const selected = await documentPicker.select({
        maxSelectNumber: 8,
      })
      if (selected.length === 0) return
      for (const uri of selected) {
      if (scope !== this.state.sessionKey || !this.state.connected) throw new Error('会话已切换，附件已取消')
      const name: string = decodeURIComponent(uri.split('/').pop() ?? 'attachment')
      if (/\.(jpe?g|png|gif|webp)$/i.test(name)) { await this.readImage(uri, scope); continue }
      const file = await fs.open(uri, fs.OpenMode.READ_ONLY)
      try {
        const size: number = (await fs.stat(file.fd)).size
        if (size <= 0 || size > 512 * 1024) throw new Error('请选择 512 KiB 以内的代码或文本文件')
        const buffer: ArrayBuffer = new ArrayBuffer(size)
        if (await fs.read(file.fd, buffer) !== size) throw new Error('文件读取不完整。')
        const data: string = new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer))
        if (scope !== this.state.sessionKey || !this.state.connected) throw new Error('会话已切换，附件已取消')
        if (!await runtime.perform('uploadFile', JSON.stringify({ name: name, text: data }))) throw new Error(this.state.error || '文件无法添加')
      } finally { await fs.close(file.fd) }
      }
    } catch (error) { this.imageError = runtime.translate((error as Error).message) }
  }

  private async readImage(uri: string, scope: string): Promise<void> {
    if (uri.length === 0) return
    try {
      if (scope !== this.state.sessionKey || !this.state.connected) throw new Error('会话已切换，附件已取消')
      if (!this.state.imageAllowed) throw new Error('当前后端未发布图片支持')
      const file = await fs.open(uri, fs.OpenMode.READ_ONLY)
      try {
        const stat = await fs.stat(file.fd)
        if (stat.size > this.state.imageMaxBytes || this.promptImages.reduce((sum: number, row: PromptAttachment): number => sum + Math.floor(row.data.length * 3 / 4), 0) + stat.size > 32 * 1024 * 1024) throw new Error('图片超过主机或本机内存限制')
        const buffer = new ArrayBuffer(stat.size)
        const bytesRead = await fs.read(file.fd, buffer)
        if (bytesRead !== stat.size) throw new Error('图片读取不完整。')
        const bytes = new Uint8Array(buffer)
        if (bytes[0] === 0xFF && bytes[1] === 0xD8) this.mediaType = 'image/jpeg'
        else if (bytes[0] === 0x89 && bytes[1] === 0x50) this.mediaType = 'image/png'
        else if (bytes[0] === 0x47 && bytes[1] === 0x49) this.mediaType = 'image/gif'
        else if (bytes[0] === 0x52 && bytes[8] === 0x57) this.mediaType = 'image/webp'
        else throw new Error('支持 JPEG、PNG、GIF 和 WebP；HEIC 请先转换。')
        if (this.promptImages.length >= this.state.imageMaxCount) throw new Error('图片数量超过主机限制')
        if (scope !== this.state.sessionKey || !this.state.connected) throw new Error('会话已切换，附件已取消')
        const data: string = new util.Base64Helper().encodeToStringSync(bytes)
        const attachments: PromptAttachment[] = [...this.promptImages, { data: data, mediaType: this.mediaType }]
        runtime.validateImageAttachments(JSON.stringify(attachments))
        this.image = data; this.promptImages = attachments
      } finally { await fs.close(file.fd) }
    } catch (error) { this.imageError = runtime.translate((error as Error).message) }
  }

  @Builder
  header() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
      if (this.state.view !== 'login' && this.state.view !== 'devices') {
        Button('‹').accessibilityText(runtime.translate('返回')).fontSize(30).width(42).height(42).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.font_primary')).onClick(() => { this.invoke('back') })
      }
      Column({ space: 4 }) {
        Text(this.state.title).width('100%').fontSize(22).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(runtime.translate(this.state.connected || this.state.recovering ? this.state.status : 'HarmonyOS · 0.6.3 移植预览'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(11).fontColor(this.state.connected ? (this.state.recovering ? '#9D6B20' : '#39966C') : $r('sys.color.font_secondary'))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      if (this.state.connected) {
        Row({ space: 4 }) {
          if (this.state.view === 'chat') {
            if (this.state.children.length > 0) {
              Button(runtime.translate(`子任务 ${this.state.children.length}`)).fontSize(12).height(34).backgroundColor(Color.Transparent)
                .fontColor('#4B78E6').onClick(() => { this.showChildren = true })
            }
            Button(runtime.translate('信息')).padding({ left: 8, right: 8 }).fontSize(12).height(34).backgroundColor(Color.Transparent)
              .fontColor($r('sys.color.font_secondary')).onClick(() => { this.showInfo = true; this.invoke('sessionInfo') })
            Button(runtime.translate(this.traceMode ? '对话' : '轨迹')).padding({ left: 8, right: 8 }).fontSize(12).height(34).backgroundColor(Color.Transparent)
              .fontColor(this.traceMode ? '#4B78E6' : $r('sys.color.font_secondary'))
              .onClick(() => { this.traceMode = !this.traceMode; this.traceQuery = ''; this.traceCategory = 'all' })
          }
          Button(runtime.translate('切换主机')).fontSize(12).height(34).backgroundColor(Color.Transparent).fontColor('#4B78E6').onClick(() => { this.showHostSwitcher = true; this.invoke('refresh') })
          Button('☰').accessibilityText(runtime.translate('工作区与会话')).width(36).padding(0).fontSize(17).height(34).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
            .onClick(() => { this.openDrawer() })
          Button(runtime.translate('断开')).padding({ left: 8, right: 8 }).fontSize(12).height(34).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
            .onClick(() => { this.invoke('disconnect') })
        }
      } else if (this.state.canReconnect) {
        // Android offers 重新连接当前对话 once a carrier is gone but the host is known.
        Button(runtime.translate('重新连接')).fontSize(12).height(34).backgroundColor(Color.Transparent).fontColor('#4B78E6')
          .onClick(() => { this.invoke('reconnect') })
        Button('⚙').fontSize(16).height(34).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.showSettings = true })
      } else {
        Button('⚙').fontSize(16).height(34).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.showSettings = true })
      }
    }.padding({ left: 16, right: 16, top: 12, bottom: 12 }).width('100%')
  }

  @Builder
  login() {
    Scroll() {
      Column({ space: 18 }) {
        Image($r('app.media.app_icon')).width(64).height(64).borderRadius(18).margin({ top: 20 })
        Text(runtime.translate('让工作，随你而行')).fontSize(27).fontWeight(FontWeight.Bold)
        Text(runtime.translate('连接电脑上的 Harness、CodeX 与 ACP 工作区'))
          .fontSize(14).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
        Column({ space: 14 }) {
          TextInput({ text: this.server, placeholder: runtime.translate('服务器 HTTPS 地址') }).onChange((value: string) => { this.server = value })
          TextInput({ text: this.email, placeholder: runtime.translate('邮箱') }).type(InputType.Email).onChange((value: string) => { this.email = value })
          TextInput({ text: this.password, placeholder: runtime.translate('密码') }).type(InputType.Password).onChange((value: string) => { this.password = value })
          Button(runtime.translate('登录并注册本机')).width('100%').height(48).backgroundColor('#4B78E6')
            .enabled(!this.state.busy && this.email.length > 0 && this.password.length > 0)
            .onClick(() => {
              const password: string = this.password
              this.password = ''
              runtime.perform('login', JSON.stringify({ server: this.server, email: this.email, password: password })).catch(() => {})
            })
        }.padding(20).borderRadius(22).backgroundColor($r('sys.color.comp_background_primary')).width('100%')
        Text(runtime.translate('或使用网页 OAuth 授权登录')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Row({ space: 12 }) {
          Button(runtime.translate('使用 GitHub 登录')).layoutWeight(1).enabled(!this.state.busy)
            .onClick(() => { runtime.perform('startOAuth', JSON.stringify({ server: this.server, provider: 'github' })).catch(() => {}) })
          Button(runtime.translate('使用知乎登录')).layoutWeight(1).enabled(!this.state.busy)
            .onClick(() => { runtime.perform('startOAuth', JSON.stringify({ server: this.server, provider: 'zhihu' })).catch(() => {}) })
        }
        Text(runtime.translate('将在浏览器中打开授权页面，完成授权后自动返回。'))
          .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
        Text(runtime.translate('或使用另一台设备扫码授权')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Row({ space: 12 }) {
          Button(runtime.translate('GitHub 扫码')).layoutWeight(1).enabled(!this.state.busy)
            .onClick(() => { runtime.perform('qr', JSON.stringify({ server: this.server, provider: 'github' })).catch(() => {}) })
          Button(runtime.translate('知乎扫码')).layoutWeight(1).enabled(!this.state.busy)
            .onClick(() => { runtime.perform('qr', JSON.stringify({ server: this.server, provider: 'zhihu' })).catch(() => {}) })
        }
        if (this.state.qrUrl) {
          QRCode(this.state.qrUrl).width(220).height(220).backgroundColor(Color.White).color(Color.Black)
          Text(runtime.translate('使用另一台设备扫描并完成授权')).fontSize(13)
          Button(runtime.translate('取消扫码')).onClick(() => { this.invoke('cancelQr') })
        }
        Text(runtime.translate('凭据保存在鸿蒙安全资产中。聊天内容不写入本地存储。'))
          .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
      }.padding(24).constraintSize({ maxWidth: 560 }).width('100%')
    }.layoutWeight(1).width('100%')
  }

  @Builder
  trust() {
    Column({ space: 20 }) {
      Text(runtime.translate('确认主机身份')).fontSize(25).fontWeight(FontWeight.Bold)
      Text(this.state.candidate.name).fontSize(19)
      Text(runtime.translate('请在电脑端核对指纹，确认这是你要连接的主机。')).fontSize(15).textAlign(TextAlign.Center)
      Text(this.state.candidate.fingerprint).fontSize(30).fontWeight(FontWeight.Bold)
        .fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
      Text(runtime.translate(this.state.candidate.trusted ? '已保存此主机身份' : '首次信任后，公钥改变将阻止连接'))
        .fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (!this.state.candidate.online) {
        Text(runtime.translate('主机当前离线。请在电脑端打开 DeepSeek Harness 与 DSH Remote 插件，再重试连接。'))
          .fontSize(13).fontColor('#C64B43').textAlign(TextAlign.Center)
      }
      Button(runtime.translate(this.state.candidate.trusted ? '连接主机' : '指纹一致，信任并连接'))
        .backgroundColor('#4B78E6').enabled(!this.state.busy)
        .onClick(() => { this.invoke('trustHost', this.state.candidate.id) })
      Row({ space: 10 }) {
        Button(runtime.translate('解除这台主机的绑定')).layoutWeight(1).backgroundColor(Color.Transparent).fontColor('#C64B43')
          .enabled(!this.state.busy).onClick(() => { this.confirmForget = true })
        Button(runtime.translate('重命名主机')).layoutWeight(1).enabled(!this.state.busy && this.rename.trim().length > 0)
          .onClick(() => { runtime.perform('renameHost', JSON.stringify({ id: this.state.candidate.id, name: this.rename } as ActionInput)).catch(() => {}) })
      }.width('100%')
      if (this.confirmForget) {
        Text(runtime.translate('解除后会从账号中移除这台设备并断开连接，需要在电脑端重新绑定。'))
          .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
        Row({ space: 10 }) {
          Button(runtime.translate('确认解除')).layoutWeight(1).backgroundColor('#8C3B36').fontColor(Color.White)
            .onClick(() => { runtime.perform('forgetHost', JSON.stringify({ id: this.state.candidate.id } as ActionInput)).catch(() => {}); this.confirmForget = false })
          Button(runtime.translate('返回')).layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
            .onClick(() => { this.confirmForget = false })
        }.width('100%')
      }
    }.padding(28).constraintSize({ maxWidth: 560 }).width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
  }

  private archiveLabel(): string {
    if (this.state.archiveFilter === 'all') { return '全部对话' }
    if (this.state.archiveFilter === 'only') { return '仅已归档' }
    return '隐藏已归档'
  }
  private nextArchiveFilter(): string {
    if (this.state.archiveFilter === 'hidden') { return 'all' }
    return this.state.archiveFilter === 'all' ? 'only' : 'hidden'
  }
  /** With a search active the drawer collapses to the matching sessions only. */
  private shownOverview(): OverviewRow[] {
    const needle: string = this.query.trim().toLowerCase()
    if (needle.length === 0) { return this.state.overview.filter((row: OverviewRow) => row.kind !== 'session' || !row.hidden) }
    return this.state.overview.filter((row: OverviewRow) => row.kind === 'session' && row.name.toLowerCase().includes(needle))
  }

  @Builder
  backendTabs() {
    if (this.state.backends.length > 1) {
      Scroll() {
      Row({ space: 8 }) {
        ForEach(this.state.backends, (tab: BackendTab) => {
          Button(this.backendLabel(tab)).fontSize(13).height(34).flexShrink(0)
            .backgroundColor(this.state.backend === tab.id ? '#20386B' : $r('sys.color.comp_background_tertiary'))
            .fontColor(this.state.backend === tab.id ? '#8FB0F7' : $r('sys.color.font_primary'))
            .onClick(() => { this.send('backend', { backend: tab.id }) })
        }, (tab: BackendTab) => `${tab.id}|${tab.name}|${tab.count}|${this.state.backend === tab.id ? 'on' : 'off'}`)
      }.padding({ left: 16, right: 16 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }
  }

  @Builder
  viewOptions() {
    Row({ space: 8 }) {
      Button(runtime.translate(this.state.groupBy === 'workspace' ? '按工作区' : '平铺列表')).fontSize(12).height(30)
        .backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
        .onClick(() => { this.send('groupMode', { mode: this.state.groupBy === 'workspace' ? 'list' : 'workspace' }) })
      Button(runtime.translate(this.state.orderBy === 'updated' ? '最近更新' : '手动排序')).fontSize(12).height(30)
        .backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
        .onClick(() => { this.send('sortMode', { mode: this.state.orderBy === 'updated' ? 'manual' : 'updated' }) })
      Button(this.archiveLabel()).fontSize(12).height(30)
        .backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
        .onClick(() => { this.send('archiveFilter', { mode: this.nextArchiveFilter() }) })
      Blank()
      Text(runtime.translate(`已归档 ${this.state.archivedCount}`)).fontSize(11).fontColor($r('sys.color.font_secondary'))
    }.width('100%').padding({ left: 16, right: 16 })
  }

  @Builder
  /** Android keeps the cross-workspace session list in a right-anchored drawer. */
  drawer(persistent: boolean = false) {
    Row() {
      if (!persistent) Column().layoutWeight(1).height('100%').backgroundColor('#80000000').onClick(() => { this.closeDrawer() })
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text(this.hostName()).fontSize(17).fontWeight(FontWeight.Bold).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .onClick(() => { this.closeDrawer() })
          Button('⟳').accessibilityText(runtime.translate('刷新')).fontSize(16).width(34).height(34).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.font_secondary')).enabled(!this.state.busy).onClick(() => { this.invoke('catalog') })
          Button('✕').accessibilityText(runtime.translate('关闭')).fontSize(16).width(34).height(34).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.font_secondary')).onClick(() => { this.closeDrawer() })
        }.width('100%').padding({ left: 14, right: 8, top: 14 })
        Button(runtime.translate('＋ 新建对话')).fontSize(15).height(44).width('100%').backgroundColor('#4B78E6')
          .enabled(!this.state.busy && this.state.connected)
          .onClick(() => { this.closeDrawer(); this.invoke('newSession') })
        // Android pins 插件 and 自动化任务 between the new-session button and the backend tabs.
        Row({ space: 12 }) {
          Text('🧩').fontSize(15).width(22).textAlign(TextAlign.Center).fontColor($r('sys.color.font_secondary'))
          Text(runtime.translate('插件')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(16).fontColor($r('sys.color.font_secondary'))
        }.width('100%').height(42).padding({ left: 14, right: 12 })
          .onClick(() => { this.closeDrawer(); this.openPlugins() })
        Row({ space: 12 }) {
          Text('⏰').fontSize(15).width(22).textAlign(TextAlign.Center).fontColor($r('sys.color.font_secondary'))
          Text(runtime.translate('自动化任务')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(16).fontColor($r('sys.color.font_secondary'))
        }.width('100%').height(42).padding({ left: 14, right: 12 })
          .onClick(() => { this.closeDrawer(); this.openTasks() })
        Row({ space: 12 }) {
          Text('🤖').fontSize(15).width(22).textAlign(TextAlign.Center).fontColor($r('sys.color.font_secondary'))
          Text(runtime.translate('Bot 团队')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(16).fontColor($r('sys.color.font_secondary'))
        }.width('100%').height(42).padding({ left: 14, right: 12 })
          .onClick(() => { this.closeDrawer(); this.openBots() })
        Row({ space: 12 }) {
          Text('🌐').fontSize(15).width(22).textAlign(TextAlign.Center).fontColor($r('sys.color.font_secondary'))
          Text(runtime.translate('网络与链路')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(16).fontColor($r('sys.color.font_secondary'))
        }.width('100%').height(42).padding({ left: 14, right: 12 })
          .onClick(() => { this.closeDrawer(); this.openNetwork() })
        Row({ space: 12 }) {
          Text('⚙').fontSize(15).width(22).textAlign(TextAlign.Center).fontColor($r('sys.color.font_secondary'))
          Text(runtime.translate('设置')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(16).fontColor($r('sys.color.font_secondary'))
        }.width('100%').height(42).padding({ left: 14, right: 12 })
          .onClick(() => { this.closeDrawer(); this.showSettings = true })
        this.backendTabs()
        Row({ space: 4 }) {
          Text(runtime.translate('工作区')).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
          Button('🔍').fontSize(14).width(32).height(32).backgroundColor(Color.Transparent)
            .fontColor(this.drawerSearch ? '#4B78E6' : $r('sys.color.font_secondary'))
            .onClick(() => { this.drawerSearch = !this.drawerSearch })
          Button('⚙').fontSize(14).width(32).height(32).backgroundColor(Color.Transparent)
            .fontColor(this.drawerOptions ? '#4B78E6' : $r('sys.color.font_secondary'))
            .onClick(() => { this.drawerOptions = !this.drawerOptions })
        }.width('100%').padding({ left: 14, right: 8 })
        if (this.drawerSearch) {
          TextInput({ text: this.query, placeholder: runtime.translate('搜索会话') }).width('92%')
            .onChange((value: string) => { this.query = value })
        }
        if (this.drawerOptions || this.state.archiveFilter !== 'hidden') { this.viewOptions() }
        List({ space: 6 }) {
        ForEach(this.shownOverview(), (row: OverviewRow) => {
          if (row.kind === 'group') {
            ListItem() {
              Row({ space: 8 }) {
                Text(row.expanded ? '⌄' : '›').fontSize(15).width(18).flexShrink(0).fontColor($r('sys.color.font_secondary'))
                Column({ space: 2 }) {
                  Text(row.name).width('100%').fontSize(16).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.description).width('100%').fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(row.meta).fontSize(12).flexShrink(0).fontColor($r('sys.color.font_secondary'))
                if (row.target.length > 0) {
                  Button(row.favorite ? '★' : '☆').fontSize(17).width(36).height(36).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
                    .fontColor(row.favorite ? '#D8A33F' : $r('sys.color.font_secondary'))
                    .onClick(() => { this.send('favorite', { id: row.target }) })
                }
              }.width('100%').padding({ left: 12, right: 6, top: 10, bottom: 10 })
                .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(14)
            }.onClick(() => { this.send('toggleGroup', { id: row.id }) })
          } else if (row.kind === 'more') {
            ListItem() {
              Text(row.name).fontSize(13).fontColor('#4B78E6').width('100%').padding(12).textAlign(TextAlign.Center)
            }.onClick(() => { this.send('showMore', { id: row.target }) })
          } else {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text(row.name).width('100%').fontSize(16).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontWeight(row.selected ? FontWeight.Bold : FontWeight.Normal)
                  Text(`${row.description}${row.meta.length > 0 ? ' · ' + row.meta : ''}`)
                    .width('100%').fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (row.selected) { Text(runtime.translate('当前')).fontSize(11).fontColor('#4B78E6') }
                Button(runtime.translate('归档')).fontSize(12).height(30).backgroundColor(Color.Transparent)
                  .fontColor($r('sys.color.font_secondary'))
                  .onClick(() => { this.send('archive', { id: row.id }) })
              }.width('100%').padding({ left: 16, right: 8, top: 12, bottom: 12 })
                .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(16)
            }.enabled(!this.state.busy).onClick(() => { this.closeDrawer(); this.invoke('session', row.id) })
          }
        }, (row: OverviewRow) => `${row.id}|${row.kind}|${row.name}|${row.description}|${row.meta}`
          + `|${row.expanded}|${row.hidden}|${row.favorite}|${row.selected}|${row.remaining}`)
        if (this.state.overview.length === 0 && !this.state.busy && !this.state.error) {
          ListItem() { Text(runtime.translate('这台主机还没有可见会话。')).padding(24).fontColor($r('sys.color.font_secondary')) }
        }
        }.layoutWeight(1).width('100%').padding({ left: 12, right: 12 })
      }.width(persistent ? 320 : '86%').height('100%').alignItems(HorizontalAlign.Start)
        .backgroundColor($r('sys.color.background_primary'))
    }.width(persistent ? 320 : '100%').height('100%')
  }

  private workspaceExpanded(id: string): boolean {
    return this.state.workspaceOverview.some((row: OverviewRow) => row.kind === 'group' && row.target === id && row.expanded)
  }
  private workspaceChildren(id: string): OverviewRow[] {
    const result: OverviewRow[] = []
    let inside: boolean = false
    for (const row of this.state.workspaceOverview) {
      if (row.kind === 'group') inside = row.target === id
      else if (inside && !row.hidden) result.push(row)
    }
    return result
  }
  private toggleWorkspace(id: string): void {
    const group: OverviewRow | undefined = this.state.workspaceOverview.find((row: OverviewRow) => row.kind === 'group' && row.target === id)
    if (group) this.send('toggleGroup', { id: group.id })
  }
  @Builder
  workspaceSessions(id: string) {
    ForEach(this.workspaceChildren(id), (child: OverviewRow) => {
      Row({ space: 8 }) {
        Text(child.kind === 'more' ? '…' : '☰').fontSize(14).width(24).flexShrink(0).fontColor($r('sys.color.font_secondary'))
        Column({ space: 4 }) {
          Text(child.name).fontSize(15).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if (child.kind !== 'more') Text(child.description + ' · ' + child.meta).fontSize(11).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.padding({ left: 30, right: 12, top: 12, bottom: 12 }).width('100%')
        .accessibilityText(child.name).onClick(() => { this.send(child.kind === 'more' ? 'showMore' : 'session', { id: child.kind === 'more' ? child.target : child.id }) })
    }, (child: OverviewRow) => `${child.id}|${child.name}|${child.meta}`)
  }
  @Builder
  catalog() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: runtime.translate('搜索主机、工作区或会话') }).layoutWeight(1)
          .onChange((value: string) => { this.query = value })
        Button(runtime.translate('刷新')).enabled(!this.state.busy)
          .onClick(() => { this.invoke(this.state.view === 'devices' ? 'refresh' : 'catalog') })
      }.padding({ left: 16, right: 16 })
      if (this.state.view !== 'devices') {
        this.backendTabs()
        Row({ space: 8 }) {
          Button(runtime.translate('选择主机目录')).fontSize(12).onClick(() => { this.send('hostDirectory', {}); this.alignmentPanel = 'directory' })
          Button(runtime.translate('管理对话')).fontSize(12).onClick(() => { this.alignmentPanel = 'sessions' })
        }.width('100%').justifyContent(FlexAlign.Center)
      }
      if (this.state.view === 'devices') {
        Text(this.state.account).fontSize(12).fontColor($r('sys.color.font_secondary'))
        List({ space: 10 }) {
          ForEach(this.state.devices.filter((row: DeviceRow) => row.name.toLowerCase().includes(this.query.toLowerCase())), (row: DeviceRow) => {
            ListItem() {
              Column({ space: 8 }) {
                Text(row.name).fontSize(19).fontWeight(FontWeight.Medium).width('100%')
                Text(row.description + (row.trusted ? ' · 已信任' : ' · 待核对指纹')).fontSize(13).width('100%')
                  .fontColor(row.online ? '#39966C' : $r('sys.color.font_secondary'))
              }.padding(20).width('100%').backgroundColor($r('sys.color.comp_background_primary')).borderRadius(20)
            }.enabled(!this.state.busy).onClick(() => { this.invoke(row.trusted ? 'connect' : 'inspectHost', row.id) })
          }, (row: DeviceRow) => `${row.id}|${row.name}|${row.description}|${row.online}|${row.trusted}`)
          if (!this.state.busy && this.state.devices.length === 0 && !this.state.error) {
            ListItem() { Text(runtime.translate('没有已授权主机。请先在电脑端登录同一账号。')).padding(24) }
          }
        }.padding({ left: 16, right: 16 }).layoutWeight(1).width('100%')
        Button(runtime.translate('退出本机账号')).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
          .onClick(() => { this.invoke('logout') })
      } else {
        List({ space: 10 }) {
          ForEach((this.state.view === 'workspaces' ? this.state.workspaces : this.state.sessions)
            .filter((row: CatalogRow) => (row.name + row.description).toLowerCase().includes(this.query.toLowerCase())), (row: CatalogRow) => {
            ListItem() {
              Column() {
              Row({ space: 8 }) {
                if (this.state.view === 'workspaces') {
                  Button(this.workspaceExpanded(row.id) ? '📂' : '📁').width(36).height(44).padding(0).flexShrink(0)
                    .backgroundColor(Color.Transparent).accessibilityText(runtime.translate(this.workspaceExpanded(row.id) ? '折叠工作区' : '展开工作区'))
                    .onClick(() => { this.toggleWorkspace(row.id) })
                }
                Column({ space: 8 }) {
                  Text(row.name).fontSize(18).fontWeight(FontWeight.Medium).width('100%').maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.description).fontSize(12).width('100%').fontColor($r('sys.color.font_secondary')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).ellipsisMode(EllipsisMode.CENTER)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  .onClick(() => { if (this.state.view === 'workspaces') this.toggleWorkspace(row.id); else this.invoke('session', row.id) })
                if (this.state.view === 'workspaces') {
                  Text(`${row.count}`).fontSize(12).flexShrink(0).fontColor($r('sys.color.font_secondary'))
                  Button('+').width(34).height(38).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
                    .fontColor('#4B78E6').accessibilityText(runtime.translate('在此工作区新建对话')).enabled(!this.state.busy)
                    .onClick(() => { this.send('newSessionIn', { id: row.id }) })
                  // Fixed icon hit areas must not inherit the Button text padding.
                  Button(row.favorite ? '★' : '☆').accessibilityText(runtime.translate(row.favorite ? '取消收藏' : '收藏工作区')).fontSize(18).width(38).height(38).padding(0).flexShrink(0)
                    .backgroundColor(Color.Transparent).fontColor(row.favorite ? '#D8A33F' : $r('sys.color.font_secondary'))
                    .onClick(() => { this.send('favorite', { id: row.id }) })
                  Button('⋮').accessibilityText(runtime.translate('管理工作区')).fontSize(18).width(34).height(38).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
                    .fontColor($r('sys.color.font_secondary'))
                    .onClick(() => { this.manageTarget = row; this.workspaceName = row.name; this.confirmDelete = '' })
                } else {
                  Button(runtime.translate('归档')).fontSize(12).height(32).backgroundColor(Color.Transparent)
                    .fontColor($r('sys.color.font_secondary'))
                    .onClick(() => { this.send('archive', { id: row.id }) })
                }
              }.padding({ left: 16, right: 10, top: 14, bottom: 14 }).width('100%')
                .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(20).alignItems(VerticalAlign.Center)
              if (this.state.view === 'workspaces' && this.workspaceExpanded(row.id)) this.workspaceSessions(row.id)
              }.width('100%')
            }.enabled(!this.state.busy)
              // Android opens 管理工作区 from a long press on the workspace row.
              .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                if (this.state.view !== 'workspaces') return
                this.manageTarget = row; this.workspaceName = row.name; this.confirmDelete = ''
              }))
          }, (row: CatalogRow) => `${row.id}|${row.name}|${row.description}|${row.count}|${row.favorite}|${row.archived}|${this.workspaceExpanded(row.id)}|${this.workspaceChildren(row.id).map((child: OverviewRow): string => child.id + child.name + child.meta).join(";")}`)
          if (!this.state.busy && (this.state.view === 'workspaces' ? this.state.workspaces : this.state.sessions).length === 0 && !this.state.error) {
            ListItem() { Text(runtime.translate(this.state.view === 'workspaces' ? '当前主机没有可用工作区。' : '还没有会话，可以新建对话。')).padding(24) }
          }
        }.padding({ left: 16, right: 16 }).layoutWeight(1).width('100%')
        if (this.state.view === 'sessions') {
          Button(runtime.translate('＋ 新建对话')).backgroundColor('#4B78E6').enabled(!this.state.busy && this.state.connected)
            .onClick(() => { this.invoke('newSession') }).margin({ bottom: 16 })
        } else {
          Row({ space: 8 }) {
            TextInput({ text: this.directory, placeholder: runtime.translate('Harness 新工作区的绝对路径') }).layoutWeight(1)
              .onChange((value: string) => { this.directory = value })
            Button(runtime.translate('创建')).enabled(!this.state.busy && this.directory.length > 0)
              .onClick(() => { runtime.perform('newWorkspace', JSON.stringify({ path: this.directory })).catch(() => {}) })
          }.padding(16)
        }
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  chat() {
    Column() {
      if (this.state.models.length > 0) {
        Button(runtime.translate(this.state.selectedModel || '选择模型')).fontSize(12).height(32)
          .backgroundColor(Color.Transparent).fontColor('#4B78E6').enabled(!this.state.running && !this.state.busy)
          .onClick(() => { this.showModels = !this.showModels })
      }
      if (this.showModels) {
        Select(this.state.models.map((model: ModelRow): SelectOption => ({ value: model.name })))
          .selected(this.selectedModel).value('选择模型').onSelect((index: number) => { this.selectedModel = index; this.effort = '' })
        if (this.state.models[this.selectedModel]?.efforts.length > 0) {
          Select(this.state.models[this.selectedModel].efforts.map((item: ModelEffort): SelectOption => ({ value: item.name })))
            .value('思考强度').onSelect((index: number) => { this.effort = this.state.models[this.selectedModel].efforts[index].id })
        }
        Button(runtime.translate('应用模型')).onClick(() => {
          const model: ModelRow = this.state.models[this.selectedModel]
          if (model) runtime.perform('model', JSON.stringify({ provider: model.provider, model: model.model, effort: this.effort })).catch(() => {})
          this.showModels = false
        })
      }
      if (this.state.modelWarning) { Text(this.state.modelWarning).fontSize(11).fontColor($r('sys.color.font_secondary')).padding(8) }
      if (this.traceMode) { this.traceControls() }
      List({ space: 12, scroller: this.scroller }) {
        if (this.state.hasMore) {
          ListItem() { Button(runtime.translate('加载更早消息')).enabled(!this.state.busy).onClick(() => { this.invoke('history') }) }
        }
        ForEach(this.state.botExtras, (row: BotExtra) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(row.title).fontSize(13).width('100%')
              if (row.view && row.view.length > 0) LocalSurface({ kind: 'bot', payload: row.view, onAction: async (): Promise<boolean> => false })
              else LocalSurface({ kind: 'markdown', scope: this.state.sessionKey, dark: (getContext(this) as common.UIAbilityContext).config.colorMode === 0,
                payload: JSON.stringify({ text: row.text, density: this.state.typographyDensity, dark: (getContext(this) as common.UIAbilityContext).config.colorMode === 0 }),
                onAction: async (raw: string): Promise<boolean> => {
                  const event: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
                  return event.type === 'link' ? runtime.perform('openLink', JSON.stringify({ text: event.url })) : false
                } })
            }.width('100%')
          }
        }, (row: BotExtra) => row.id + row.state + row.text.length)
        ForEach(this.traceMode ? this.traceRows() : this.state.rows, (row: TimelineRow) => {
          ListItem() {
            if (this.traceMode) {
              TraceEntry({ row: row, label: this.categoryLabel(row.category), onFork: this.forkRow, onFeedback: this.rateRow })
            } else {
              TimelineCard({ row: row, scope: this.state.sessionKey, dark: (getContext(this) as common.UIAbilityContext).config.colorMode === 0, density: this.state.typographyDensity, onFork: this.forkRow, onFeedback: this.rateRow,
                onApproval: (id: string, decision: string) => {
                  runtime.perform('approval', JSON.stringify({ id: id, decision: decision })).catch(() => {})
                }, onQuestion: (id: string, answers: QuestionAnswer[]) => {
                  runtime.perform('question', JSON.stringify({ id: id, answers: answers })).catch(() => {})
                } })
            }
          }
        // A streaming message keeps its id, so the content it renders has to enter the key.
        }, (row: TimelineRow) => `${row.id}|${row.kind}|${row.category}|${row.turn}|${row.clock}|${row.title}`
          + `|${row.text.length}|${row.detail.length}|${row.preview.length}|${row.attachments}|${row.images.length}`
          + `|${row.pending}|${row.actionable}|${row.feedback}|${row.tokens}|${row.questions === undefined ? 0 : row.questions.length}`
          + `|${row.botReplies === undefined ? 0 : row.botReplies.length}|${row.turnStatus}|${row.turnDetail}`)
        ForEach(this.state.botAsides, (row: BotExtra) => {
          ListItem() {
            Column({ space: 4 }) {
              Text(row.title).fontSize(14).width('100%')
              Text(row.text || row.state).fontSize(13).width('100%').copyOption(CopyOptions.LocalDevice)
              if (row.state === 'answering') Button(runtime.translate('取消旁问')).enabled(this.state.botReadOnly.length === 0).onClick(() => { this.send('botOperation', { mode: 'btw-cancel', text: JSON.stringify({ sessionId: this.state.botTarget, id: row.id }) }) })
            }.width('100%')
          }
        }, (row: BotExtra) => row.id + row.state + row.text.length)
        if (this.state.botView.length > 2) {
          ListItem() {
            LocalSurface({ kind: 'bot', payload: this.state.botView, onAction: async (raw: string): Promise<boolean> => {
              const event: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
              if (event.type === 'link') return runtime.perform('openLink', JSON.stringify({ text: event.url }))
              const pending: BotPending = JSON.parse(this.state.botView) as BotPending
              return runtime.perform('botViewReply', JSON.stringify({ text: raw, name: pending.id, mode: this.state.sessionKey }))
            } })
          }
        }
      ForEach(this.state.failedSends, (row: FailedSend) => {
        ListItem() {
        Column({ space: 6 }) {
          Text(row.text).fontSize(13).maxLines(3).width('100%')
          Text(runtime.translate('送达结果未确认：' + row.error)).fontSize(12).fontColor('#C64B43').width('100%')
          Row({ space: 12 }) {
            Button(runtime.translate('重新发送')).enabled(this.state.connected && !this.state.busy).onClick(() => {
              promptAction.showDialog({ title: '确认重新发送', message: '主机可能已收到原消息。重新发送可能产生重复任务，是否继续？', buttons: [{ text: '取消', color: '#888888' }, { text: '重新发送', color: '#4B78E6' }] }).then((result: promptAction.ShowDialogSuccessResponse) => { if (result.index === 1) this.send('retrySend', { id: row.id, enabled: true }) })
            })
            Button(runtime.translate('移除')).onClick(() => { this.send('dismissSend', { id: row.id }) })
          }
        }.padding(10).width('100%')
        }
      }, (row: FailedSend) => row.id)
        if (!this.traceMode && this.state.rows.length === 0 && this.state.botExtras.length === 0 && !this.state.busy) {
          ListItem() {
            Column({ space: 10 }) {
              Text(runtime.translate('预览版')).fontSize(11).fontColor('#4B78E6').padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(10)
              Text(this.welcomeTitle()).fontSize(20).fontWeight(FontWeight.Bold)
              Text(this.welcomeBody()).fontSize(14).fontColor($r('sys.color.font_secondary'))
                .textAlign(TextAlign.Center)
              Text(this.policyHint()).fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
            }.width('100%').padding({ left: 26, right: 26, top: 40, bottom: 24 })
              .alignItems(HorizontalAlign.Center)
          }
        }
        if (this.traceMode && this.state.rows.length > 0 && this.traceRows().length === 0) {
          ListItem() { Text(runtime.translate('没有匹配的已加载轨迹')).padding(24).fontColor($r('sys.color.font_secondary')) }
        }
        if (!this.traceMode && this.state.rows.length === 0 && this.state.botExtras.length === 0 && !this.state.busy) {
          ListItem() { Text(runtime.translate('继续电脑上的工作，或发送第一条消息。')).padding(24).fontColor($r('sys.color.font_secondary')) }
        }
      }.layoutWeight(1).width('100%').padding({ left: 16, right: 16 })
        .onScrollIndex((start: number) => { this.firstVisibleRow = start })
        .onScrollStart(() => { if (!this.restoringReading) this.pinnedToBottom = false })
        .onScrollStop(() => { this.saveReadingPosition() })
        .onAreaChange(() => { this.restoreReadingPosition() })
      if (this.state.connected) {
        Row({ space: 8 }) {
          Button(runtime.translate('活动')).fontSize(12).height(32).onClick(() => { this.alignmentPanel = 'activity' })
          Button(runtime.translate('管理对话')).fontSize(12).height(32).onClick(() => { this.alignmentPanel = 'sessions' })
          Button(runtime.translate(this.expandedComposer ? '收起输入' : '展开输入')).fontSize(12).height(32).onClick(() => { this.expandedComposer = !this.expandedComposer })
        }.width('100%').justifyContent(FlexAlign.Center)
      }
      if (this.state.botTarget.length > 0) {
        if (this.state.botReadOnly.length > 0) Text(this.state.botReadOnly).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
        Row({ space: 8 }) {
          Button(runtime.translate('更早记录')).onClick(() => { this.invoke('botEarlier') })
          Button(runtime.translate('刷新智能体')).onClick(() => { this.invoke('botRefresh') })
          Button(runtime.translate('旁问 /btw')).enabled(this.state.botReadOnly.length === 0).onClick(() => { this.draft = '/btw ' + this.draft })
        }.width('100%')
      }
      if (this.state.activity.rows.length > 0 || this.state.activity.jobs.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(['todos', 'goal', 'team', 'subagents'], (category: string) => {
              if (this.state.activity.rows.some((row: ActivityRow) => row.category === category)) {
                Button(runtime.translate(category === 'todos' ? '待办' : category === 'goal' ? '目标' : category === 'team' ? '团队' : '子任务') + ' ' + this.state.activity.rows.filter((row: ActivityRow) => row.category === category && row.status === 'completed').length + '/' + this.state.activity.rows.filter((row: ActivityRow) => row.category === category).length)
                  .fontSize(11).height(32).onClick(() => { this.alignmentPanel = 'activity' })
              }
            }, (category: string) => category)
            if (this.state.activity.jobs.length > 0) Button(runtime.translate('后台任务') + ' ' + this.state.activity.jobs.filter((job: JobRow) => job.status === 'running').length).fontSize(11).height(32).onClick(() => { this.alignmentPanel = 'activity' })
          }.padding({ left: 16, right: 16 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.state.running) {
        Row({ space: 12 }) {
          LoadingProgress().width(18).height(18)
          Text(runtime.translate('主机正在回复')).fontSize(12).layoutWeight(1)
          Button(runtime.translate('停止')).fontSize(12).height(32).onClick(() => { this.invoke('interrupt') })
        }.padding({ left: 24, right: 24, top: 8 })
      }
      ForEach(this.state.stagedFiles, (file: StagedFile) => {
        Row({ space: 8 }) {
          Text(file.name).fontSize(12).layoutWeight(1).maxLines(1)
          Button(runtime.translate('移除')).onClick(() => { this.send('removeFile', { id: file.id }) })
        }.width('100%').padding({ left: 24, right: 24 })
      }, (file: StagedFile) => file.id)
      ForEach(this.promptImages, (image: PromptAttachment, index: number) => {
        Row({ space: 8 }) {
          Image(`data:${image.mediaType};base64,${image.data}`).width(36).height(36).objectFit(ImageFit.Contain)
          Text(runtime.translate(`图片 ${index + 1}`)).fontSize(12).layoutWeight(1)
          Button(runtime.translate('移除')).onClick(() => { this.promptImages = this.promptImages.filter((row: PromptAttachment, at: number) => at !== index); this.image = this.promptImages[0]?.data ?? '' })
        }.padding({ left: 24, right: 24 }).width('100%')
      }, (image: PromptAttachment, index: number) => String(index) + image.data.slice(0,32))
      if (this.imageError) { Text(this.imageError).fontSize(12).fontColor('#C64B43').padding(8) }
      if (this.state.queue.length > 0) {
        Column({ space: 6 }) {
          Text(runtime.translate(`排队中 ${this.state.queue.length} 条消息`)).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
          ForEach(this.state.queue, (item: QueueRow) => {
            Row({ space: 8 }) {
              Text(item.preview).fontSize(13).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(runtime.translate('等待执行')).fontSize(11).fontColor($r('sys.color.font_secondary'))
              if (item.id.length > 0) {
                Button(runtime.translate('立即发送')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#4B78E6')
                  .onClick(() => { this.send('queueAction', { id: item.id, mode: 'steer' }) })
                Button(runtime.translate('移出队列')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor($r('sys.color.font_secondary'))
                  .onClick(() => { this.send('queueAction', { id: item.id, mode: 'remove' }) })
              }
            }.width('100%')
          }, (item: QueueRow) => `${item.id}|${item.preview}`)
        }.padding({ left: 26, right: 22, top: 10, bottom: 10 }).width('100%')
          .backgroundColor($r('sys.color.comp_background_tertiary'))
      }
      Column({ space: 8 }) {
        TextArea({ text: this.draft, placeholder: runtime.translate('向远程会话发送消息…') })
          .height(this.expandedComposer ? 220 : 72).width('100%').onChange((value: string) => { this.draft = value; runtime.perform('saveDraft', JSON.stringify({ id: this.lastSession, text: value })).catch(() => {}) })
        Row({ space: 10 }) {
        Button('＋').width(36).height(36).onClick(() => { this.openMore() }).enabled(!this.state.busy && this.state.connected)
        Button(runtime.translate('快捷提示词')).fontSize(12).height(36).backgroundColor(Color.Transparent).fontColor('#4B78E6')
          .enabled(!this.state.busy && this.state.connected).onClick(() => { this.openPrompts() })
        Blank()
        Button(runtime.translate('发送')).height(44).backgroundColor('#4B78E6')
          .enabled(this.state.connected && !this.state.busy && (this.state.botTarget.length === 0 || this.state.botReadOnly.length === 0) && (this.draft.trim().length > 0 || this.image.length > 0 || this.state.stagedFiles.length > 0))
          .onClick(() => {
            const text: string = this.draft
            const failedCount: number = this.state.failedSends.length
            const image: string = this.image
            const images: PromptAttachment[] = this.promptImages.map((value: PromptAttachment): PromptAttachment => ({ data: value.data, mediaType: value.mediaType }))
            runtime.perform('prompt', JSON.stringify({ text: text, images: images }))
              .then((success: boolean) => {
                const retained: boolean = this.state.failedSends.length > failedCount
                if ((success || retained) && this.draft === text) this.draft = ''
                if ((success || retained) && this.image === image) { this.image = ''; this.promptImages = [] }
                if (success || retained) runtime.perform('saveDraft', JSON.stringify({ id: this.lastSession, text: '' } as ActionInput)).catch(() => {})
              }).catch(() => {})
          })
        }.width('100%').alignItems(VerticalAlign.Center)
      }.padding(16).width('100%')
    }.width('100%').layoutWeight(1)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      RtcSurface()
      // Literal translations have no ArkUI state dependency. Recreate only
      // the visual subtree when language changes; keep the RTC carrier alive.
      ForEach([this.state.languagePreference], (language: string) => {
      Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        if (this.pageWidth >= 840 && this.state.connected) this.drawer(true)
        Column() {
        this.header()
      if (this.state.error || this.state.notice) {
        Text(this.state.error || this.state.notice).fontSize(13).fontColor(this.state.error ? '#C64B43' : '#9D6B20')
          .width('100%').padding(12).backgroundColor($r('sys.color.comp_background_tertiary'))
      }
      if (this.state.busy) { Progress({ value: 35, total: 100, type: ProgressType.Linear }).width('100%').color('#4B78E6') }
        if (this.state.view === 'login') { this.login() }
        else if (this.state.view === 'trust') { this.trust() }
        else if (this.state.view === 'chat') { this.chat() }
        else if (this.state.view === 'botHome') { this.botSheet() }
        else { this.catalog() }
        }.layoutWeight(1).height('100%').backgroundColor($r('sys.color.background_primary'))
      }.width('100%').height('100%')
      if (this.showHostSwitcher) {
        this.scrim()
        Column({ space: 12 }) {
          Row() {
            Text(runtime.translate('切换主机')).fontSize(19).layoutWeight(1)
            Button(runtime.translate('关闭')).onClick(() => { this.showHostSwitcher = false })
          }.width('100%')
          List({ space: 8 }) {
            ForEach(this.state.devices, (device: DeviceRow) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(device.name).fontSize(16).width('100%')
                  Text(device.description).fontSize(12).width('100%')
                }.padding(12).width('100%')
              }.onClick(() => { this.showHostSwitcher = false; this.send('connect', { id: device.id }) })
            }, (device: DeviceRow) => device.id + device.description)
          }.height(320).width('100%')
          Button(runtime.translate('管理远程主机')).onClick(() => { this.showHostSwitcher = false; this.send('manageHosts', {}) })
          Button(runtime.translate('设置')).onClick(() => { this.showHostSwitcher = false; this.showSettings = true })
        }.padding(20).width('100%').backgroundColor($r('sys.color.background_primary')).borderRadius({ topLeft: 24, topRight: 24 })
      }
      if (this.pageWidth < 840 && this.drawerOpen && this.state.connected) { this.drawer() }
      if (this.alignmentPanel.length > 0 || this.showMore || this.showPromptForm || this.showPrompts || this.manageTarget !== undefined
        || this.showChildren || this.showInfo || this.showPlugins || this.showPluginForm
        || this.showTasks || this.showRecords || this.showSettings || this.showTerminal || this.showBots || this.showNetwork) {
        this.scrim()
        if (this.alignmentPanel.length > 0) {
          AlignmentPanel({ state: this.state, mode: this.alignmentPanel, availableHeight: Math.max(180, this.pageHeight - 140),
            onClose: () => { this.alignmentPanel = '' }, onPath: (path: string) => { this.directory = path } })
        } else if (this.showTerminal) { this.terminalSheet() }
        else if (this.showMore) { this.morePanel() }
        else if (this.showPrompts) { this.promptsPanel() }
        else if (this.showPromptForm) { this.promptForm() }
        else if (this.showChildren) { this.childrenSheet() }
        else if (this.showInfo) { this.infoSheet() }
        else if (this.showPluginForm) { this.pluginFormSheet() }
        else if (this.showPlugins) { this.pluginsSheet() }
        else if (this.showRecords) { this.recordsSheet() }
        else if (this.showTasks) { this.tasksSheet() }
        else if (this.showSettings) { this.settingsSheet() }
        else if (this.showBots) { this.botSheet() }
        else if (this.showNetwork) { this.networkSheet() }
        else if (this.manageTarget !== undefined) { this.manageSheet() }
      }
      }.width('100%').height('100%')
      }, (language: string) => language)
    }.width('100%').height('100%').onAreaChange((old: Area, area: Area) => { this.pageWidth = Number(area.width); this.pageHeight = Number(area.height) })
  }
}
