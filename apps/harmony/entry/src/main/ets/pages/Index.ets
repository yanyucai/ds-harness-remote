import { saveWorkspaceFile } from '../components/FileSave'
import photoAccessHelper from '@ohos.file.photoAccessHelper'
import cameraPicker from '@ohos.multimedia.cameraPicker'
import cameraKit from '@ohos.multimedia.camera'
import picker from '@ohos.file.picker'
import fileUri from '@ohos.file.fileuri'
import common from '@ohos.app.ability.common'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import window from '@ohos.window'
import promptAction from '@ohos.promptAction'
import { AlignmentPanel } from '../components/AlignmentPanel'
import { LocalSurface } from '../components/LocalSurface'
import { RtcSurface } from '../components/RtcSurface'
import { runtime } from '../RuntimeHost'
import { HarmonyThemeColors, harmonyTypeScale, HarmonyTypeScale, resolveHarmonyTheme } from '../theme/HarmonyTheme'
import { ViewState, TimelineRow, CatalogRow, DeviceRow, ModelRow, ModelEffort, UserQuestion, QuestionOption, QuestionAnswer, emptyState } from '../models/ViewState'
import { BotDefinition, ActivityRow, JobRow, BackendTab, OverviewRow, ActionInput, StagedFile, BotExtra, FailedSend, PresetRow, QueueRow, PromptRow } from '../models/ViewState'
import { SkillRow, FileRow, InfoRow, PluginRow, FormRow, TaskRow, RecordRow, TerminalRow, UiArtifactRow, BotReplyRow, BotEntryRow, NetworkRow, NetworkSection } from '../models/ViewState'

interface PromptAttachment { data: string; mediaType: string; name?: string }
interface BotPending { id: string }
interface SurfaceEvent { type?: string; url?: string; text?: string; data?: string; cols?: number; rows?: number }
interface ChatAppearanceValue { fontScale?: string; spacingScale?: string; letterSpacing?: string; accent?: string; bubbleStyle?: string; codeTheme?: string }
interface PrefOption { id: string; name: string }
interface AccentPresetView { id: string; name: string; color: string }

@Component
struct QuestionForm {
  @Prop questions: UserQuestion[] = []
  @Prop dark: boolean = false
  @Prop accent: string = 'deepseek'
  @Prop density: string = 'compact'
  onSubmit: (answers: QuestionAnswer[]) => void = () => {}
  @State selected: string[][] = []
  @State custom: string[] = []

  private theme(): HarmonyThemeColors {
    return resolveHarmonyTheme(this.dark, this.accent)
  }
  private type(): HarmonyTypeScale {
    return harmonyTypeScale(this.density)
  }
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
        Text(question.question).fontSize(this.type().bodySize).lineHeight(this.type().bodyLineHeight).fontWeight(FontWeight.Medium)
          .fontColor(this.theme().ink).width('100%')
        if (question.detail) {
          Text(question.detail).fontSize(this.type().smallSize).lineHeight(this.type().smallLineHeight)
            .fontColor(this.theme().muted).width('100%')
        }
        ForEach(question.options || [], (option: QuestionOption) => {
          Button((this.selected[index]?.includes(option.label) ? '✓ ' : '') + option.label)
            .fontSize(this.type().smallSize).height(48).width('100%')
            .backgroundColor(this.selected[index]?.includes(option.label) ? this.theme().primarySoft : this.theme().background)
            .fontColor(this.selected[index]?.includes(option.label) ? this.theme().primary : this.theme().ink)
            .border({ width: 1, color: this.selected[index]?.includes(option.label) ? this.theme().primary : this.theme().border })
            .borderRadius(12)
            .onClick(() => {
              this.selected = this.selected.map((values: string[], row: number): string[] => {
                if (row !== index) return values
                if (values.includes(option.label)) return values.filter((value: string) => value !== option.label)
                return question.multiSelect ? values.concat([option.label]) : [option.label]
              })
            })
        })
        TextInput({ text: this.custom[index] || '', placeholder: runtime.translate('补充回答（可选）') })
          .height(48).fontSize(this.type().bodySize).fontColor(this.theme().ink).placeholderColor(this.theme().muted)
          .backgroundColor(this.theme().surface).border({ width: 1, color: this.theme().border }).borderRadius(16)
          .onChange((value: string) => { this.custom = this.custom.map((old: string, row: number) => row === index ? value : old) })
      })
      Button(runtime.translate('提交回答')).height(50).fontSize(this.type().bodySize).fontWeight(FontWeight.Medium)
        .backgroundColor(this.theme().primary).fontColor(this.theme().onPrimary).borderRadius(999)
        .onClick(() => { this.onSubmit(this.answers()) })
    }.width('100%')
  }
}

@Component
struct TimelineCard {
  @Prop scope: string = ''
  @Prop dark: boolean = false
  @State imagePreview: string = ''
  @Prop row: TimelineRow
  @Prop accent: string = '#4D6BFE'
  @Prop appearance: string = '{}'
  @Prop density: string = 'compact'
  onApproval: (id: string, decision: string) => void = () => {}
  onQuestion: (id: string, answers: QuestionAnswer[]) => void = () => {}
  onFork: (id: string) => void = () => {}
  onFeedback: (id: string, rating: string) => void = () => {}
  @State expanded: boolean = false

  private theme(): HarmonyThemeColors {
    let accent: string = 'deepseek'
    try {
      const value: ChatAppearanceValue = JSON.parse(this.appearance) as ChatAppearanceValue
      accent = value.accent ?? 'deepseek'
    } catch {}
    return resolveHarmonyTheme(this.dark, accent)
  }
  private type(): HarmonyTypeScale {
    return harmonyTypeScale(this.density)
  }
  private bubbleColor(): ResourceColor {
    if (this.row.title !== '你') return Color.Transparent
    const value: ChatAppearanceValue = JSON.parse(this.appearance) as ChatAppearanceValue
    if (value.bubbleStyle === 'minimal') return Color.Transparent
    if (value.bubbleStyle === 'tinted') return this.theme().primarySoft
    if (value.bubbleStyle === 'solid') return this.theme().primary
    return this.theme().userBubble
  }
  private solidBubble(): boolean {
    const value: ChatAppearanceValue = JSON.parse(this.appearance) as ChatAppearanceValue
    return this.row.title === '你' && value.bubbleStyle === 'solid'
  }
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
    Column({ space: 6 }) {
      Text(this.row.title)
        .fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight).fontWeight(FontWeight.Medium)
        .fontColor(this.row.kind === 'approval' ? this.theme().warning : this.theme().muted)
        .width('100%')
      if (this.row.turnStatus) {
        Text(runtime.translate(this.row.turnStatus === 'failed' ? '回复失败' : this.row.turnStatus === 'stopped' ? '已停止' : '已完成'))
          .fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight).width('100%')
          .fontColor(this.row.turnStatus === 'failed' ? this.theme().danger : this.theme().muted)
      }
      if (this.row.text) {
        LocalSurface({ scope: this.scope, dark: this.dark, payload: JSON.stringify({ text: this.row.text, dark: this.dark || this.solidBubble(), density: this.density, appearance: JSON.parse(this.appearance), copyLabel: runtime.translate('复制') }),
          onAction: async (raw: string): Promise<boolean> => {
            const value: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
            return runtime.perform('openLink', JSON.stringify({ text: value.url }))
          } })
      }
      if (this.row.turnDetail && this.row.turnDetail !== this.row.text) {
        Text(this.row.turnDetail).fontSize(this.type().smallSize).lineHeight(this.type().smallLineHeight)
          .width('100%').copyOption(CopyOptions.LocalDevice)
          .fontColor(this.row.turnStatus === 'failed' ? this.theme().danger : this.theme().muted)
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
        Text(runtime.translate(this.expanded ? '收起详情 ∧' : '查看思考 / 详情 ∨')).fontSize(this.type().smallSize)
          .lineHeight(this.type().smallLineHeight).fontColor(this.theme().primary).width('100%')
          .onClick(() => { this.expanded = !this.expanded })
        if (this.expanded) {
          Text(this.row.detail).fontSize(this.fs(13)).lineHeight(this.fs(20)).fontColor(this.theme().muted)
            .copyOption(CopyOptions.LocalDevice).width('100%')
        }
      }
      if (this.row.actionable) {
        Row({ space: 10 }) {
          Button(runtime.translate('引用')).fontSize(this.type().captionSize).height(32).backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { runtime.perform('quote', JSON.stringify({ id: this.row.id })).catch(() => {}) })
          Button(runtime.translate('复制')).fontSize(this.type().captionSize).height(32).backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { runtime.perform('copyMessage', JSON.stringify({ id: this.row.id })).catch(() => {}) })
          Button(runtime.translate('分享')).fontSize(this.type().captionSize).height(32).backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { runtime.perform('shareMessage', JSON.stringify({ id: this.row.id })).catch(() => {}) })
          Button(runtime.translate('分支')).fontSize(this.type().captionSize).height(32).backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { this.onFork(this.row.id) })
          Button(runtime.translate(this.row.feedback === 'positive' ? '已赞' : '赞')).fontSize(11).height(30)
            .backgroundColor(this.row.feedback === 'positive' ? this.theme().primarySoft : Color.Transparent)
            .fontColor(this.row.feedback === 'positive' ? this.theme().primary : this.theme().muted)
            .onClick(() => { this.onFeedback(this.row.id, 'positive') })
          Button(runtime.translate(this.row.feedback === 'negative' ? '已踩' : '踩')).fontSize(11).height(30)
            .backgroundColor(this.row.feedback === 'negative' ? this.theme().dangerSoft : Color.Transparent)
            .fontColor(this.row.feedback === 'negative' ? this.theme().danger : this.theme().muted)
            .onClick(() => { this.onFeedback(this.row.id, 'negative') })
          Blank()
          Text(this.row.tokens).fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight).fontColor(this.theme().muted)
            .accessibilityText(runtime.translate('本轮用量') + ' ' + this.row.tokens)
            .onClick(() => { if (this.row.usageDetail) promptAction.showDialog({ title: runtime.translate('本轮用量'), message: this.row.usageDetail, buttons: [{ text: runtime.translate('关闭'), color: this.theme().primary }] }) })
          Text(this.row.clock).fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight).fontColor(this.theme().muted)
        }.width('100%').alignItems(VerticalAlign.Center)
      } else if (this.row.clock.length > 0) {
        Text(this.row.clock).fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight)
          .fontColor(this.theme().muted).width('100%')
          .textAlign(this.row.title === '你' ? TextAlign.End : TextAlign.Start)
      }
      if (this.row.kind === 'question' && this.row.pending) {
        QuestionForm({
          questions: this.row.questions || [],
          dark: this.dark,
          accent: ((JSON.parse(this.appearance) as ChatAppearanceValue).accent ?? 'deepseek'),
          density: this.density,
          onSubmit: (answers: QuestionAnswer[]) => { this.onQuestion(this.row.id, answers) },
        })
      }
      if (this.row.uiArtifacts && this.row.uiArtifacts.length > 0) {
        ForEach(this.row.uiArtifacts, (ui: UiArtifactRow) => {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('🎛').fontSize(16)
              Text(ui.title).fontSize(this.type().smallSize).lineHeight(this.type().smallLineHeight)
                .fontWeight(FontWeight.Bold).fontColor(this.theme().ink).layoutWeight(1)
              Text(`v${ui.version}`).fontSize(this.type().captionSize).fontColor(this.theme().primary)
                .backgroundColor(this.theme().primarySoft).padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(4)
            }.width('100%')

            if (ui.summary.length > 0) {
              Text(ui.summary).fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight)
                .fontColor(this.theme().muted).width('100%')
            }

            LocalSurface({ kind: 'intelligent', payload: ui.payload,
              onAction: async (raw: string): Promise<boolean> => {
                const message: SurfaceEvent = JSON.parse(raw) as SurfaceEvent
                return runtime.perform('uiAction', JSON.stringify({ id: ui.uiId, name: String(ui.version), mode: this.scope, text: message.text }))
              } })
            if (false) {
              Row() {
                Blank()
                Button(runtime.translate('执行操作')).fontSize(12).height(30).backgroundColor(this.theme().primary)
                  .onClick(() => {
                    promptAction.showDialog({
                      title: '发送 UI 操作？',
                      message: `确定要向会话发送以下操作吗？\n\n${ui.actionText}`,
                      buttons: [
                        { text: '取消', color: this.theme().muted },
                        { text: '发送', color: this.theme().primary }
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
          .width('100%').padding(12).borderRadius(16)
          .backgroundColor(this.theme().toolSurface)
          .margin({ top: 4, bottom: 4 })
        }, (ui: UiArtifactRow) => `ui|${ui.uiId}|${ui.version}`)
      }
      if (this.row.updatedArtifacts && this.row.updatedArtifacts.length > 0) {
        ForEach(this.row.updatedArtifacts, (hint: string) => {
          Text(hint).fontSize(this.type().captionSize).fontColor(this.theme().muted).margin({ top: 4 })
        }, (hint: string) => hint)
      }
      if (this.row.botReplies && this.row.botReplies.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.row.botReplies, (reply: BotReplyRow) => {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text(reply.name).fontSize(this.type().captionSize).fontWeight(FontWeight.Bold)
                  .fontColor(reply.color.length > 0 ? reply.color : this.theme().primary)
                if (reply.kind.length > 0 && reply.kind !== 'user') {
                  Text(reply.kind).fontSize(this.type().captionSize).fontColor(this.theme().muted)
                    .backgroundColor(this.theme().surfaceStrong)
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 }).borderRadius(4)
                }
              }.width('100%')
              Text(reply.text).fontSize(this.fs(14)).lineHeight(this.fs(20))
                .fontColor(this.theme().ink).copyOption(CopyOptions.LocalDevice).width('100%')
            }
            .width('100%').padding(10).borderRadius(12)
            .backgroundColor(this.theme().toolSurface)
          }, (reply: BotReplyRow, index: number) => `botReply|${index}|${reply.name}|${reply.text.length}`)
        }.width('100%').margin({ top: 4, bottom: 4 })
      }
      if (this.row.kind === 'approval' && this.row.pending) {
        Row({ space: 12 }) {
          Button(runtime.translate('拒绝')).type(ButtonType.Normal).borderRadius(999)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink)
            .onClick(() => { this.onApproval(this.row.id, 'deny') })
          Button(runtime.translate('允许一次')).type(ButtonType.Normal).borderRadius(999)
            .backgroundColor(this.theme().primary).fontColor(this.theme().onPrimary)
            .onClick(() => { this.onApproval(this.row.id, 'allow_once') })
        }
        .width('100%').justifyContent(FlexAlign.End)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.row.title === '你' ? '86%' : '100%')
    .padding({
      left: this.row.title === '你' ? 14 : 0,
      right: this.row.title === '你' ? 14 : 0,
      top: this.row.title === '你' ? 10 : 0,
      bottom: this.row.title === '你' ? 10 : 0,
    })
    .borderRadius(this.row.title === '你' ? { topLeft: 18, topRight: 6, bottomLeft: 18, bottomRight: 18 } : 0)
    .backgroundColor(this.bubbleColor())
  }
}

@Component
struct TraceEntry {
  @Prop row: TimelineRow
  @Prop dark: boolean = false
  @Prop accent: string = 'deepseek'
  @Prop appearance: string = '{}'
  @Prop density: string = 'compact'
  label: string = ''
  onFork: (id: string) => void = () => {}
  onFeedback: (id: string, rating: string) => void = () => {}
  @State expanded: boolean = false

  private theme(): HarmonyThemeColors {
    return resolveHarmonyTheme(this.dark, this.accent)
  }
  private type(): HarmonyTypeScale {
    return harmonyTypeScale(this.density)
  }
  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.label).fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight)
          .fontColor(this.theme().muted)
        Text(runtime.translate(this.row.turn.length > 0 ? `轮次 ${this.row.turn}` : '')).fontSize(this.type().captionSize)
          .lineHeight(this.type().captionLineHeight).fontColor(this.theme().muted).maxLines(1)
        Blank()
        Text(this.row.clock).fontSize(this.type().captionSize).lineHeight(this.type().captionLineHeight)
          .fontColor(this.theme().muted)
        Text(this.expanded ? '⌄' : '›').fontSize(14).fontColor(this.theme().muted)
      }.width('100%')
      if (this.expanded) {
        TimelineCard({
          row: this.row, dark: this.dark, accent: this.accent, appearance: this.appearance, density: this.density,
          onFork: this.onFork, onFeedback: this.onFeedback,
        })
      } else {
        Text(this.row.preview).fontSize(this.type().smallSize).lineHeight(this.type().smallLineHeight)
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.theme().ink).width('100%')
        if (this.row.attachments > 0) {
          Text(runtime.translate(`${this.row.attachments} 张图片`)).fontSize(this.type().captionSize)
            .lineHeight(this.type().captionLineHeight).fontColor(this.theme().muted)
        }
      }
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 }).borderRadius(16)
      .backgroundColor(this.theme().card).border({ width: 1, color: this.theme().separator })
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
  @State bottomSafeHeight: number = 0
  @State showHostSwitcher: boolean = false
  @State showSettings: boolean = false
  @State settingsPage: string = ''
  @State homeBackendOpen: boolean = false
  @State showWorkspaceCreator: boolean = false
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

  private darkMode(): boolean {
    return (getContext(this) as common.UIAbilityContext).config.colorMode === 0
  }
  private accentPreset(): string {
    try {
      return (JSON.parse(this.state.chatAppearance) as ChatAppearanceValue).accent ?? 'deepseek'
    } catch {
      return 'deepseek'
    }
  }
  private theme(): HarmonyThemeColors {
    return resolveHarmonyTheme(this.darkMode(), this.accentPreset())
  }
  private typography(): HarmonyTypeScale {
    return harmonyTypeScale(this.state.typographyDensity)
  }
  private accentColor(): string {
    return this.theme().primary
  }
  private homeMode(): string {
    return this.state.view === 'botHome' ? 'bot' : 'agent'
  }
  private homeBackendName(): string {
    const current: BackendTab | undefined = this.state.backends.find((row: BackendTab) => row.id === this.state.backend)
    return current?.name ?? this.state.backend
  }
  private languageLabel(): string {
    if (this.state.languagePreference === 'zh-CN') return runtime.translate('简体中文')
    if (this.state.languagePreference === 'en-US') return 'English'
    if (this.state.languagePreference === 'zh-TW') return runtime.translate('繁體中文')
    if (this.state.languagePreference === 'ja-JP') return '日本語'
    if (this.state.languagePreference === 'es-ES') return 'Español'
    if (this.state.languagePreference === 'de-DE') return 'Deutsch'
    if (this.state.languagePreference === 'fr-FR') return 'Français'
    return runtime.translate('跟随系统')
  }
  private activityDockLabel(): string {
    if (this.state.activityDockMode === 'cards') return runtime.translate('卡片')
    if (this.state.activityDockMode === 'hidden') return runtime.translate('隐藏')
    return runtime.translate('紧凑')
  }
  private densityLabel(): string {
    return runtime.translate(this.state.typographyDensity === 'standard' ? '标准' : '紧凑')
  }
  private chatAppearanceLabel(): string {
    const font: string = this.appearanceValue('fontScale')
    const bubble: string = this.appearanceValue('bubbleStyle')
    const fontLabel: string = font === 'sm' ? '小' : font === 'lg' ? '大' : font === 'xl' ? '特大' : '标准'
    const bubbleLabel: string = bubble === 'tinted' ? '浅色' : bubble === 'solid' ? '纯色' : bubble === 'minimal' ? '极简' : '柔和'
    return `${runtime.translate(fontLabel)} · ${runtime.translate(bubbleLabel)}`
  }
  private defaultPermissionLabel(): string {
    if (this.state.defaultPermission === 'workspace-write') return runtime.translate('工作区读写')
    if (this.state.defaultPermission === 'danger-full-access') return runtime.translate('完全权限')
    return runtime.translate('默认')
  }
  private accentItems(): AccentPresetView[] {
    return [
      { id: 'deepseek', name: '蓝', color: this.darkMode() ? '#6F89FF' : '#4D6BFE' },
      { id: 'emerald', name: '绿', color: this.darkMode() ? '#2DD4BF' : '#0D9488' },
      { id: 'violet', name: '紫', color: this.darkMode() ? '#A78BFA' : '#7C5CFC' },
      { id: 'amber', name: '琥珀', color: this.darkMode() ? '#F59E0B' : '#D97706' },
      { id: 'graphite', name: '石墨', color: this.darkMode() ? '#E4E4E7' : '#27272A' },
    ]
  }

  aboutToAppear(): void {
    const initial: ViewState = emptyState()
    initial.accentColor = this.theme().primary
    this.state = initial
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
      try {
        const appearance: ChatAppearanceValue = JSON.parse(next.chatAppearance) as ChatAppearanceValue
        next.accentColor = resolveHarmonyTheme(this.darkMode(), appearance.accent ?? 'deepseek').primary
      } catch {
        next.accentColor = resolveHarmonyTheme(this.darkMode()).primary
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
    this.refreshBottomSafeArea()
  }

  private async refreshBottomSafeArea(): Promise<void> {
    try {
      const target = await window.getLastWindow(getContext(this) as common.UIAbilityContext)
      const area = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      this.bottomSafeHeight = area.visible ? Math.max(0, px2vp(area.bottomRect.height)) : 0
    } catch {}
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
    if (this.showSettings && this.settingsPage.length > 0) { this.settingsPage = ''; return true }
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
    this.showSettings = false; this.settingsPage = ''
    this.showBots = false
    this.showNetwork = false
    this.showTerminal = false
    this.terminalInput = ''
    this.homeBackendOpen = false
    this.showWorkspaceCreator = false
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
        Button('‹').fontSize(22).width(38).height(38).padding(0)
          .backgroundColor(this.theme().elevated).borderRadius(999)
          .border({ width: 1, color: this.theme().separator })
          .fontColor(this.theme().muted).onClick(() => { this.panelPage = '' })
      }
      Text(runtime.translate(title)).fontSize(this.typography().headingSize).lineHeight(this.typography().headingLineHeight)
        .fontWeight(FontWeight.Bold).fontColor(this.theme().ink).layoutWeight(1)
      Button('✕').fontSize(17).width(38).height(38).padding(0)
        .backgroundColor(this.theme().elevated).borderRadius(999)
        .border({ width: 1, color: this.theme().separator }).fontColor(this.theme().muted)
        .onClick(() => { this.closePanels() })
    }.width('100%').constraintSize({ minHeight: 44 })
  }
  @Builder
  optionRow(icon: string, label: string, value: string, page: string) {
    Row({ space: 12 }) {
      Text(icon).fontSize(17).width(24).textAlign(TextAlign.Center).fontColor(this.state.accentColor)
      Text(label).fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
        .fontColor(this.theme().ink).layoutWeight(1)
      Text(value).fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight)
        .fontColor(this.theme().muted).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 150 })
      Text('›').fontSize(17).fontColor(this.theme().muted)
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
      Text(empty).fontSize(13).fontColor(this.theme().muted).padding(20).width('100%')
    } else {
      List({ space: 2 }) {
        ForEach(items, (item: PresetRow) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(item.name).fontSize(15).width('100%')
                  .fontWeight(item.current ? FontWeight.Bold : FontWeight.Normal)
                Text(item.description).fontSize(12).fontColor(this.theme().muted)
                  .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (item.current) { Text('✓').fontSize(17).fontColor(this.state.accentColor) }
            }.width('100%').padding({ top: 10, bottom: 10 })
          }.enabled(!item.broken && !item.current && !this.state.busy)
            .onClick(() => { this.showMore = false; this.panelPage = ''; this.send(action, { id: item.id }) })
        }, (item: PresetRow) => `${item.id}|${item.current}|${item.broken}|${item.name}|${item.description}`)
      }.width('100%').constraintSize({ maxHeight: 330 })
    }
  }

  @Builder
  morePanel() {
    Scroll() {
      Column({ space: 10 }) {
      if (this.panelPage === '') {
        this.sheetTitle('更多操作', false)
        Row({ space: 8 }) {
          Button(runtime.translate('会话信息')).layoutWeight(1).height(40).fontSize(13)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(14)
            .onClick(() => { this.showMore = false; this.showInfo = true; this.invoke('sessionInfo') })
          Button(runtime.translate(this.traceMode ? '返回对话' : '查看轨迹')).layoutWeight(1).height(40).fontSize(13)
            .backgroundColor(this.traceMode ? this.theme().primarySoft : this.theme().surfaceStrong)
            .fontColor(this.traceMode ? this.accentColor() : this.theme().ink).borderRadius(14)
            .onClick(() => { this.showMore = false; this.traceMode = !this.traceMode; this.traceQuery = ''; this.traceCategory = 'all' })
        }.width('100%')
        Row({ space: 8 }) {
          Button(runtime.translate('切换主机')).layoutWeight(1).height(40).fontSize(13)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(14)
            .onClick(() => { this.showMore = false; this.showHostSwitcher = true; this.invoke('refresh') })
          Button(runtime.translate('断开连接')).layoutWeight(1).height(40).fontSize(13)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().danger).borderRadius(14)
            .onClick(() => { this.showMore = false; this.invoke('disconnect') })
        }.width('100%')
        Row({ space: 12 }) {
          Button(runtime.translate('拍照')).layoutWeight(1).height(56).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(!this.state.busy).onClick(() => { this.showMore = false; this.panelPage = ''; this.takePhoto() })
          Button(runtime.translate('相册')).layoutWeight(1).height(56).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(!this.state.busy).onClick(() => { this.showMore = false; this.panelPage = ''; this.pickImage() })
          Button(runtime.translate('视频')).layoutWeight(1).height(56).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.connected).onClick(() => { this.showMore = false; this.pickVideo() })
          Button(runtime.translate('文件')).layoutWeight(1).height(56).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(!this.state.busy).onClick(() => { this.showMore = false; this.panelPage = ''; this.pickDocument() })
        }.width('100%')
        if (this.state.panelWarning.length > 0) {
          Text(this.state.panelWarning).fontSize(12).fontColor(this.theme().warning).width('100%')
        }
        Divider().color(this.theme().surfaceStrong)
        this.optionRow('🗂', '工作区', this.workspaceValue(), 'workspace')
        this.optionRow('◈', '模式', this.modeValue(), 'mode')
        this.optionRow('⛨', '操作权限', this.permissionValue(), 'permission')
        this.optionRow('⌘', 'Slash 命令', `${this.state.skills.length} 个`, 'skills')
        this.optionRow('📄', '工作区文件', this.state.filePath, 'files')
        this.optionRow('💻', '终端', this.terminalValue(), 'terminal')
        this.optionRow('🤖', 'Bot 团队', this.state.bots.length > 0 ? `${this.state.bots.length} 个成员` : '查看', 'bots')
        this.optionRow('🌐', '网络与链路', this.networkStatusSummary(), 'network')
        Row({ space: 12 }) {
          Text('⏱').fontSize(17).width(24).textAlign(TextAlign.Center).fontColor(this.state.accentColor)
          Text(runtime.translate('紧凑历史')).fontSize(15).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.state.compactHistory })
            .selectedColor(this.state.accentColor).enabled(!this.state.busy)
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
          Text(runtime.translate('这台主机没有可用的 Slash 命令。')).fontSize(13).fontColor(this.theme().muted).padding(20).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.skills, (item: SkillRow) => {
              ListItem() {
                Column({ space: 3 }) {
                  Text(`/${item.name}`).fontSize(15).width('100%').fontFamily('monospace')
                  Text(item.description).fontSize(12).fontColor(this.theme().muted)
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
          .fontSize(12).fontColor(this.theme().muted).width('100%').fontFamily('monospace')
        if (this.state.files.length === 0) {
          Text(runtime.translate('正在加载目录，或该目录为空。')).fontSize(13).fontColor(this.theme().muted).padding(20).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.files, (item: FileRow) => {
              ListItem() {
                Row({ space: 10 }) {
                  Text(item.kind === 'directory' ? '📁' : '📄').fontSize(16).width(24).textAlign(TextAlign.Center)
                  Text(item.name).fontSize(15).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.size).fontSize(12).fontColor(this.theme().muted)
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
          Divider().color(this.theme().surfaceStrong)
          Row({ space: 8 }) {
            Text(this.state.filePreview.name).fontSize(14).layoutWeight(1).fontFamily('monospace').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(runtime.translate('只读')).fontSize(10).fontColor(this.state.accentColor).backgroundColor(this.theme().primarySoft)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(4)
            Button('✕').accessibilityText(runtime.translate('关闭')).fontSize(15).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
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
              Text(this.state.filePreview.error).fontSize(12).fontColor(this.theme().warning).width('100%')
              Button(runtime.translate('重试')).fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                .onClick(() => { this.send('readFile', { id: this.state.filePreview.path, offset: this.state.filePreview.offset } as ActionInput) })
            }.width('100%').padding(10).backgroundColor(this.theme().surfaceStrong).borderRadius(10)
          } else if (this.state.filePreview.kind === 'text') {
            Scroll() {
              Text(this.state.filePreview.text).fontSize(12).fontFamily('monospace').width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }.constraintSize({ maxHeight: 240 }).width('100%')
            Row() {
              Text(this.state.filePreview.eof
                ? `第 ${this.state.filePreview.offset}–${this.state.filePreview.offset + Math.max(0, this.state.filePreview.lines - 1)} 行（已到末尾）`
                : `第 ${this.state.filePreview.offset}–${this.state.filePreview.offset + Math.max(0, this.state.filePreview.lines - 1)} 行`)
                .fontSize(11).fontColor(this.theme().muted).layoutWeight(1)
              if (this.state.filePreview.offset > 1) {
                Button(runtime.translate('上一页')).fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                  .onClick(() => { this.send('readFile', { id: this.state.filePreview.path, offset: Math.max(1, this.state.filePreview.offset - 200) } as ActionInput) })
              }
              if (!this.state.filePreview.eof && this.state.filePreview.lines > 0) {
                Button(runtime.translate('下一页')).fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                  .onClick(() => { this.send('readFile', { id: this.state.filePreview.path, offset: this.state.filePreview.offset + this.state.filePreview.lines } as ActionInput) })
              }
            }.width('100%')
          } else if (this.state.filePreview.kind === 'image') {
            Scroll() {
              Image(`data:${this.state.filePreview.mimeType};base64,${this.state.filePreview.data}`)
                .objectFit(ImageFit.Contain).width('100%')
            }.constraintSize({ maxHeight: 260 }).width('100%')
            Text(runtime.translate('图片只读预览')).fontSize(11).fontColor(this.theme().muted).width('100%')
          } else if (this.state.filePreview.kind === 'pdf' || this.state.filePreview.kind === 'office') {
            LocalSurface({ kind: 'pdf', payload: JSON.stringify(this.state.filePreview.data) })
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text(this.state.filePreview.kind === 'office' ? '📑 Office 文档 (PDF 转码)' : '📕 PDF 文档')
                  .fontSize(13).fontWeight(FontWeight.Medium)
              }.width('100%')
              if (this.state.filePreview.missingFonts.length > 0) {
                Text(`缺少字体: ${this.state.filePreview.missingFonts.join(', ')}`)
                  .fontSize(11).fontColor(this.theme().warning).width('100%')
              }
              Text(this.state.filePreview.kind === 'office'
                ? '由主机 officeToPdf 引擎渲染为标准化 PDF 产物，完整保留版式结构与图文排版。'
                : '标准化 PDF 产物，已在移动端完成格式校验。')
                .fontSize(12).fontColor(this.theme().muted).width('100%')
            }.padding(12).backgroundColor(this.theme().surfaceStrong).borderRadius(12).width('100%')
          } else {
            Text(runtime.translate('此文件类型暂不支持在移动端直接预览，请在电脑端查看。'))
              .fontSize(12).fontColor(this.theme().muted).padding(12).width('100%')
          }
        }
      } else {
        this.sheetTitle('选择工作区', true)
        Text(runtime.translate('把当前对话移到所选工作区')).fontSize(12).fontColor(this.theme().muted).width('100%')
        if (this.state.workspaceOptions.length === 0) {
          Text(runtime.translate('还没有可用的工作区。请在电脑端添加项目目录。')).fontSize(13)
            .fontColor(this.theme().muted).padding(20).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.workspaceOptions, (item: CatalogRow) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(item.name).fontSize(15).width('100%')
                    Text(item.description).fontSize(12).fontColor(this.theme().muted)
                      .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text(`${item.count}`).fontSize(12).fontColor(this.theme().muted)
                }.width('100%').padding({ top: 10, bottom: 10 })
              }.enabled(!this.state.busy)
                .onClick(() => { this.showMore = false; this.panelPage = ''; this.send('moveSession', { id: item.id }) })
            // ArkUI reuses an item whenever its key is unchanged, so every rendered field belongs in the key.
            }, (item: CatalogRow) => `move|${item.id}|${item.name}|${item.description}|${item.count}|${item.favorite}`)
          }.width('100%').constraintSize({ maxHeight: 330 })
        }
        }
      }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 20 })
    }.width('100%').constraintSize({ maxHeight: Math.max(280, this.pageHeight - 100 - this.bottomSafeHeight) })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
      .scrollBar(BarState.Auto)
  }

  /** Android's title-bar 子任务 popover: child sessions only, tapping opens one. */
  @Builder
  childrenSheet() {
    Column({ space: 10 }) {
      this.sheetTitle(`子任务 ${this.state.children.length}`, false)
      if (this.state.children.length === 0) {
        Text(runtime.translate('这段对话没有子任务会话。')).fontSize(13).fontColor(this.theme().muted).padding(20).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.state.children, (item: CatalogRow) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(item.name).fontSize(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.description).fontSize(12).fontColor(item.description === '回复中' ? this.state.accentColor : this.theme().muted)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('›').fontSize(17).fontColor(this.theme().muted)
              }.width('100%').padding({ top: 10, bottom: 10 })
            }.enabled(!this.state.busy)
              .onClick(() => { this.showChildren = false; this.send('session', { id: item.id }) })
          }, (item: CatalogRow) => `child|${item.id}|${item.name}|${item.description}`)
        }.width('100%').constraintSize({ maxHeight: 330 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** Android's 对话信息 sheet: workspace, host, backend and directories. */
  @Builder
  infoSheet() {
    Column({ space: 10 }) {
      this.sheetTitle('对话与连接信息', false)
      Scroll() {
        Column({ space: 10 }) {
          Text(runtime.translate('会话与工作区')).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme().muted).width('100%')
          Column({ space: 2 }) {
            ForEach(this.state.info, (row: InfoRow) => {
              Column({ space: 2 }) {
                Text(row.label).fontSize(12).fontColor(this.theme().muted).width('100%')
                Text(row.value).fontSize(14).width('100%').copyOption(CopyOptions.LocalDevice)
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
            }, (row: InfoRow) => `info|${row.label}|${row.value}`)
          }.width('100%').padding(10).borderRadius(12).backgroundColor(this.theme().surfaceStrong)

          if (this.state.networkSections.length > 0) {
            ForEach(this.state.networkSections, (sec: NetworkSection) => {
              Text(sec.title).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.theme().muted).width('100%')
              Column({ space: 2 }) {
                ForEach(sec.rows, (row: NetworkRow) => {
                  Column({ space: 2 }) {
                    Text(row.label).fontSize(12).fontColor(this.theme().muted).width('100%')
                    Text(row.value).fontSize(14).width('100%')
                      .fontFamily(row.mono ? 'monospace' : 'sans-serif')
                      .copyOption(CopyOptions.LocalDevice)
                  }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
                }, (row: NetworkRow) => `net|${row.label}|${row.value}`)
              }.width('100%').padding(10).borderRadius(12).backgroundColor(this.theme().surfaceStrong)
            }, (sec: NetworkSection) => `sec|${sec.title}`)
          }
        }.width('100%')
      }.constraintSize({ maxHeight: 460 }).width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  @Builder
  badge(text: string) {
    Text(text).fontSize(10).fontColor(this.state.accentColor).borderRadius(8)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(this.theme().surfaceStrong)
  }

  /** Android's plugin manager: three sections, a switch per bundle and per component. */
  @Builder
  pluginsSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('插件')).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor(this.theme().muted).enabled(!this.state.busy)
          .onClick(() => { this.send('plugins', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate('启用和配置电脑上的插件')).fontSize(12).fontColor(this.theme().muted).width('100%')
      if (!this.state.settingsWritable) {
        Text(runtime.translate('Host 当前配置不可写入')).fontSize(12).fontColor(this.theme().warning).width('100%')
      }
      if (this.state.plugins.length === 0) {
        Text(runtime.translate(this.state.busy ? '正在加载插件…' : 'Host 上没有可管理的插件')).fontSize(13)
          .fontColor(this.theme().muted).padding(16).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.state.plugins, (row: PluginRow) => {
            ListItem() {
              if (row.level === 'section') {
                Column({ space: 2 }) {
                  Text(row.name).fontSize(13).fontWeight(FontWeight.Bold).width('100%')
                  if (row.description.length > 0) {
                    Text(row.description).fontSize(11).fontColor(this.theme().muted).width('100%')
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
                      Text(row.description).fontSize(12).fontColor(this.theme().muted).width('100%')
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (row.feature.length > 0) {
                      Text(row.feature).fontSize(11).fontColor(this.state.accentColor).width('100%')
                    }
                    if (this.pluginMeta(row).length > 0) {
                      Text(this.pluginMeta(row)).fontSize(11).width('100%').maxLines(2)
                        .fontColor(row.available ? this.theme().muted : this.theme().warning)
                    }
                    if (row.error.length > 0) {
                      Text(row.error).fontSize(11).fontColor(this.theme().danger).width('100%')
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (row.form.length > 0 && row.enabled) {
                    Button(runtime.translate('设置')).fontSize(12).height(32).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                      .enabled(!this.state.busy)
                      .onClick(() => { this.showPlugins = false; this.showPluginForm = true; this.send('pluginForm', { id: row.form }) })
                  }
                  Toggle({ type: ToggleType.Switch, isOn: row.enabled }).selectedColor(this.state.accentColor)
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
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** The schema-derived settings form of one plugin component. */
  @Builder
  pluginFormSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
          .fontColor(this.theme().muted)
          .onClick(() => { this.showPluginForm = false; this.openPlugins() })
        Text(this.state.formTitle).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate(this.state.settingsWritable ? '保存后立即生效，无需重启' : 'Host 当前配置不可写入'))
        .fontSize(12).fontColor(this.state.settingsWritable ? this.theme().muted : this.theme().warning).width('100%')
      if (this.state.form.length === 0) {
        Text(runtime.translate('该组件没有可配置项')).fontSize(13).fontColor(this.theme().muted).padding(16).width('100%')
      } else {
        Scroll() {
          Column({ space: 14 }) {
            ForEach(this.state.form, (row: FormRow, index: number) => {
              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(row.description).fontSize(14).width('100%')
                    Text(row.key).fontSize(11).fontFamily('monospace').width('100%')
                      .fontColor(this.theme().muted)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (row.kind === 'boolean') {
                    Toggle({ type: ToggleType.Switch, isOn: this.formFlags[index] === true }).selectedColor(this.state.accentColor)
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
                  Text(runtime.translate('此项请在电脑端修改')).fontSize(12).fontColor(this.theme().muted).width('100%')
                }
                if (row.bounds.length > 0) {
                  Text(row.bounds).fontSize(11).fontColor(this.theme().muted).width('100%')
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (row: FormRow) => `form|${row.key}|${row.kind}|${row.value}|${row.description}|${row.bounds}`)
          }.width('100%')
        }.constraintSize({ maxHeight: 380 }).width('100%')
        Row({ space: 10 }) {
          Button(runtime.translate('保存')).layoutWeight(1).backgroundColor(this.state.accentColor)
            .enabled(this.state.settingsWritable && !this.state.busy)
            .onClick(() => {
              runtime.perform('pluginSave', JSON.stringify({ text: this.formPayload() } as ActionInput)).catch(() => {})
            })
          if (this.state.formResettable) {
            Button(runtime.translate('恢复默认')).layoutWeight(1).backgroundColor(this.theme().surfaceStrong)
              .enabled(this.state.settingsWritable && !this.state.busy)
              .onClick(() => { runtime.perform('pluginReset', JSON.stringify({} as ActionInput)).catch(() => {}) })
          }
        }.width('100%')
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** Android's 自动化任务 list: status filter, rule summary, records and delete. */
  @Builder
  tasksSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('自动化任务')).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.taskFilterLabel()).fontSize(12).height(32).backgroundColor(Color.Transparent)
          .fontColor(this.state.accentColor).onClick(() => { this.taskFilter = this.nextTaskFilter() })
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor(this.theme().muted).enabled(!this.state.busy)
          .onClick(() => { this.send('tasks', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate('启用/停用与安卓版一致，仅改变本次客户端列表状态。')).fontSize(11).fontColor(this.theme().muted)
      Button(runtime.translate('新建 / 编辑任务')).onClick(() => { this.showTasks = false; this.alignmentPanel = 'tasks' })
      if (this.shownTasks().length === 0) {
        Text(this.state.busy ? '正在加载任务…'
          : (this.state.tasks.length === 0 ? '还没有自动化任务，在会话中创建的任务会显示在这里' : '没有匹配的自动化任务'))
          .fontSize(13).fontColor(this.theme().muted).padding(16).width('100%')
      } else {
        List({ space: 4 }) {
          ForEach(this.shownTasks(), (row: TaskRow) => {
            ListItem() {
              Column({ space: 5 }) {
                Row({ space: 8 }) {
                  Text(row.title).fontSize(15).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.status).fontSize(11)
                    .fontColor(row.active ? this.theme().success : this.theme().muted)
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(row.schedule).fontSize(12).fontColor(this.state.accentColor).width('100%')
                if (row.next.length > 0) {
                  Text(runtime.translate(`下次计划时间：${row.next}`)).fontSize(11).width('100%')
                    .fontColor(this.theme().muted)
                }
                if (row.last.length > 0) {
                  Text(runtime.translate(`上次触发：${row.last}`)).fontSize(11).width('100%')
                    .fontColor(this.theme().muted)
                }
                Text(row.prompt).fontSize(12).fontColor(this.theme().muted).width('100%')
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.confirmTask === row.id) {
                  Text(runtime.translate('任务将停止触发，并连同其已保存的运行记录一并删除。原会话及其消息仍然保留。'))
                    .fontSize(11).fontColor(this.theme().danger).width('100%')
                }
                Row({ space: 8 }) {
                  Blank()
                  Button(runtime.translate(row.active ? '停用' : '启用')).fontSize(12).onClick(() => { this.send('taskToggle', { id: row.id, name: row.session }) })
                  Button(runtime.translate('运行记录')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                    .enabled(!this.state.busy)
                    .onClick(() => {
                      this.showTasks = false; this.showRecords = true
                      this.send('taskHistory', { id: row.id, name: row.session })
                    })
                  if (this.confirmTask === row.id) {
                    Button(runtime.translate('确认删除')).fontSize(12).height(30).backgroundColor(this.theme().danger).fontColor(Color.White)
                      .enabled(!this.state.busy)
                      .onClick(() => {
                        this.confirmTask = ''
                        this.send('taskDelete', { id: row.id, name: row.session })
                      })
                    Button(runtime.translate('取消')).fontSize(12).height(30).backgroundColor(Color.Transparent)
                      .fontColor(this.theme().muted).onClick(() => { this.confirmTask = '' })
                  } else {
                    Button(runtime.translate('删除')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor(this.theme().danger)
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
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** One task's delivery records, newest first as the Host returns them. */
  @Builder
  recordsSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
          .fontColor(this.theme().muted).onClick(() => { this.showRecords = false; this.openTasks() })
        Text(this.state.recordsTitle).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Text(runtime.translate('任务运行记录')).fontSize(12).fontColor(this.theme().muted).width('100%')
      if (this.state.records.length === 0) {
        Text(runtime.translate(this.state.busy ? '正在加载任务…' : '暂无任务运行记录')).fontSize(13)
          .fontColor(this.theme().muted).padding(16).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.state.records, (row: RecordRow) => {
            ListItem() {
              Column({ space: 3 }) {
                Row({ space: 8 }) {
                  Text(row.delivered).fontSize(14).layoutWeight(1)
                  Text(runtime.translate(`计划 ${row.scheduled}`)).fontSize(11).fontColor(this.theme().muted)
                }.width('100%').alignItems(VerticalAlign.Center)
                if (row.prompt.length > 0) {
                  Text(row.prompt).fontSize(12).fontColor(this.theme().muted).width('100%')
                    .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 8 })
            }
          }, (row: RecordRow) => `record|${row.id}|${row.delivered}|${row.scheduled}|${row.prompt}`)
        }.width('100%').constraintSize({ maxHeight: 400 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  private appearanceValue(key: string): string {
    const value: ChatAppearanceValue = JSON.parse(this.state.chatAppearance) as ChatAppearanceValue
    if (key === 'fontScale') return value.fontScale ?? 'md'
    if (key === 'spacingScale') return value.spacingScale ?? 'balanced'
    if (key === 'letterSpacing') return value.letterSpacing ?? 'normal'
    if (key === 'accent') return value.accent ?? 'deepseek'
    if (key === 'bubbleStyle') return value.bubbleStyle ?? 'soft'
    return value.codeTheme ?? 'auto'
  }
  @Builder
  appearanceRow(label: string, key: string, values: string[], names: string[]) {
    Column({ space: 6 }) {
      Text(runtime.translate(label)).fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight)
        .fontColor(this.theme().ink).width('100%')
      Scroll() {
        Row({ space: 8 }) {
          ForEach(values, (value: string, index: number) => {
            Button(runtime.translate(names[index])).fontSize(12).height(36).padding({ left: 14, right: 14 })
              .backgroundColor(this.appearanceValue(key) === value ? this.state.accentColor : this.theme().surfaceStrong)
              .fontColor(this.appearanceValue(key) === value ? this.theme().onPrimary : this.theme().ink)
              .borderRadius(999)
              .onClick(() => { this.send('setChatAppearance', { name: key, text: value }) })
          })
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%')
    }.width('100%')
  }

  /** Android's 设置 sheet: language, appearance, typography density, compact history. */
  @Builder
  legacySettingsSheet() {
    Column({ space: 14 }) {
      this.sheetTitle('设置', false)
      Scroll() {
        Column({ space: 14 }) {
          Text(runtime.translate('聊天外观')).fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
            .fontWeight(FontWeight.Bold).fontColor(this.theme().ink).width('100%')
          this.appearanceRow('字号', 'fontScale', ['sm','md','lg','xl'], ['小','标准','大','特大'])
          this.appearanceRow('行距', 'spacingScale', ['tight','balanced','relaxed'], ['紧凑','均衡','宽松'])
          this.appearanceRow('字距', 'letterSpacing', ['normal','wide','wider'], ['标准','宽','更宽'])
          this.appearanceRow('主题色', 'accent', ['deepseek','emerald','violet','amber','graphite'], ['蓝','绿','紫','琥珀','石墨'])
          this.appearanceRow('气泡', 'bubbleStyle', ['soft','tinted','solid','minimal'], ['柔和','浅色','纯色','极简'])
          this.appearanceRow('代码配色', 'codeTheme', ['auto','dark','light'], ['跟随主题','深色','浅色'])
          Button(runtime.translate('恢复默认外观')).height(44).fontSize(this.typography().smallSize)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { this.send('resetChatAppearance', {}) })
          Text(runtime.translate('活动显示')).fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight)
            .fontColor(this.theme().ink).width('100%')
          Row({space:8}) {
            ForEach(['compact','cards','hidden'], (mode: string) => {
              Button(runtime.translate(mode === 'compact' ? '紧凑' : mode === 'cards' ? '卡片' : '隐藏'))
                .fontSize(12).height(36).padding({ left: 14, right: 14 })
                .backgroundColor(this.state.activityDockMode === mode ? this.state.accentColor : this.theme().surfaceStrong)
                .fontColor(this.state.activityDockMode === mode ? this.theme().onPrimary : this.theme().ink).borderRadius(999)
                .onClick(() => { this.send('setActivityDockMode', {name: mode}) })
            })
          }
          Divider()
          // 语言
          Column({ space: 6 }) {
            Text(runtime.translate('语言')).fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight)
              .fontWeight(FontWeight.Bold).fontColor(this.theme().muted).width('100%')
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
                    Text(item.name).fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
                      .fontColor(this.theme().ink).layoutWeight(1)
                      .fontWeight(this.state.languagePreference === item.id ? FontWeight.Bold : FontWeight.Normal)
                    if (this.state.languagePreference === item.id) {
                      Text('✓').fontSize(16).fontColor(this.state.accentColor)
                    }
                  }.width('100%').padding({ top: 10, bottom: 10, left: 4, right: 4 })
                }.onClick(() => { this.send('setLanguage', { id: item.id, name: item.id }) })
              }, (item: PrefOption) => `lang|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          // 外观
          Column({ space: 8 }) {
            Text(runtime.translate('外观')).fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight)
              .fontWeight(FontWeight.Bold).fontColor(this.theme().muted).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'system', name: runtime.translate('跟随系统') },
                { id: 'light', name: runtime.translate('浅色') },
                { id: 'dark', name: runtime.translate('深色') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(38).fontSize(13).borderRadius(999)
                  .backgroundColor(this.state.themePreference === item.id ? this.state.accentColor : this.theme().surfaceStrong)
                  .fontColor(this.state.themePreference === item.id ? this.theme().onPrimary : this.theme().ink)
                  .onClick(() => { this.send('setTheme', { id: item.id, name: item.id }) })
              }, (item: PrefOption) => `theme|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          // 排版密度
          Column({ space: 8 }) {
            Text(runtime.translate('排版密度')).fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight)
              .fontWeight(FontWeight.Bold).fontColor(this.theme().muted).width('100%')
            Text(runtime.translate('调整正文行距、段间距与气泡紧凑度')).fontSize(this.typography().captionSize)
              .lineHeight(this.typography().captionLineHeight).fontColor(this.theme().muted).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'standard', name: runtime.translate('标准') },
                { id: 'compact', name: runtime.translate('紧凑') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(38).fontSize(13).borderRadius(999)
                  .backgroundColor(this.state.typographyDensity === item.id ? this.state.accentColor : this.theme().surfaceStrong)
                  .fontColor(this.state.typographyDensity === item.id ? this.theme().onPrimary : this.theme().ink)
                  .onClick(() => { this.send('setDensity', { id: item.id, name: item.id }) })
              }, (item: PrefOption) => `density|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          // 紧凑历史
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('会话精简模式')).fontSize(this.typography().bodySize)
                .lineHeight(this.typography().bodyLineHeight).fontColor(this.theme().ink).width('100%')
              Text(runtime.translate('缩减历史工具详情，保留正文和状态')).fontSize(this.typography().captionSize)
                .lineHeight(this.typography().captionLineHeight).fontColor(this.theme().muted).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.state.compactHistory })
              .selectedColor(this.state.accentColor).enabled(!this.state.busy)
              .onChange((on: boolean) => { if (on !== this.state.compactHistory) { this.send('compactHistory', {}) } })
          }.width('100%').height(52).padding({ left: 2, right: 2 })

          Divider().color(this.theme().surfaceStrong)

          Row({ space: 12 }) {
            Text(runtime.translate('启动自动连接主机')).fontSize(this.typography().bodySize)
              .lineHeight(this.typography().bodyLineHeight).fontColor(this.theme().ink).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.state.autoConnectHost }).onChange((on: boolean) => { this.send('setAutoConnectHost', { enabled: on }) })
          }.width('100%')
          // 通知
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('启动恢复上次对话')).fontSize(this.typography().bodySize)
                .lineHeight(this.typography().bodyLineHeight).width('100%')
              Text(runtime.translate('自动连接后返回上次打开的对话，默认关闭'))
                .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
                .fontColor(this.theme().muted).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.state.resumeSessionEnabled })
              .selectedColor(this.state.accentColor).enabled(!this.state.busy)
              .onChange((on: boolean) => { if (on !== this.state.resumeSessionEnabled) this.send('setResumeSession', { enabled: on }) })
          }.width('100%').padding({ top: 4, bottom: 4 })
          Text(runtime.translate('阅读位置会自动保存；重新打开时回到已加载历史中的相应消息')).fontSize(11)
            .fontColor(this.theme().muted).width('100%')

          Divider().color(this.theme().surfaceStrong)

          Column({ space: 8 }) {
            Text(runtime.translate('通知')).fontSize(this.typography().smallSize)
              .lineHeight(this.typography().smallLineHeight).fontWeight(FontWeight.Bold).width('100%')
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(runtime.translate('任务和待确认提醒')).fontSize(this.typography().bodySize)
                  .lineHeight(this.typography().bodyLineHeight).width('100%')
                Text(runtime.translate('在应用处于后台时，接收任务完成与审批提示'))
                  .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
                  .fontColor(this.theme().muted).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.state.notificationsEnabled })
                .selectedColor(this.state.accentColor)
                .onChange((on: boolean) => {
                  if (on !== this.state.notificationsEnabled) {
                    this.send('setNotifications', { name: on ? 'true' : 'false' })
                  }
                })
            }.width('100%').padding({ top: 4, bottom: 4 })
            Button(runtime.translate('开启系统通知权限')).fontSize(this.typography().smallSize)
              .height(36).backgroundColor(this.theme().surfaceStrong)
              .fontColor(this.state.accentColor).width('100%')
              .onClick(() => { this.send('requestNotificationPermission', {}) })
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          // 传输与直连策略
          Column({ space: 8 }) {
            Text(runtime.translate('传输与直连策略')).fontSize(this.typography().smallSize)
              .lineHeight(this.typography().smallLineHeight).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('优先尝试局域网与 P2P 直连，遇到网络限制自动回退中继'))
              .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
              .fontColor(this.theme().muted).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'auto', name: runtime.translate('自动优选') },
                { id: 'turn', name: runtime.translate('仅穿透中继') },
                { id: 'relay', name: runtime.translate('仅控制转发') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(36).fontSize(this.typography().smallSize)
                  .backgroundColor(this.state.transportPreference === item.id ? this.state.accentColor : this.theme().surfaceStrong)
                  .fontColor(this.state.transportPreference === item.id ? this.theme().onPrimary : this.theme().ink)
                  .onClick(() => { this.send('setTransportPreference', { mode: item.id }) })
              }, (item: PrefOption) => `trans|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          // 新对话默认权限
          Column({ space: 8 }) {
            Text(runtime.translate('新对话默认权限')).fontSize(this.typography().smallSize)
              .lineHeight(this.typography().smallLineHeight).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('仅影响新建的 DSH / CodeX 对话，已有对话不变'))
              .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
              .fontColor(this.theme().muted).width('100%')
            Row({ space: 8 }) {
              ForEach([
                { id: 'default', name: runtime.translate('默认') },
                { id: 'workspace-write', name: runtime.translate('工作区读写') },
                { id: 'danger-full-access', name: runtime.translate('完全权限') },
              ], (item: PrefOption) => {
                Button(item.name).layoutWeight(1).height(36).fontSize(this.typography().captionSize)
                  .backgroundColor(this.state.defaultPermission === item.id ? this.state.accentColor : this.theme().surfaceStrong)
                  .fontColor(this.state.defaultPermission === item.id ? this.theme().onPrimary : this.theme().ink)
                  .onClick(() => {
                    if (item.id !== 'danger-full-access') { this.send('setDefaultPermission', { name: item.id }); return }
                    promptAction.showDialog({ title: runtime.translate('完全权限'), message: runtime.translate('新对话可以修改文件与执行命令，不再逐次询问。'), buttons: [{ text: runtime.translate('取消'), color: this.theme().muted }, { text: runtime.translate('确认'), color: this.state.accentColor }] }).then((result: promptAction.ShowDialogSuccessResponse) => { if (result.index === 1) this.send('setDefaultPermission', { name: item.id }) })
                  })
              }, (item: PrefOption) => `perm|${item.id}|${item.name}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          // 系统状态栏
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('系统状态栏')).fontSize(this.typography().bodySize).width('100%')
              Text(runtime.translate('在全屏与页面切换时保持系统状态栏可见'))
                .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
                .fontColor(this.theme().muted).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.state.statusBarVisible })
              .selectedColor(this.state.accentColor)
              .onChange((on: boolean) => { if (on !== this.state.statusBarVisible) this.send('setStatusBar', { enabled: on }) })
          }.width('100%').padding({ top: 4, bottom: 4 })

          Divider().color(this.theme().surfaceStrong)

          // 本地数据与缓存
          Column({ space: 8 }) {
            Text(runtime.translate('本地数据与缓存')).fontSize(this.typography().smallSize)
              .lineHeight(this.typography().smallLineHeight).fontWeight(FontWeight.Bold).width('100%')
            Text(runtime.translate('清除本机保存的草稿、收藏、历史浏览位置与连接缓存'))
              .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
              .fontColor(this.theme().muted).width('100%')
            Button(runtime.translate('清除本地记录与缓存')).fontSize(this.typography().smallSize)
              .height(36).backgroundColor(this.theme().surfaceStrong)
              .fontColor(this.theme().danger).width('100%')
              .onClick(() => { promptAction.showDialog({ title: runtime.translate('清除本地记录与缓存'), message: runtime.translate('清除本机保存的草稿、收藏、历史浏览位置与连接缓存'), buttons: [{ text: runtime.translate('取消'), color: this.theme().muted }, { text: runtime.translate('确认'), color: this.theme().danger }] }).then((result: promptAction.ShowDialogSuccessResponse) => { if (result.index === 1) this.send('clearBrowseData', {}) }) })
          }.width('100%').alignItems(HorizontalAlign.Start)

          Divider().color(this.theme().surfaceStrong)

          Text(runtime.translate('后台连接')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).fontWeight(FontWeight.Bold).width('100%')
          Text(runtime.translate(this.state.backgroundActive ? '后台持续任务已启用' : '后台持续任务未启用'))
            .fontSize(this.typography().smallSize).width('100%')
          if (this.state.backgroundError) Text(runtime.translate(this.state.backgroundError))
            .fontSize(this.typography().smallSize).fontColor(this.theme().danger).width('100%')
          Text(runtime.translate('系统省电策略可能暂停连接，可在应用设置中检查通知与后台权限'))
            .fontSize(this.typography().smallSize).lineHeight(this.typography().smallLineHeight).width('100%')
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
            Text(runtime.translate('当前版本')).fontSize(this.typography().smallSize)
              .fontColor(this.theme().muted).layoutWeight(1)
            Text(this.state.appVersion).fontSize(this.typography().smallSize).fontColor(this.theme().muted)
          }.width('100%').padding({ top: 4, bottom: 8 })
        }.width('100%')
      }.constraintSize({ maxHeight: 480 }).width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  @Builder
  settingsSection(title: string) {
    Text(runtime.translate(title)).fontSize(15).lineHeight(20)
      .fontColor(this.theme().muted).width('100%').padding({ left: 2 })
  }

  @Builder
  settingsDivider() {
    Divider().color(this.theme().separator).margin({ left: 56 })
  }

  @Builder
  settingsHeader(title: string) {
    Row({ space: 8 }) {
      Button('‹').accessibilityText(runtime.translate('返回')).fontSize(24).width(42).height(42).padding(0)
        .backgroundColor(this.theme().elevated).borderRadius(999).fontColor(this.theme().ink)
        .onClick(() => {
          if (this.settingsPage.length > 0) this.settingsPage = ''
          else this.closePanels()
        })
      Text(runtime.translate(title)).fontSize(20).lineHeight(26).fontWeight(FontWeight.Bold)
        .fontColor(this.theme().ink).textAlign(TextAlign.Center).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank().width(42)
    }.width('100%').height(52)
  }

  @Builder
  themePreviewTile(id: string, name: string) {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.Center }) {
        Row() {
          Column().width('50%').height('100%').backgroundColor(id === 'dark' ? '#161A21' : '#FFFFFF')
          Column().width('50%').height('100%').backgroundColor(id === 'system' ? '#161A21' : id === 'dark' ? '#161A21' : '#FFFFFF')
        }.width('100%').height('100%').clip(true).borderRadius(12)
        Column({ space: 5 }) {
          Row() { Text('').width('52%').height(4).backgroundColor(id === 'dark' ? '#7A8291' : '#B9B9BB').borderRadius(2) }
          Row() { Text('').width('34%').height(4).backgroundColor(id === 'dark' ? '#7A8291' : '#B9B9BB').borderRadius(2) }
          Blank()
          Row() { Blank(); Text('').width(12).height(12).backgroundColor(this.accentColor()).borderRadius(6) }
        }.width('100%').height('100%').padding(10)
      }.width('100%').height(62)
        .border({ width: 2, color: this.state.themePreference === id ? this.accentColor() : Color.Transparent })
        .borderRadius(14)
      Text(runtime.translate(name)).fontSize(14).lineHeight(19).width('100%').textAlign(TextAlign.Center)
        .fontWeight(this.state.themePreference === id ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.state.themePreference === id ? this.accentColor() : this.theme().ink)
        .maxLines(1)
    }.layoutWeight(1).onClick(() => { this.send('setTheme', { id: id, name: id }) })
  }

  @Builder
  settingsHome() {
    Scroll() {
      Column({ space: 20 }) {
        this.settingsSection('外观')
        Column() {
          Row({ space: 10 }) {
            this.themePreviewTile('light', '浅色')
            this.themePreviewTile('dark', '深色')
            this.themePreviewTile('system', '跟随系统')
          }.width('100%').padding(12)
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })

        Column() {
          Row({ space: 12 }) {
            Text('◐').fontSize(20).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('聊天外观')).fontSize(16).lineHeight(22).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.chatAppearanceLabel()).fontSize(14).lineHeight(19).fontColor(this.theme().muted).maxLines(1)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.settingsPage = 'appearance' })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('T').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('排版密度')).fontSize(16).lineHeight(22).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.densityLabel()).fontSize(14).fontColor(this.theme().muted)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.settingsPage = 'density' })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('▤').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('活动显示')).fontSize(16).lineHeight(22).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.activityDockLabel()).fontSize(14).fontColor(this.theme().muted)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.settingsPage = 'activity' })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('▣').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('系统状态栏')).fontSize(16).lineHeight(22).layoutWeight(1).fontColor(this.theme().ink)
            Toggle({ type: ToggleType.Switch, isOn: this.state.statusBarVisible })
              .selectedColor(this.accentColor())
              .onChange((on: boolean) => { if (on !== this.state.statusBarVisible) this.send('setStatusBar', { enabled: on }) })
          }.width('100%').height(58).padding({ left: 14, right: 12 })
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })

        this.settingsSection('语言')
        Row({ space: 12 }) {
          Text('文').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
          Text(runtime.translate('语言')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
          Text(this.languageLabel()).fontSize(14).fontColor(this.theme().muted)
          Text('›').fontSize(19).fontColor(this.theme().subtle)
        }.width('100%').height(58).padding({ left: 14, right: 12 })
          .backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })
          .onClick(() => { this.settingsPage = 'language' })

        this.settingsSection('工作区设置')
        Column() {
          Row({ space: 12 }) {
            Text('◷').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('启动恢复上次对话')).fontSize(16).lineHeight(22).layoutWeight(1).fontColor(this.theme().ink)
            Toggle({ type: ToggleType.Switch, isOn: this.state.resumeSessionEnabled })
              .selectedColor(this.accentColor()).enabled(!this.state.busy)
              .onChange((on: boolean) => { if (on !== this.state.resumeSessionEnabled) this.send('setResumeSession', { enabled: on }) })
          }.width('100%').height(58).padding({ left: 14, right: 12 })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('☷').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Column({ space: 3 }) {
              Text(runtime.translate('会话精简模式')).fontSize(16).lineHeight(22).fontColor(this.theme().ink).width('100%')
              Text(runtime.translate('缩减历史工具详情，保留正文和状态')).fontSize(12).lineHeight(17)
                .fontColor(this.theme().muted).width('100%').maxLines(2)
            }.layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.state.compactHistory })
              .selectedColor(this.accentColor()).enabled(!this.state.busy)
              .onChange((on: boolean) => { if (on !== this.state.compactHistory) this.send('compactHistory', {}) })
          }.width('100%').constraintSize({ minHeight: 72 }).padding({ left: 14, right: 12, top: 10, bottom: 10 })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('♢').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('启动自动连接主机')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Toggle({ type: ToggleType.Switch, isOn: this.state.autoConnectHost })
              .selectedColor(this.accentColor())
              .onChange((on: boolean) => { this.send('setAutoConnectHost', { enabled: on }) })
          }.width('100%').height(58).padding({ left: 14, right: 12 })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('♧').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('任务和待确认提醒')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Toggle({ type: ToggleType.Switch, isOn: this.state.notificationsEnabled })
              .selectedColor(this.accentColor())
              .onChange((on: boolean) => { if (on !== this.state.notificationsEnabled) this.send('setNotifications', { name: on ? 'true' : 'false' }) })
          }.width('100%').height(58).padding({ left: 14, right: 12 })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('♢').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Column({ space: 2 }) {
              Text(runtime.translate('开启系统通知权限')).fontSize(16).lineHeight(22).fontColor(this.theme().ink).width('100%')
              Text(runtime.translate('在应用处于后台时，接收任务完成与审批提示')).fontSize(12).lineHeight(17)
                .fontColor(this.theme().muted).width('100%').maxLines(1)
            }.layoutWeight(1)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(64).padding({ left: 14, right: 12 })
            .onClick(() => { this.send('requestNotificationPermission', {}) })
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })

        this.settingsSection('安全与连接')
        Column() {
          Row({ space: 12 }) {
            Text('◇').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('新对话默认权限')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.defaultPermissionLabel()).fontSize(14).fontColor(this.theme().muted)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.settingsPage = 'permission' })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('⇄').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('传输与直连策略')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Text(runtime.translate(this.state.transportPreference === 'turn' ? '仅穿透中继' : this.state.transportPreference === 'relay' ? '仅控制转发' : '自动优选'))
              .fontSize(14).fontColor(this.theme().muted)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.settingsPage = 'transport' })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('⌁').fontSize(19).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Column({ space: 3 }) {
              Text(runtime.translate('后台连接')).fontSize(16).fontColor(this.theme().ink).width('100%')
              Text(runtime.translate(this.state.backgroundActive ? '后台持续任务已启用' : '后台持续任务未启用'))
                .fontSize(12).lineHeight(17).fontColor(this.state.backgroundError ? this.theme().danger : this.theme().muted).width('100%')
            }.layoutWeight(1)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(64).padding({ left: 14, right: 12 })
            .onClick(() => { this.settingsPage = 'background' })
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })

        this.settingsSection('数据与关于')
        Column() {
          Row({ space: 12 }) {
            Text('⌫').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().danger)
            Text(runtime.translate('清除本地记录与缓存')).fontSize(16).layoutWeight(1).fontColor(this.theme().danger)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => {
              promptAction.showDialog({
                title: runtime.translate('清除本地记录与缓存'),
                message: runtime.translate('清除本机保存的草稿、收藏、历史浏览位置与连接缓存'),
                buttons: [
                  { text: runtime.translate('取消'), color: this.theme().muted },
                  { text: runtime.translate('确认'), color: this.theme().danger },
                ],
              }).then((result: promptAction.ShowDialogSuccessResponse) => {
                if (result.index === 1) this.send('clearBrowseData', {})
              })
            })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('↻').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('检查更新')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.state.updateVersion.length > 0 ? this.state.updateVersion : this.state.appVersion)
              .fontSize(14).fontColor(this.theme().muted)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.send('checkUpdate', {}) })
          this.settingsDivider()
          Row({ space: 12 }) {
            Text('ⓘ').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('打开发布页')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.state.appVersion).fontSize(14).fontColor(this.theme().muted)
            Text('›').fontSize(19).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .onClick(() => { this.send('openUpdates', {}) })
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })
        Text(runtime.translate('鸿蒙安装包需要匹配签名；请使用正式发布的 HAP 或 HoKit 覆盖安装'))
          .fontSize(12).lineHeight(17).fontColor(this.theme().muted).padding({ left: 16, right: 16 })
      }.width('100%').padding({ bottom: 28 })
    }.layoutWeight(1).width('100%')
  }

  @Builder
  settingsAppearancePage() {
    Scroll() {
      Column({ space: 20 }) {
        this.settingsSection('预览')
        Column({ space: 10 }) {
          Row() {
            Blank()
            Text(runtime.translate('这段对话在使用当前字号、行距与主题色显示。'))
              .fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
              .fontColor(this.appearanceValue('bubbleStyle') === 'solid' ? this.theme().white : this.theme().ink)
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(this.appearanceValue('bubbleStyle') === 'solid' ? this.accentColor() : this.theme().userBubble)
              .borderRadius({ topLeft: 18, topRight: 6, bottomLeft: 18, bottomRight: 18 })
          }.width('100%')
          Text(runtime.translate('DSH Remote 会把当前设置同步到消息正文、工具卡片与代码块。'))
            .fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
            .fontColor(this.theme().ink).width('100%')
        }.width('100%').padding(14).backgroundColor(this.theme().surface).borderRadius(20)
          .border({ width: 1, color: this.theme().separator })

        this.settingsSection('主题色')
        Row({ space: 8 }) {
          ForEach(this.accentItems(), (item: AccentPresetView) => {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.Center }) {
                Text('').width(36).height(36).borderRadius(18).backgroundColor(item.color)
                if (this.appearanceValue('accent') === item.id) Text('✓').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
              }.width(48).height(48).borderRadius(24)
                .border({ width: 2, color: this.appearanceValue('accent') === item.id ? item.color : Color.Transparent })
              Text(runtime.translate(item.name)).fontSize(12).fontColor(this.appearanceValue('accent') === item.id ? this.theme().ink : this.theme().muted)
            }.layoutWeight(1).onClick(() => { this.send('setChatAppearance', { name: 'accent', text: item.id }) })
          }, (item: AccentPresetView) => item.id)
        }.width('100%').padding(12).backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })

        Column({ space: 16 }) {
          this.appearanceRow('字体大小', 'fontScale', ['sm','md','lg','xl'], ['小','标准','大','特大'])
          this.appearanceRow('行距', 'spacingScale', ['tight','balanced','relaxed'], ['紧凑','均衡','宽松'])
          this.appearanceRow('字距', 'letterSpacing', ['normal','wide','wider'], ['标准','宽','更宽'])
          this.appearanceRow('气泡', 'bubbleStyle', ['soft','tinted','solid','minimal'], ['柔和','浅色','纯色','极简'])
          this.appearanceRow('代码配色', 'codeTheme', ['auto','dark','light'], ['跟随主题','深色','浅色'])
        }.width('100%').padding(14).backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })
        Button(runtime.translate('恢复默认外观')).height(46).fontSize(15)
          .backgroundColor(this.theme().surfaceStrong).fontColor(this.accentColor()).borderRadius(999)
          .onClick(() => { this.send('resetChatAppearance', {}) })
      }.width('100%').padding({ bottom: 28 })
    }.layoutWeight(1).width('100%')
  }

  private choiceValue(field: string): string {
    if (field === 'theme') return this.state.themePreference
    if (field === 'density') return this.state.typographyDensity
    if (field === 'activity') return this.state.activityDockMode
    if (field === 'permission') return this.state.defaultPermission
    return this.state.transportPreference
  }

  @Builder
  settingsChoicePage(subtitle: string, ids: string[], names: string[], field: string) {
    Scroll() {
      Column({ space: 14 }) {
        Text(runtime.translate(subtitle)).fontSize(14).lineHeight(20).fontColor(this.theme().muted)
          .width('100%').padding({ left: 16, right: 16 })
        Column() {
          ForEach(ids, (id: string, index: number) => {
            Row({ space: 12 }) {
              Text(runtime.translate(names[index])).fontSize(16).lineHeight(22).layoutWeight(1)
                .fontWeight(this.choiceValue(field) === id ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.choiceValue(field) === id ? this.accentColor() : this.theme().ink)
              if (this.choiceValue(field) === id) {
                Text('✓').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.accentColor())
              } else {
                Text('○').fontSize(16).fontColor(this.theme().subtle)
              }
            }.width('100%').height(58).padding({ left: 16, right: 16 })
              .onClick(() => {
                if (field === 'theme') this.send('setTheme', { id: id, name: id })
                else if (field === 'density') this.send('setDensity', { id: id, name: id })
                else if (field === 'activity') this.send('setActivityDockMode', { name: id })
                else if (field === 'transport') this.send('setTransportPreference', { mode: id })
                else if (field === 'permission') {
                  if (id !== 'danger-full-access') {
                    this.send('setDefaultPermission', { name: id })
                  } else {
                    promptAction.showDialog({
                      title: runtime.translate('完全权限'),
                      message: runtime.translate('新对话可以修改文件与执行命令，不再逐次询问。'),
                      buttons: [
                        { text: runtime.translate('取消'), color: this.theme().muted },
                        { text: runtime.translate('确认'), color: this.accentColor() },
                      ],
                    }).then((result: promptAction.ShowDialogSuccessResponse) => {
                      if (result.index === 1) this.send('setDefaultPermission', { name: id })
                    })
                  }
                }
                this.settingsPage = ''
              })
            if (index < ids.length - 1) this.settingsDivider()
          }, (id: string) => `${field}|${id}`)
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })
      }.width('100%').padding({ top: 4, bottom: 28 })
    }.layoutWeight(1).width('100%')
  }

  @Builder
  settingsLanguagePage() {
    Scroll() {
      Column() {
        ForEach([
          { id: 'system', name: '跟随系统' },
          { id: 'zh-CN', name: '简体中文' },
          { id: 'en-US', name: 'English' },
          { id: 'zh-TW', name: '繁體中文' },
          { id: 'ja-JP', name: '日本語' },
          { id: 'es-ES', name: 'Español' },
          { id: 'de-DE', name: 'Deutsch' },
          { id: 'fr-FR', name: 'Français' },
        ], (item: PrefOption, index: number) => {
          Row() {
            Text(runtime.translate(item.name)).fontSize(16).lineHeight(22).layoutWeight(1)
              .fontWeight(this.state.languagePreference === item.id ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.state.languagePreference === item.id ? this.accentColor() : this.theme().ink)
            if (this.state.languagePreference === item.id) Text('✓').fontSize(18).fontColor(this.accentColor())
          }.width('100%').height(56).padding({ left: 16, right: 16 })
            .onClick(() => { this.send('setLanguage', { id: item.id, name: item.id }); this.settingsPage = '' })
          if (index < 7) this.settingsDivider()
        }, (item: PrefOption) => item.id)
      }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
        .border({ width: 1, color: this.theme().separator }).margin({ top: 4, bottom: 28 })
    }.layoutWeight(1).width('100%')
  }

  @Builder
  settingsBackgroundPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.settingsSection('后台连接')
        Column({ space: 10 }) {
          Text(runtime.translate(this.state.backgroundActive ? '后台持续任务已启用' : '后台持续任务未启用'))
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.state.backgroundActive ? this.theme().success : this.theme().ink).width('100%')
          if (this.state.backgroundError) {
            Text(runtime.translate(this.state.backgroundError)).fontSize(13).lineHeight(18)
              .fontColor(this.theme().danger).width('100%')
          }
          Text(runtime.translate('系统省电策略可能暂停连接，可在应用设置中检查通知与后台权限'))
            .fontSize(13).lineHeight(18).fontColor(this.theme().muted).width('100%')
          Button(runtime.translate('应用系统设置')).height(46).width('100%')
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { this.send('appSettings', {}) })
          Button(runtime.translate('开启系统通知权限')).height(46).width('100%')
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .onClick(() => { this.send('requestNotificationPermission', {}) })
          Button(runtime.translate('重试后台连接')).height(46).width('100%')
            .backgroundColor(this.accentColor()).fontColor(this.theme().onPrimary).borderRadius(999)
            .enabled(this.state.connected)
            .onClick(() => { this.send('retryBackground', {}) })
        }.width('100%').padding(16).backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })
      }.width('100%').padding({ top: 4, bottom: 28 })
    }.layoutWeight(1).width('100%')
  }

  /** Android's settings screen, expressed as an ArkUI full-height sheet with native subpages. */
  @Builder
  settingsSheet() {
    Column({ space: 10 }) {
      this.settingsHeader(
        this.settingsPage === 'appearance' ? '聊天外观'
          : this.settingsPage === 'language' ? '语言'
            : this.settingsPage === 'density' ? '排版密度'
              : this.settingsPage === 'activity' ? '活动显示'
                : this.settingsPage === 'permission' ? '默认权限'
                  : this.settingsPage === 'transport' ? '传输策略'
                    : this.settingsPage === 'background' ? '后台连接'
                      : '设置'
      )
      if (this.settingsPage === 'appearance') {
        this.settingsAppearancePage()
      } else if (this.settingsPage === 'language') {
        this.settingsLanguagePage()
      } else if (this.settingsPage === 'density') {
        this.settingsChoicePage('调整正文行距、段间距与气泡紧凑度', ['standard','compact'], ['标准','紧凑'], 'density')
      } else if (this.settingsPage === 'activity') {
        this.settingsChoicePage('选择会话中活动卡的显示方式', ['compact','cards','hidden'], ['紧凑','卡片','隐藏'], 'activity')
      } else if (this.settingsPage === 'permission') {
        this.settingsChoicePage('仅影响新建的 DSH / CodeX 对话，已有对话不变', ['default','workspace-write','danger-full-access'], ['默认','工作区读写','完全权限'], 'permission')
      } else if (this.settingsPage === 'transport') {
        this.settingsChoicePage('优先尝试局域网与 P2P 直连，遇到网络限制自动回退中继', ['auto','turn','relay'], ['自动优选','仅穿透中继','仅控制转发'], 'transport')
      } else if (this.settingsPage === 'background') {
        this.settingsBackgroundPage()
      } else {
        this.settingsHome()
      }
    }.width('100%').height('94%').padding({ left: 18, right: 18, top: 16, bottom: 20 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** Android's Bot team roster panel: members, main bot badge, roles, models and open conversation. */
  @Builder
  legacyBotSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('Bot 团队')).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor(this.theme().muted).enabled(!this.state.busy)
          .onClick(() => { this.send('bots', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')
      Button(runtime.translate('管理智能体与群组')).onClick(() => { this.showBots = false; this.alignmentPanel = 'bots' })
      if (this.state.bots.length === 0) {
        Text(this.state.busy ? '正在加载 Bot 团队…'
          : '这台主机暂无 Bot，或尚未启用 ds-bot 插件')
          .fontSize(13).fontColor(this.theme().muted).padding(16).width('100%')
      } else {
        List({ space: 6 }) {
          ForEach(this.state.bots, (bot: BotEntryRow) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(bot.name.slice(0, 1).toUpperCase())
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  .width(36).height(36).textAlign(TextAlign.Center).borderRadius(18)
                  .backgroundColor(bot.color.length > 0 ? bot.color : this.state.accentColor)
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(bot.name).fontSize(15).fontWeight(FontWeight.Medium)
                    if (bot.main) {
                      Text(runtime.translate('主 Bot')).fontSize(10).fontColor(this.state.accentColor)
                        .backgroundColor(this.theme().primarySoft).padding({ left: 4, right: 4, top: 1, bottom: 1 }).borderRadius(4)
                    }
                  }
                  Text(`${bot.role}${bot.model.length > 0 ? ' · ' + bot.model : ''}`)
                    .fontSize(12).fontColor(this.theme().muted).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(runtime.translate('打开')).fontSize(12).height(30).backgroundColor(this.theme().surfaceStrong)
                  .fontColor(this.state.accentColor)
                  .onClick(() => {
                    this.closePanels()
                    this.send('botSelect', { id: bot.id })
                  })
              }.width('100%').padding(10).borderRadius(12)
              .backgroundColor(this.theme().card)
            }
          }, (bot: BotEntryRow) => `bot|${bot.id}|${bot.name}|${bot.main}`)
        }.width('100%').constraintSize({ maxHeight: 380 })
      }
    }
    .width('100%').padding(16)
    .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  @Builder
  botSheet() {
    if (this.showBots) {
      this.legacyBotSheet()
    } else {
      Stack({ alignContent: Alignment.Bottom }) {
        Column({ space: 14 }) {
          this.homeModeSwitcher()
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text(runtime.translate('Bot 团队')).fontSize(21).lineHeight(27).fontWeight(FontWeight.Bold).fontColor(this.theme().ink)
              Text(runtime.translate('选择 Bot 开始对话，或在电脑端管理团队成员')).fontSize(13).lineHeight(18).fontColor(this.theme().muted)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button('⟳').accessibilityText(runtime.translate('刷新')).fontSize(17).width(40).height(40).padding(0)
              .backgroundColor(this.theme().elevated).fontColor(this.theme().muted).borderRadius(999)
              .border({ width: 1, color: this.theme().separator })
              .enabled(!this.state.busy).onClick(() => { this.send('bots', {}) })
          }.width('100%').padding({ top: 8 })
          Row({ space: 12 }) {
            Text('⚙').fontSize(18).width(28).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('管理智能体与群组')).fontSize(16).layoutWeight(1).fontColor(this.theme().ink)
            Text('›').fontSize(18).fontColor(this.theme().subtle)
          }.width('100%').height(58).padding({ left: 14, right: 12 })
            .backgroundColor(this.theme().grouped).borderRadius(22)
            .border({ width: 1, color: this.theme().separator })
            .onClick(() => { this.alignmentPanel = 'bots' })
          if (this.state.bots.length === 0) {
            Column({ space: 7 }) {
              Text('◫').fontSize(30).fontColor(this.theme().subtle)
              Text(runtime.translate(this.state.busy ? '正在加载 Bot 团队…' : '这台主机暂无 Bot'))
                .fontSize(15).fontColor(this.theme().ink)
              Text(runtime.translate('请确认电脑端已启用并配置 ds-bot 插件')).fontSize(12).fontColor(this.theme().muted)
            }.width('100%').padding(30)
          } else {
            List({ space: 8 }) {
              ForEach(this.state.bots, (bot: BotEntryRow) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Text(bot.name.slice(0, 1).toUpperCase())
                      .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                      .width(42).height(42).textAlign(TextAlign.Center).borderRadius(14)
                      .backgroundColor(bot.color.length > 0 ? bot.color : this.accentColor())
                    Column({ space: 3 }) {
                      Row({ space: 7 }) {
                        Text(bot.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme().ink)
                        if (bot.main) {
                          Text(runtime.translate('主 Bot')).fontSize(10).fontColor(this.accentColor())
                            .backgroundColor(this.theme().primarySoft).padding({ left: 5, right: 5, top: 2, bottom: 2 }).borderRadius(5)
                        }
                      }
                      Text(`${bot.role}${bot.model.length > 0 ? ' · ' + bot.model : ''}`)
                        .fontSize(12).lineHeight(17).fontColor(this.theme().muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text('›').fontSize(18).fontColor(this.theme().subtle)
                  }.width('100%').height(64).padding({ left: 14, right: 12 })
                    .backgroundColor(this.theme().card).borderRadius(18)
                    .border({ width: 1, color: this.theme().separator })
                }.onClick(() => { this.send('botSelect', { id: bot.id }) })
              }, (bot: BotEntryRow) => `home-bot|${bot.id}|${bot.name}|${bot.main}|${bot.model}`)
            }.layoutWeight(1).width('100%').padding({ bottom: 86 })
          }
        }.width('100%').height('100%').padding({ left: 16, right: 16, bottom: 76 })
        this.homeHostFooter()
      }.width('100%').height('100%')
    }
  }

  /** Android's 网络详情 panel: path, probe order, endpoints, RTT, bitrate, traffic. */
  @Builder
  networkSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('网络与链路详情')).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('⟳').fontSize(15).width(34).height(34).backgroundColor(Color.Transparent)
          .fontColor(this.theme().muted).enabled(!this.state.busy)
          .onClick(() => { this.send('networkDetails', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')
      if (this.state.networkSections.length === 0) {
        Text(runtime.translate(this.state.busy ? '正在获取网络状态…' : '网络状态暂不可用')).fontSize(13)
          .fontColor(this.theme().muted).padding(16).width('100%')
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.state.networkSections, (sec: NetworkSection) => {
              Column({ space: 6 }) {
                Text(sec.title).fontSize(13).fontWeight(FontWeight.Bold)
                  .fontColor(this.theme().muted).width('100%')
                Column({ space: 2 }) {
                  ForEach(sec.rows, (row: NetworkRow) => {
                    Column({ space: 3 }) {
                      Text(row.label).fontSize(12).fontColor(this.theme().muted).width('100%')
                      Text(row.value).fontSize(14).width('100%')
                        .fontFamily(row.mono ? 'monospace' : 'sans-serif')
                        .copyOption(CopyOptions.LocalDevice)
                    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
                  }, (row: NetworkRow) => `nr|${row.label}|${row.value}`)
                }.width('100%').padding(12).borderRadius(12)
                .backgroundColor(this.theme().surfaceStrong)
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (sec: NetworkSection) => `ns|${sec.title}`)
          }.width('100%')
        }.constraintSize({ maxHeight: 460 }).width('100%')
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** Android's terminal panel: tab strip, monospace screen, shortcut bar and command input. */
  @Builder
  terminalSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(runtime.translate('终端')).fontSize(this.typography().headingSize + 2)
          .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
        if (this.state.terminalBusy) {
          Text('…').fontSize(14).fontColor(this.theme().muted)
        }
        Button(runtime.translate('＋ 新建')).fontSize(12).height(32).backgroundColor(Color.Transparent)
          .fontColor(this.state.accentColor).enabled(!this.state.busy && !this.state.terminalBusy)
          .onClick(() => { this.send('createTerminal', {}) })
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.closePanels() })
      }.width('100%')

      if (this.state.terminals.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.state.terminals, (item: TerminalRow) => {
              Button(item.title).fontSize(12).height(28)
                .backgroundColor(this.state.activeTerminalId === item.id ? this.state.accentColor : this.theme().surfaceStrong)
                .fontColor(this.state.activeTerminalId === item.id ? this.theme().onPrimary : this.theme().ink)
                .enabled(!this.state.terminalBusy)
                .onClick(() => { this.send('selectTerminal', { id: item.id }) })
            }, (item: TerminalRow) => `${item.id}|${item.title}|${item.state}`)
            if (this.state.activeTerminalId.length > 0) {
              Button(runtime.translate('结束终端')).fontSize(12).height(28).backgroundColor(Color.Transparent)
                .fontColor(this.theme().warning).enabled(!this.state.terminalBusy)
                .onClick(() => { this.send('closeTerminal', {}) })
            }
          }.alignItems(VerticalAlign.Center)
        }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
      }

      if (this.state.terminalError.length > 0) {
        Row({ space: 8 }) {
          Text(this.state.terminalError).fontSize(12).fontColor(this.theme().warning).layoutWeight(1)
          Button(runtime.translate('重试')).fontSize(11).height(26).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
            .onClick(() => { this.send('retryTerminal', {}) })
        }.width('100%').padding(6).backgroundColor(this.theme().surfaceStrong).borderRadius(6)
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
          Button('Ctrl+C').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x03' }) })
          Button('Tab').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\t' }) })
          Button('Esc').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b' }) })
          Button('↑').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[A' }) })
          Button('↓').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[B' }) })
          Button('←').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[D' }) })
          Button('→').fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x1b[C' }) })
          Button(runtime.translate('退格')).fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\x7f' }) })
          Button(runtime.translate('回车')).fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.state.accentColor).enabled(this.state.terminalWritable)
            .onClick(() => { this.send('writeTerminal', { text: '\r' }) })
          Button(runtime.translate('清屏')).fontSize(11).height(28).backgroundColor(this.theme().surfaceStrong)
            .fontColor(this.theme().muted)
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
        Button(runtime.translate('发送')).fontSize(13).height(36).backgroundColor(this.state.accentColor).fontColor(Color.White)
          .enabled(this.state.terminalWritable && this.terminalInput.length > 0)
          .onClick(() => {
            if (this.terminalInput.length > 0) {
              this.send('writeTerminal', { text: `${this.terminalInput}\r` })
              this.terminalInput = ''
            }
          })
      }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  /** Android keeps 快捷提示词 out of 更多操作: its own list, then a manager, then an editor. */
  @Builder
  promptsPanel() {
    Column({ space: 10 }) {
      if (this.promptPage === '') {
        Row() {
          Text(runtime.translate('快捷提示词')).fontSize(this.typography().headingSize + 2)
            .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
            .onClick(() => { this.showPrompts = false; this.promptPage = '' })
        }.width('100%')
        if (this.state.prompts.length === 0) {
          Text(runtime.translate('没有提示词。点击「编辑提示词」增加常用提示词。')).fontSize(13)
            .fontColor(this.theme().muted).padding(16).width('100%')
        } else {
          List({ space: 2 }) {
            ForEach(this.state.prompts, (item: PromptRow) => {
              ListItem() {
                Column({ space: 3 }) {
                  Text(item.title).fontSize(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.text).fontSize(12).fontColor(this.theme().muted)
                    .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 10 })
              }.enabled(!this.state.busy).onClick(() => { this.startPrompt(item) })
            }, (item: PromptRow) => `send|${item.id}|${item.title}|${item.text}`)
          }.width('100%').constraintSize({ maxHeight: 300 })
        }
        Row({ space: 8 }) {
          Text(runtime.translate('编辑提示词')).fontSize(15).layoutWeight(1)
          Text('›').fontSize(17).fontColor(this.theme().muted)
        }.width('100%').height(50).onClick(() => { this.promptPage = 'manager' })
      } else {
        Row({ space: 8 }) {
          Button('‹').fontSize(24).width(36).height(36).backgroundColor(Color.Transparent)
            .fontColor(this.theme().muted).onClick(() => { this.promptPage = '' })
          Text(runtime.translate('编辑提示词')).fontSize(this.typography().headingSize + 2)
            .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('＋').fontSize(17).width(36).height(36).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
            .onClick(() => {
              this.promptId = ''; this.promptTitle = ''; this.promptText = ''
              this.showPrompts = false; this.showPromptForm = true
            })
          Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
            .onClick(() => { this.showPrompts = false; this.promptPage = '' })
        }.width('100%')
        List({ space: 2 }) {
          ForEach(this.state.prompts, (item: PromptRow) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(item.title).fontSize(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(runtime.translate(item.builtIn ? '内置' : item.text)).fontSize(12).fontColor(this.theme().muted)
                    .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button(runtime.translate('编辑')).fontSize(12).height(32).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                  .onClick(() => { this.editPrompt(item) })
                if (!item.builtIn) {
                  Button(runtime.translate('删除')).fontSize(12).height(32).backgroundColor(Color.Transparent).fontColor(this.theme().danger)
                    .onClick(() => { this.send('deletePrompt', { id: item.id }) })
                }
              }.width('100%').padding({ top: 8, bottom: 8 })
            }
          }, (item: PromptRow) => `edit|${item.id}|${item.title}|${item.text}|${item.builtIn}`)
        }.width('100%').constraintSize({ maxHeight: 330 })
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  @Builder
  promptForm() {
    Column({ space: 12 }) {
      Row() {
        Text(runtime.translate(this.promptId.length > 0 ? `编辑“${this.promptTitle}”` : '新建提示词'))
          .fontSize(this.typography().headingSize + 2).lineHeight(this.typography().headingLineHeight + 4)
          .fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.showPromptForm = false })
      }.width('100%')
      TextInput({ text: this.promptTitle, placeholder: runtime.translate('提示词名称') }).onChange((value: string) => { this.promptTitle = value })
      TextArea({ text: this.promptText, placeholder: runtime.translate('提示词内容') })
        .constraintSize({ minHeight: 110, maxHeight: 220 }).onChange((value: string) => { this.promptText = value })
      Row({ space: 10 }) {
        Button(runtime.translate('保存')).layoutWeight(1).backgroundColor(this.state.accentColor)
          .enabled(this.promptTitle.trim().length > 0 && this.promptText.trim().length > 0)
          .onClick(() => {
            runtime.perform('savePrompt', JSON.stringify({
              id: this.promptId, name: this.promptTitle, text: this.promptText,
            } as ActionInput)).catch(() => {})
            this.showPromptForm = false
          })
        Button(runtime.translate('取消')).layoutWeight(1).backgroundColor(this.theme().surfaceStrong)
          .onClick(() => { this.showPromptForm = false })
      }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  @Builder
  manageSheet() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text(runtime.translate('管理工作区')).fontSize(this.typography().headingSize + 2)
            .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold).width('100%')
          Text(this.manageTarget?.name ?? '').fontSize(14).fontColor(this.theme().muted).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('✕').fontSize(18).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.manageTarget = undefined; this.confirmDelete = '' })
      }.width('100%')
      Text(this.manageTarget?.description ?? '').fontSize(12).fontColor(this.theme().muted)
        .width('100%').copyOption(CopyOptions.LocalDevice)
      if (this.manageTarget !== undefined && this.manageTarget.backend !== 'harness') {
        Text(runtime.translate('CodeX 与 ACP 工作区的名称、顺序和删除由电脑端管理。')).fontSize(13).fontColor(this.theme().warning).width('100%')
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
          Button(runtime.translate('↑ 上移')).layoutWeight(1).backgroundColor(this.theme().surfaceStrong)
            .onClick(() => { this.moveWorkspaceBy('up') })
          Button(runtime.translate('↓ 下移')).layoutWeight(1).backgroundColor(this.theme().surfaceStrong)
            .onClick(() => { this.moveWorkspaceBy('down') })
        }.width('100%')
        if (this.confirmDelete.length === 0) {
          Button(runtime.translate('删除工作区')).width('100%').backgroundColor(this.theme().danger).fontColor(Color.White)
            .onClick(() => { this.confirmDelete = 'again' })
        } else {
          Text(runtime.translate('删除将从这台主机移除该工作区及其所有对话，且无法撤销。')).fontSize(12).fontColor(this.theme().danger).width('100%')
          Row({ space: 10 }) {
            Button(runtime.translate('确认删除')).layoutWeight(1).backgroundColor(this.theme().danger).fontColor(Color.White)
              .onClick(() => {
                const target = this.manageTarget
                if (target === undefined) return
                runtime.perform('deleteWorkspace', JSON.stringify({ id: target.id } as ActionInput)).catch(() => {})
                this.manageTarget = undefined; this.confirmDelete = ''
              })
            Button(runtime.translate('返回')).layoutWeight(1).backgroundColor(this.theme().surfaceStrong)
              .onClick(() => { this.confirmDelete = '' })
          }.width('100%')
        }
      }
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 28 })
      .backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
  }

  private moveWorkspaceBy(direction: string): void {
    const target = this.manageTarget
    if (target === undefined) return
    runtime.perform('moveWorkspace', JSON.stringify({ id: target.id, mode: direction } as ActionInput)).catch(() => {})
  }

  @Builder
  scrim() {
    Column().width('100%').height('100%').backgroundColor(this.theme().modalBackdrop).onClick(() => { this.closePanels() })
  }

  @Builder
  traceControls() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.traceQuery, placeholder: runtime.translate('搜索消息、工具或轮次') }).layoutWeight(1)
          .onChange((value: string) => { this.traceQuery = value })
        if (this.traceQuery.length > 0) {
          Button(runtime.translate('清空')).fontSize(12).height(34).backgroundColor(Color.Transparent)
            .fontColor(this.theme().muted).onClick(() => { this.traceQuery = '' })
        }
      }
      Scroll() {
        Row({ space: 6 }) {
          ForEach(['all', 'system', 'user', 'context', 'assistant', 'tool'], (key: string) => {
            Button(this.categoryLabel(key)).fontSize(12).height(30)
              .backgroundColor(this.traceCategory === key ? this.theme().primarySoft : this.theme().surfaceStrong)
              .fontColor(this.traceCategory === key ? this.theme().primary : this.theme().ink)
              .onClick(() => { this.traceCategory = key })
          }, (key: string) => `${key}|${this.traceCategory === key ? 'on' : 'off'}`)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      Text(runtime.translate('仅显示已加载的真实消息；加载更早记录可扩展轨迹。'))
        .fontSize(11).fontColor(this.theme().muted).width('100%')
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
      await this.stageFileUri(uri, scope, name)
      }
    } catch (error) { this.imageError = runtime.translate((error as Error).message) }
  }

  private async stageFileUri(uri: string, scope: string, name: string): Promise<void> {
    if (scope !== this.state.sessionKey || !this.state.connected) throw new Error('会话已切换，附件已取消')
    const file = await fs.open(uri, fs.OpenMode.READ_ONLY)
    try {
      const size: number = (await fs.stat(file.fd)).size
      if (size <= 0 || size > this.state.uploadMaxBytes) throw new Error('文件超过当前传输通道的大小限制。')
      if (!await runtime.perform('stageNativeFile', JSON.stringify({ uri: uri, name: name, size: size }))) throw new Error(this.state.error || '文件无法添加')
    } finally { await fs.close(file.fd) }
  }
  private async pickVideo(): Promise<void> {
    const scope: string = this.state.sessionKey
    try {
      const picker = new photoAccessHelper.PhotoViewPicker()
      const selected = await picker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE, maxSelectNumber: 8 })
      for (const uri of selected.photoUris) await this.stageFileUri(uri, scope, decodeURIComponent(uri.split('/').pop() ?? 'video.mp4'))
    } catch (error) { this.imageError = (error as Error).message }
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
    if (this.state.view === 'workspaces' || this.state.view === 'botHome') {
      Row({ space: 10 }) {
        Row({ space: 8 }) {
          Image($r('app.media.fish_logo')).width(25).height(19).fillColor(this.theme().ink)
          Text('DS Harness Remote')
            .fontSize(21).lineHeight(26).fontWeight(FontWeight.Bold)
            .fontColor(this.theme().ink).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1)
        Button('⋮').accessibilityText(runtime.translate('更多'))
          .fontSize(21).width(42).height(42).padding(0)
          .backgroundColor(this.theme().elevated).fontColor(this.theme().ink).borderRadius(999)
          .border({ width: 1, color: this.theme().separator })
          .onClick(() => { this.showHostSwitcher = true; this.invoke('refresh') })
      }.width('100%').padding({ left: 20, right: 16, top: 14, bottom: 10 })
        .backgroundColor(this.theme().background)
    } else if (this.state.view === 'chat') {
      Row({ space: 10 }) {
        Button(this.state.connected ? '☰' : '‹')
          .accessibilityText(runtime.translate(this.state.connected ? '工作区与会话' : '返回'))
          .fontSize(this.state.connected ? 20 : 24).width(42).height(42).padding(0).flexShrink(0)
          .backgroundColor(this.theme().elevated).borderRadius(999)
          .border({ width: 1, color: this.theme().separator }).fontColor(this.theme().ink)
          .onClick(() => { if (this.state.connected) this.openDrawer(); else this.invoke('back') })
        Column({ space: 1 }) {
          Text(this.state.title).width('100%').fontSize(18).lineHeight(23).fontWeight(FontWeight.Bold)
            .fontColor(this.theme().ink).textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(runtime.translate(this.state.connected || this.state.recovering ? this.state.status : '已断开连接'))
            .width('100%').textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(12).lineHeight(16)
            .fontColor(this.state.connected ? (this.state.recovering ? this.theme().warning : this.theme().success) : this.theme().muted)
        }.alignItems(HorizontalAlign.Center).layoutWeight(1)
        if (this.state.connected) {
          Row({ space: 2 }) {
            Button('⋯').accessibilityText(runtime.translate('会话操作')).fontSize(19).width(34).height(34).padding(0)
              .backgroundColor(Color.Transparent).fontColor(this.theme().ink).borderRadius(999)
              .onClick(() => { this.openMore() })
            Button('＋').accessibilityText(runtime.translate('新建对话')).fontSize(22).width(34).height(34).padding(0)
              .backgroundColor(Color.Transparent).fontColor(this.theme().ink).borderRadius(999)
              .enabled(!this.state.busy).onClick(() => { this.invoke('newSession') })
          }.height(42).padding({ left: 4, right: 4 }).flexShrink(0)
            .backgroundColor(this.theme().elevated).borderRadius(999)
            .border({ width: 1, color: this.theme().separator })
        } else {
          Row({ space: 4 }) {
            if (this.state.canReconnect) {
              Button(runtime.translate('重连')).fontSize(12).height(36).padding({ left: 10, right: 10 })
                .backgroundColor(this.theme().primarySoft).fontColor(this.accentColor()).borderRadius(999)
                .onClick(() => { this.invoke('reconnect') })
            }
            Button('⚙').accessibilityText(runtime.translate('设置')).fontSize(17).width(38).height(38).padding(0)
              .backgroundColor(this.theme().elevated).borderRadius(999).border({ width: 1, color: this.theme().separator })
              .fontColor(this.theme().ink).onClick(() => { this.settingsPage = ''; this.showSettings = true })
          }.flexShrink(0)
        }
      }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 8 })
        .backgroundColor(this.theme().background)
    } else {
      Row({ space: 8 }) {
        if (this.state.view !== 'login' && this.state.view !== 'devices') {
          Button('‹').accessibilityText(runtime.translate('返回')).fontSize(24).fontWeight(FontWeight.Medium)
            .width(40).height(40).padding(0).flexShrink(0).backgroundColor(this.theme().elevated).borderRadius(999)
            .border({ width: 1, color: this.theme().separator })
            .fontColor(this.theme().ink).onClick(() => { this.invoke('back') })
        }
        Column({ space: 1 }) {
          Text(this.state.title).width('100%').fontSize(17).lineHeight(22).fontWeight(FontWeight.Bold)
            .fontColor(this.theme().ink).textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(runtime.translate(this.state.connected || this.state.recovering ? this.state.status : 'HarmonyOS · 0.6.5 移植预览'))
            .width('100%').textAlign(TextAlign.Center)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
            .fontColor(this.state.connected ? (this.state.recovering ? this.theme().warning : this.theme().success) : this.theme().muted)
        }.alignItems(HorizontalAlign.Center).layoutWeight(1)
        Button('⚙').accessibilityText(runtime.translate('设置')).fontSize(17).width(40).height(40).padding(0)
          .backgroundColor(this.theme().elevated).borderRadius(999).border({ width: 1, color: this.theme().separator })
          .fontColor(this.theme().ink).onClick(() => { this.settingsPage = ''; this.showSettings = true })
      }.padding({ left: 16, right: 16, top: 8, bottom: 10 }).width('100%')
        .backgroundColor(this.theme().background)
    }
  }

  @Builder
  login() {
    Scroll() {
      Column({ space: 18 }) {
        Image($r('app.media.app_icon')).width(64).height(64).borderRadius(18).margin({ top: 20 })
        Text(runtime.translate('让工作，随你而行')).fontSize(this.typography().heroSize)
          .lineHeight(this.typography().heroLineHeight).fontWeight(FontWeight.Bold)
          .fontColor(this.theme().ink)
        Text(runtime.translate('连接电脑上的 Harness、CodeX 与 ACP 工作区'))
          .fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
          .fontColor(this.theme().muted).textAlign(TextAlign.Center)
        Column({ space: 14 }) {
          TextInput({ text: this.server, placeholder: runtime.translate('服务器 HTTPS 地址') })
            .height(52).fontSize(this.typography().bodySize).fontColor(this.theme().ink).placeholderColor(this.theme().muted)
            .backgroundColor(this.theme().surface).border({ width: 1, color: this.theme().border }).borderRadius(16)
            .onChange((value: string) => { this.server = value })
          TextInput({ text: this.email, placeholder: runtime.translate('邮箱') }).type(InputType.Email)
            .height(52).fontSize(this.typography().bodySize).fontColor(this.theme().ink).placeholderColor(this.theme().muted)
            .backgroundColor(this.theme().surface).border({ width: 1, color: this.theme().border }).borderRadius(16)
            .onChange((value: string) => { this.email = value })
          TextInput({ text: this.password, placeholder: runtime.translate('密码') }).type(InputType.Password)
            .height(52).fontSize(this.typography().bodySize).fontColor(this.theme().ink).placeholderColor(this.theme().muted)
            .backgroundColor(this.theme().surface).border({ width: 1, color: this.theme().border }).borderRadius(16)
            .onChange((value: string) => { this.password = value })
          Button(runtime.translate('登录并注册本机')).width('100%').height(50)
            .fontSize(this.typography().bodySize).fontWeight(FontWeight.Medium)
            .backgroundColor(this.state.accentColor).fontColor(this.theme().onPrimary).borderRadius(999)
            .enabled(!this.state.busy && this.email.length > 0 && this.password.length > 0)
            .onClick(() => {
              const password: string = this.password
              this.password = ''
              runtime.perform('login', JSON.stringify({ server: this.server, email: this.email, password: password })).catch(() => {})
            })
        }.padding(20).borderRadius(22).backgroundColor(this.theme().card)
          .border({ width: 1, color: this.theme().separator }).width('100%')
        Text(runtime.translate('或使用网页 OAuth 授权登录')).fontSize(this.typography().smallSize)
          .fontColor(this.theme().muted)
        Row({ space: 12 }) {
          Button(runtime.translate('使用 GitHub 登录')).layoutWeight(1).height(48).fontSize(this.typography().smallSize)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .enabled(!this.state.busy)
            .onClick(() => { runtime.perform('startOAuth', JSON.stringify({ server: this.server, provider: 'github' })).catch(() => {}) })
          Button(runtime.translate('使用知乎登录')).layoutWeight(1).height(48).fontSize(this.typography().smallSize)
            .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
            .enabled(!this.state.busy)
            .onClick(() => { runtime.perform('startOAuth', JSON.stringify({ server: this.server, provider: 'zhihu' })).catch(() => {}) })
        }
        Text(runtime.translate('将在浏览器中打开授权页面，完成授权后自动返回。'))
          .fontSize(this.typography().captionSize).fontColor(this.theme().muted).textAlign(TextAlign.Center)
        Text(runtime.translate('或使用另一台设备扫码授权')).fontSize(this.typography().smallSize)
          .fontColor(this.theme().muted)
        Row({ space: 12 }) {
          Button(runtime.translate('GitHub 扫码')).layoutWeight(1).enabled(!this.state.busy)
            .onClick(() => { runtime.perform('qr', JSON.stringify({ server: this.server, provider: 'github' })).catch(() => {}) })
          Button(runtime.translate('知乎扫码')).layoutWeight(1).enabled(!this.state.busy)
            .onClick(() => { runtime.perform('qr', JSON.stringify({ server: this.server, provider: 'zhihu' })).catch(() => {}) })
        }
        if (this.state.qrUrl) {
          QRCode(this.state.qrUrl).width(220).height(220).backgroundColor(Color.White).color(Color.Black)
          Text(runtime.translate('使用另一台设备扫描并完成授权')).fontSize(this.typography().smallSize)
          Button(runtime.translate('取消扫码')).onClick(() => { this.invoke('cancelQr') })
        }
        Text(runtime.translate('凭据保存在鸿蒙安全资产中。聊天内容不写入本地存储。'))
          .fontSize(this.typography().captionSize).fontColor(this.theme().muted).textAlign(TextAlign.Center)
      }.padding(24).constraintSize({ maxWidth: 560 }).width('100%')
    }.layoutWeight(1).width('100%')
  }

  @Builder
  trust() {
    Column({ space: 20 }) {
      Text(runtime.translate('确认主机身份')).fontSize(this.typography().titleSize)
        .lineHeight(this.typography().titleLineHeight).fontWeight(FontWeight.Bold)
      Text(this.state.candidate.name).fontSize(this.typography().headingSize + 2)
      Text(runtime.translate('请在电脑端核对指纹，确认这是你要连接的主机。'))
        .fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight).textAlign(TextAlign.Center)
      Text(this.state.candidate.fingerprint).fontSize(this.typography().heroSize).fontWeight(FontWeight.Bold)
        .fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
      Text(runtime.translate(this.state.candidate.trusted ? '已保存此主机身份' : '首次信任后，公钥改变将阻止连接'))
        .fontSize(this.typography().smallSize).fontColor(this.theme().muted)
      if (!this.state.candidate.online) {
        Text(runtime.translate('主机当前离线。请在电脑端打开 DeepSeek Harness 与 DSH Remote 插件，再重试连接。'))
          .fontSize(this.typography().smallSize).fontColor(this.theme().danger).textAlign(TextAlign.Center)
      }
      Button(runtime.translate(this.state.candidate.trusted ? '连接主机' : '指纹一致，信任并连接'))
        .backgroundColor(this.state.accentColor).enabled(!this.state.busy)
        .onClick(() => { this.invoke('trustHost', this.state.candidate.id) })
      Row({ space: 10 }) {
        Button(runtime.translate('解除这台主机的绑定')).layoutWeight(1).backgroundColor(Color.Transparent).fontColor(this.theme().danger)
          .enabled(!this.state.busy).onClick(() => { this.confirmForget = true })
        Button(runtime.translate('重命名主机')).layoutWeight(1).enabled(!this.state.busy && this.rename.trim().length > 0)
          .onClick(() => { runtime.perform('renameHost', JSON.stringify({ id: this.state.candidate.id, name: this.rename } as ActionInput)).catch(() => {}) })
      }.width('100%')
      if (this.confirmForget) {
        Text(runtime.translate('解除后会从账号中移除这台设备并断开连接，需要在电脑端重新绑定。'))
          .fontSize(12).fontColor(this.theme().muted).textAlign(TextAlign.Center)
        Row({ space: 10 }) {
          Button(runtime.translate('确认解除')).layoutWeight(1).backgroundColor(this.theme().danger).fontColor(Color.White)
            .onClick(() => { runtime.perform('forgetHost', JSON.stringify({ id: this.state.candidate.id } as ActionInput)).catch(() => {}); this.confirmForget = false })
          Button(runtime.translate('返回')).layoutWeight(1).backgroundColor(this.theme().surfaceStrong)
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
          Button(this.backendLabel(tab)).fontSize(this.typography().smallSize).height(34).flexShrink(0)
            .backgroundColor(this.state.backend === tab.id ? this.theme().primarySoft : this.theme().surfaceStrong)
            .fontColor(this.state.backend === tab.id ? this.theme().primary : this.theme().ink)
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
        .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
        .onClick(() => { this.send('groupMode', { mode: this.state.groupBy === 'workspace' ? 'list' : 'workspace' }) })
      Button(runtime.translate(this.state.orderBy === 'updated' ? '最近更新' : '手动排序')).fontSize(12).height(30)
        .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
        .onClick(() => { this.send('sortMode', { mode: this.state.orderBy === 'updated' ? 'manual' : 'updated' }) })
      Button(this.archiveLabel()).fontSize(12).height(30)
        .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
        .onClick(() => { this.send('archiveFilter', { mode: this.nextArchiveFilter() }) })
      Blank()
      Text(runtime.translate(`已归档 ${this.state.archivedCount}`)).fontSize(11).fontColor(this.theme().muted)
    }.width('100%').padding({ left: 16, right: 16 })
  }

  @Builder
  /** Android keeps the cross-workspace session list in a right-anchored drawer. */
  drawer(persistent: boolean = false) {
    Row() {
      if (!persistent) Column().layoutWeight(1).height('100%').backgroundColor(this.theme().modalBackdrop).onClick(() => { this.closeDrawer() })
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text(this.hostName()).fontSize(this.typography().headingSize + 2)
            .lineHeight(this.typography().headingLineHeight + 4).fontWeight(FontWeight.Bold)
            .fontColor(this.theme().ink).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .onClick(() => { this.closeDrawer() })
          Button('⟳').accessibilityText(runtime.translate('刷新')).fontSize(16).width(36).height(36).padding(0).flexShrink(0)
            .backgroundColor(this.theme().elevated).borderRadius(999).border({ width: 1, color: this.theme().separator })
            .fontColor(this.theme().muted).enabled(!this.state.busy).onClick(() => { this.invoke('catalog') })
          Button('✕').accessibilityText(runtime.translate('关闭')).fontSize(16).width(36).height(36).padding(0).flexShrink(0)
            .backgroundColor(this.theme().elevated).borderRadius(999).border({ width: 1, color: this.theme().separator })
            .fontColor(this.theme().muted).onClick(() => { this.closeDrawer() })
        }.width('100%').padding({ left: 20, right: 16, top: 16, bottom: 8 })
        Button(runtime.translate('＋ 新建对话')).fontSize(this.typography().bodySize)
          .fontWeight(FontWeight.Medium).height(46).width('92%')
          .backgroundColor(this.state.accentColor).fontColor(this.theme().onPrimary).borderRadius(999)
          .enabled(!this.state.busy && this.state.connected)
          .onClick(() => { this.closeDrawer(); this.invoke('newSession') })
        // Android pins 插件 and 自动化任务 between the new-session button and the backend tabs.
        Row({ space: 12 }) {
          Text('🧩').fontSize(16).width(24).textAlign(TextAlign.Center).fontColor(this.theme().ink)
          Text(runtime.translate('插件')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).layoutWeight(1).fontColor(this.theme().ink)
          Text('›').fontSize(16).fontColor(this.theme().muted)
        }.width('92%').height(44).padding({ left: 12, right: 12 })
          .backgroundColor(this.theme().surfaceStrong).borderRadius(16)
          .onClick(() => { this.closeDrawer(); this.openPlugins() })
        Row({ space: 12 }) {
          Text('⏰').fontSize(16).width(24).textAlign(TextAlign.Center).fontColor(this.theme().ink)
          Text(runtime.translate('自动化任务')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).layoutWeight(1).fontColor(this.theme().ink)
          Text('›').fontSize(16).fontColor(this.theme().muted)
        }.width('92%').height(44).padding({ left: 12, right: 12 })
          .backgroundColor(this.theme().surfaceStrong).borderRadius(16)
          .onClick(() => { this.closeDrawer(); this.openTasks() })
        Row({ space: 12 }) {
          Text('🤖').fontSize(16).width(24).textAlign(TextAlign.Center).fontColor(this.theme().ink)
          Text(runtime.translate('Bot 团队')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).layoutWeight(1).fontColor(this.theme().ink)
          Text('›').fontSize(16).fontColor(this.theme().muted)
        }.width('92%').height(44).padding({ left: 12, right: 12 })
          .backgroundColor(this.theme().surfaceStrong).borderRadius(16)
          .onClick(() => { this.closeDrawer(); this.openBots() })
        Row({ space: 12 }) {
          Text('🌐').fontSize(16).width(24).textAlign(TextAlign.Center).fontColor(this.theme().ink)
          Text(runtime.translate('网络与链路')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).layoutWeight(1).fontColor(this.theme().ink)
          Text('›').fontSize(16).fontColor(this.theme().muted)
        }.width('92%').height(44).padding({ left: 12, right: 12 })
          .backgroundColor(this.theme().surfaceStrong).borderRadius(16)
          .onClick(() => { this.closeDrawer(); this.openNetwork() })
        Row({ space: 12 }) {
          Text('⚙').fontSize(16).width(24).textAlign(TextAlign.Center).fontColor(this.theme().ink)
          Text(runtime.translate('设置')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).layoutWeight(1).fontColor(this.theme().ink)
          Text('›').fontSize(16).fontColor(this.theme().muted)
        }.width('92%').height(44).padding({ left: 12, right: 12 })
          .backgroundColor(this.theme().surfaceStrong).borderRadius(16)
          .onClick(() => { this.closeDrawer(); this.settingsPage = ''; this.showSettings = true })
        this.backendTabs()
        Row({ space: 4 }) {
          Text(runtime.translate('工作区')).fontSize(this.typography().bodySize)
            .lineHeight(this.typography().bodyLineHeight).fontWeight(FontWeight.Medium).layoutWeight(1)
          Button('🔍').fontSize(14).width(32).height(32).backgroundColor(Color.Transparent)
            .fontColor(this.drawerSearch ? this.state.accentColor : this.theme().muted)
            .onClick(() => { this.drawerSearch = !this.drawerSearch })
          Button('⚙').fontSize(14).width(32).height(32).backgroundColor(Color.Transparent)
            .fontColor(this.drawerOptions ? this.state.accentColor : this.theme().muted)
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
                Text(row.expanded ? '⌄' : '›').fontSize(15).width(18).flexShrink(0).fontColor(this.theme().muted)
                Column({ space: 2 }) {
                  Text(row.name).width('100%').fontSize(this.typography().bodySize)
                    .fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.description).width('100%').fontSize(this.typography().captionSize)
                    .fontColor(this.theme().muted).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(row.meta).fontSize(this.typography().captionSize).flexShrink(0).fontColor(this.theme().muted)
                if (row.target.length > 0) {
                  Button(row.favorite ? '★' : '☆').fontSize(17).width(36).height(36).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
                    .fontColor(row.favorite ? this.theme().warning : this.theme().muted)
                    .onClick(() => { this.send('favorite', { id: row.target }) })
                }
              }.width('100%').padding({ left: 12, right: 6, top: 10, bottom: 10 })
                .backgroundColor(this.theme().surfaceStrong).borderRadius(14)
            }.onClick(() => { this.send('toggleGroup', { id: row.id }) })
          } else if (row.kind === 'more') {
            ListItem() {
              Text(row.name).fontSize(this.typography().smallSize).fontColor(this.state.accentColor)
                .width('100%').padding(12).textAlign(TextAlign.Center)
            }.onClick(() => { this.send('showMore', { id: row.target }) })
          } else {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text(row.name).width('100%').fontSize(this.typography().bodySize)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontWeight(row.selected ? FontWeight.Bold : FontWeight.Normal)
                  Text(`${row.description}${row.meta.length > 0 ? ' · ' + row.meta : ''}`)
                    .width('100%').fontSize(this.typography().captionSize).fontColor(this.theme().muted)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (row.selected) { Text(runtime.translate('当前')).fontSize(this.typography().captionSize).fontColor(this.state.accentColor) }
                Button(runtime.translate('归档')).fontSize(this.typography().smallSize).height(30).backgroundColor(Color.Transparent)
                  .fontColor(this.theme().muted)
                  .onClick(() => { this.send('archive', { id: row.id }) })
              }.width('100%').padding({ left: 16, right: 8, top: 12, bottom: 12 })
                .backgroundColor(this.theme().card).borderRadius(16)
            }.enabled(!this.state.busy).onClick(() => { this.closeDrawer(); this.invoke('session', row.id) })
          }
        }, (row: OverviewRow) => `${row.id}|${row.kind}|${row.name}|${row.description}|${row.meta}`
          + `|${row.expanded}|${row.hidden}|${row.favorite}|${row.selected}|${row.remaining}`)
        if (this.state.overview.length === 0 && !this.state.busy && !this.state.error) {
          ListItem() { Text(runtime.translate('这台主机还没有可见会话。')).padding(24).fontColor(this.theme().muted) }
        }
        }.layoutWeight(1).width('100%').padding({ left: 12, right: 12 })
      }.width(persistent ? 320 : '100%').height('100%').alignItems(HorizontalAlign.Start)
        .backgroundColor(this.theme().background)
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
      Row({ space: 6 }) {
        Text(child.kind === 'more' ? '…' : '☰').fontSize(13).width(20).flexShrink(0).fontColor(this.theme().muted)
        Column({ space: 2 }) {
          Text(child.name).fontSize(14).lineHeight(18).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if (child.kind !== 'more') Text(child.description + ' · ' + child.meta).fontSize(11).lineHeight(15).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.theme().muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.padding({ left: 26, right: 10, top: 8, bottom: 8 }).width('100%')
        .accessibilityText(child.name).onClick(() => { this.send(child.kind === 'more' ? 'showMore' : 'session', { id: child.kind === 'more' ? child.target : child.id }) })
    }, (child: OverviewRow) => `${child.id}|${child.name}|${child.meta}`)
  }
  @Builder
  legacyCatalog() {
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
        Text(this.state.account).fontSize(12).fontColor(this.theme().muted)
        List({ space: 10 }) {
          ForEach(this.state.devices.filter((row: DeviceRow) => row.name.toLowerCase().includes(this.query.toLowerCase())), (row: DeviceRow) => {
            ListItem() {
              Column({ space: 8 }) {
                Text(row.name).fontSize(19).fontWeight(FontWeight.Medium).width('100%')
                Text(row.description + (row.trusted ? ' · 已信任' : ' · 待核对指纹')).fontSize(13).width('100%')
                  .fontColor(row.online ? this.theme().success : this.theme().muted)
              }.padding(20).width('100%').backgroundColor(this.theme().card).borderRadius(20)
            }.enabled(!this.state.busy).onClick(() => { this.invoke(row.trusted ? 'connect' : 'inspectHost', row.id) })
          }, (row: DeviceRow) => `${row.id}|${row.name}|${row.description}|${row.online}|${row.trusted}`)
          if (!this.state.busy && this.state.devices.length === 0 && !this.state.error) {
            ListItem() { Text(runtime.translate('没有已授权主机。请先在电脑端登录同一账号。')).padding(24) }
          }
        }.padding({ left: 16, right: 16 }).layoutWeight(1).width('100%')
        Button(runtime.translate('退出本机账号')).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
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
                  Text(row.description).fontSize(12).width('100%').fontColor(this.theme().muted).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).ellipsisMode(EllipsisMode.CENTER)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  .onClick(() => { if (this.state.view === 'workspaces') this.toggleWorkspace(row.id); else this.invoke('session', row.id) })
                if (this.state.view === 'workspaces') {
                  Text(`${row.count}`).fontSize(12).flexShrink(0).fontColor(this.theme().muted)
                  Button('+').width(34).height(38).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
                    .fontColor(this.state.accentColor).accessibilityText(runtime.translate('在此工作区新建对话')).enabled(!this.state.busy)
                    .onClick(() => { this.send('newSessionIn', { id: row.id }) })
                  // Fixed icon hit areas must not inherit the Button text padding.
                  Button(row.favorite ? '★' : '☆').accessibilityText(runtime.translate(row.favorite ? '取消收藏' : '收藏工作区')).fontSize(18).width(38).height(38).padding(0).flexShrink(0)
                    .backgroundColor(Color.Transparent).fontColor(row.favorite ? this.theme().warning : this.theme().muted)
                    .onClick(() => { this.send('favorite', { id: row.id }) })
                  Button('⋮').accessibilityText(runtime.translate('管理工作区')).fontSize(18).width(34).height(38).padding(0).flexShrink(0).backgroundColor(Color.Transparent)
                    .fontColor(this.theme().muted)
                    .onClick(() => { this.manageTarget = row; this.workspaceName = row.name; this.confirmDelete = '' })
                } else {
                  Button(runtime.translate('归档')).fontSize(12).height(32).backgroundColor(Color.Transparent)
                    .fontColor(this.theme().muted)
                    .onClick(() => { this.send('archive', { id: row.id }) })
                }
              }.padding({ left: 16, right: 10, top: 14, bottom: 14 }).width('100%')
                .backgroundColor(this.theme().card).borderRadius(20).alignItems(VerticalAlign.Center)
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
          Button(runtime.translate('＋ 新建对话')).backgroundColor(this.state.accentColor).enabled(!this.state.busy && this.state.connected)
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
  homeModeSwitcher() {
    Row({ space: 3 }) {
      Button('▦  智能体').layoutWeight(1).height(36)
        .fontSize(13).fontWeight(this.homeMode() === 'agent' ? FontWeight.Bold : FontWeight.Medium)
        .backgroundColor(this.homeMode() === 'agent' ? this.theme().surface : Color.Transparent)
        .fontColor(this.homeMode() === 'agent' ? this.accentColor() : this.theme().muted)
        .borderRadius(999)
        .onClick(() => { if (this.homeMode() !== 'agent') this.send('agentHome', {}) })
      Button('◫  DS-Bot').layoutWeight(1).height(36)
        .fontSize(13).fontWeight(this.homeMode() === 'bot' ? FontWeight.Bold : FontWeight.Medium)
        .backgroundColor(this.homeMode() === 'bot' ? this.theme().surface : Color.Transparent)
        .fontColor(this.homeMode() === 'bot' ? this.accentColor() : this.theme().muted)
        .borderRadius(999)
        .onClick(() => { if (this.homeMode() !== 'bot') this.send('botHome', {}) })
    }.width('100%').padding(3).backgroundColor(this.theme().surfaceStrong).borderRadius(999)
  }

  @Builder
  homeHostFooter() {
    Row({ space: 6 }) {
      Button('▣').accessibilityText(runtime.translate('主机信息')).fontSize(19).width(48).height(48).padding(0)
        .backgroundColor(Color.Transparent).fontColor(this.theme().ink)
        .onClick(() => { this.showHostSwitcher = true; this.invoke('refresh') })
      Row({ space: 9 }) {
        Column({ space: 2 }) {
          Text(this.hostName()).fontSize(15).lineHeight(20).fontWeight(FontWeight.Medium)
            .fontColor(this.theme().ink).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            Text('●').fontSize(8).fontColor(this.state.connected ? this.theme().success : this.theme().muted)
            Text(runtime.translate(this.state.connected ? '在线' : this.state.recovering ? '正在恢复' : '离线'))
              .fontSize(12).lineHeight(16).fontColor(this.theme().muted).maxLines(1)
          }.width('100%')
        }.layoutWeight(1)
        Text('⌃⌄').fontSize(13).fontColor(this.theme().muted)
      }.layoutWeight(1).height(50).padding({ left: 8, right: 8 }).borderRadius(16)
        .onClick(() => { this.showHostSwitcher = true; this.invoke('refresh') })
      Button('⚙').accessibilityText(runtime.translate('设置')).fontSize(20).width(46).height(46).padding(0)
        .backgroundColor(this.theme().elevated).fontColor(this.theme().ink).borderRadius(999)
        .border({ width: 1, color: this.theme().separator })
        .onClick(() => { this.settingsPage = ''; this.showSettings = true })
    }.width('100%').height(76 + this.bottomSafeHeight)
      .padding({ left: 8, right: 16, top: 8, bottom: 8 + this.bottomSafeHeight })
      .backgroundColor(this.theme().background)
      .border({ width: { top: 1 }, color: this.theme().separator })
  }

  @Builder
  workspaceHomeCard(row: CatalogRow) {
    Column() {
      Row({ space: 8 }) {
        Text(this.workspaceExpanded(row.id) ? '▰' : '▱')
          .fontSize(18).width(24).textAlign(TextAlign.Center)
          .fontColor(this.workspaceExpanded(row.id) ? this.accentColor() : this.theme().muted)
        Text(row.name).fontSize(15).lineHeight(20).fontWeight(FontWeight.Medium)
          .fontColor(this.theme().ink).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (row.count > 0) {
          Text(`${row.count}`).fontSize(11).fontColor(this.theme().muted)
            .backgroundColor(this.theme().surfaceStrong).padding({ left: 6, right: 6, top: 1, bottom: 1 }).borderRadius(999)
        }
        Button('+').accessibilityText(runtime.translate('在此工作区新建对话')).fontSize(18).width(30).height(34).padding(0)
          .backgroundColor(Color.Transparent).fontColor(this.theme().muted).enabled(!this.state.busy)
          .onClick(() => { this.send('newSessionIn', { id: row.id }) })
        Button('⋮').accessibilityText(runtime.translate('管理工作区')).fontSize(18).width(30).height(34).padding(0)
          .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
          .onClick(() => { this.manageTarget = row; this.workspaceName = row.name; this.confirmDelete = '' })
        Text(this.workspaceExpanded(row.id) ? '⌄' : '›').fontSize(16).fontColor(this.theme().subtle)
      }.width('100%').height(50).padding({ left: 12, right: 8 })
        .onClick(() => { this.toggleWorkspace(row.id) })
      if (this.workspaceExpanded(row.id)) {
        Divider().color(this.theme().separator).margin({ left: 42, right: 12 })
        this.workspaceSessions(row.id)
      }
    }.width('100%').backgroundColor(this.theme().card).borderRadius(18)
      .border({ width: 1, color: this.theme().separator })
      .gesture(LongPressGesture({ repeat: false }).onAction(() => {
        this.manageTarget = row; this.workspaceName = row.name; this.confirmDelete = ''
      }))
  }

  @Builder
  homeCatalog() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 8 }) {
        this.homeModeSwitcher()
        if (this.state.recovering) {
          Text(runtime.translate('正在恢复')).fontSize(12).fontColor(this.theme().warning).width('100%').padding({ top: 6 })
        }
        Column() {
          Row({ space: 10 }) {
            Text('▣').fontSize(18).width(26).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('智能体平台')).fontSize(15).layoutWeight(1).fontColor(this.theme().ink)
            Text(this.homeBackendName()).fontSize(13).fontColor(this.theme().muted).maxLines(1)
            Text(this.homeBackendOpen ? '⌄' : '›').fontSize(17).fontColor(this.theme().subtle)
          }.width('100%').height(50).padding({ left: 12, right: 10 })
            .onClick(() => { this.homeBackendOpen = !this.homeBackendOpen })
          if (this.homeBackendOpen) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.state.backends, (tab: BackendTab) => {
                  Button(this.backendLabel(tab)).fontSize(13).height(36)
                    .backgroundColor(this.state.backend === tab.id ? this.theme().primarySoft : this.theme().surfaceStrong)
                    .fontColor(this.state.backend === tab.id ? this.accentColor() : this.theme().ink).borderRadius(999)
                    .onClick(() => { this.send('backend', { backend: tab.id }); this.homeBackendOpen = false })
                }, (tab: BackendTab) => `${tab.id}|${tab.count}|${this.state.backend === tab.id ? 'on' : 'off'}`)
              }.padding({ left: 46, right: 10, bottom: 10 })
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          }
          this.settingsDivider()
          Row({ space: 10 }) {
            Text('⬡').fontSize(18).width(26).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('插件')).fontSize(15).layoutWeight(1).fontColor(this.theme().ink)
            Text('›').fontSize(17).fontColor(this.theme().subtle)
          }.width('100%').height(50).padding({ left: 12, right: 10 })
            .onClick(() => { this.openPlugins() })
          this.settingsDivider()
          Row({ space: 10 }) {
            Text('◷').fontSize(17).width(26).textAlign(TextAlign.Center).fontColor(this.theme().ink)
            Text(runtime.translate('自动化任务')).fontSize(15).layoutWeight(1).fontColor(this.theme().ink)
            Text('›').fontSize(17).fontColor(this.theme().subtle)
          }.width('100%').height(50).padding({ left: 12, right: 10 })
            .onClick(() => { this.openTasks() })
        }.width('100%').backgroundColor(this.theme().grouped).borderRadius(22)
          .border({ width: 1, color: this.theme().separator })

        Row({ space: 1 }) {
          Text(runtime.translate('工作区')).fontSize(14).fontColor(this.theme().muted).layoutWeight(1)
          Button('⌕').accessibilityText(runtime.translate('搜索')).fontSize(17).width(34).height(34).padding(0)
            .backgroundColor(Color.Transparent).fontColor(this.drawerSearch ? this.accentColor() : this.theme().muted)
            .onClick(() => { this.drawerSearch = !this.drawerSearch; if (!this.drawerSearch) this.query = '' })
          Button('☷').accessibilityText(runtime.translate('视图选项')).fontSize(17).width(34).height(34).padding(0)
            .backgroundColor(Color.Transparent).fontColor(this.drawerOptions ? this.accentColor() : this.theme().muted)
            .onClick(() => { this.drawerOptions = !this.drawerOptions })
          Button('▱+').accessibilityText(runtime.translate('新建工作区')).fontSize(15).width(38).height(34).padding(0)
            .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
            .onClick(() => { this.showWorkspaceCreator = !this.showWorkspaceCreator })
        }.width('100%').padding({ top: 2 })
        if (this.drawerSearch) {
          TextInput({ text: this.query, placeholder: runtime.translate('搜索工作区或会话') })
            .height(38).fontSize(13).fontColor(this.theme().ink).placeholderColor(this.theme().muted)
            .backgroundColor(this.theme().surfaceStrong).borderRadius(999)
            .onChange((value: string) => { this.query = value })
        }
        if (this.drawerOptions) { this.viewOptions() }
        List({ space: 6 }) {
          ForEach(this.state.workspaces.filter((row: CatalogRow) =>
            (row.name + row.description).toLowerCase().includes(this.query.trim().toLowerCase())),
          (row: CatalogRow) => {
            ListItem() { this.workspaceHomeCard(row) }
          }, (row: CatalogRow) => `${row.id}|${row.name}|${row.description}|${row.count}|${row.favorite}|${this.workspaceExpanded(row.id)}|${this.workspaceChildren(row.id).map((child: OverviewRow): string => child.id + child.name + child.meta).join(';')}`)
          if (!this.state.busy && this.state.workspaces.length === 0 && !this.state.error) {
            ListItem() {
              Column({ space: 6 }) {
                Text('▱').fontSize(28).fontColor(this.theme().subtle)
                Text(runtime.translate('当前主机没有可用工作区')).fontSize(15).fontColor(this.theme().ink)
                Text(runtime.translate('点击右上角文件夹按钮创建新的 Harness 工作区')).fontSize(12).fontColor(this.theme().muted)
              }.width('100%').padding(28)
            }
          }
        }.layoutWeight(1).width('100%').padding({ bottom: 16 })
        if (this.showWorkspaceCreator) {
          Row({ space: 8 }) {
            TextInput({ text: this.directory, placeholder: runtime.translate('Harness 新工作区的绝对路径') }).layoutWeight(1)
              .height(42).fontSize(13).fontColor(this.theme().ink).placeholderColor(this.theme().muted)
              .backgroundColor(this.theme().surfaceStrong).borderRadius(16)
              .onChange((value: string) => { this.directory = value })
            Button(runtime.translate('创建')).height(42).fontSize(14)
              .backgroundColor(this.accentColor()).fontColor(this.theme().onPrimary).borderRadius(999)
              .enabled(!this.state.busy && this.directory.trim().length > 0)
              .onClick(() => {
                runtime.perform('newWorkspace', JSON.stringify({ path: this.directory })).then((ok: boolean) => {
                  if (ok) { this.directory = ''; this.showWorkspaceCreator = false }
                }).catch(() => {})
              })
          }.width('100%').padding({ top: 4 })
        }
      }.width('100%').height('100%').padding({ left: 16, right: 16, bottom: 76 + this.bottomSafeHeight })
      this.homeHostFooter()
    }.width('100%').layoutWeight(1)
  }

  @Builder
  devicesCatalog() {
    Column({ space: 12 }) {
      TextInput({ text: this.query, placeholder: runtime.translate('搜索主机') }).height(44)
        .fontColor(this.theme().ink).placeholderColor(this.theme().muted).backgroundColor(this.theme().surfaceStrong).borderRadius(999)
        .onChange((value: string) => { this.query = value })
      Text(this.state.account).fontSize(12).fontColor(this.theme().muted).width('100%')
      List({ space: 10 }) {
        ForEach(this.state.devices.filter((row: DeviceRow) => row.name.toLowerCase().includes(this.query.toLowerCase())), (row: DeviceRow) => {
          ListItem() {
            Column({ space: 8 }) {
              Text(row.name).fontSize(18).fontWeight(FontWeight.Medium).width('100%').fontColor(this.theme().ink)
              Text(row.description + (row.trusted ? ' · 已信任' : ' · 待核对指纹')).fontSize(13).width('100%')
                .fontColor(row.online ? this.theme().success : this.theme().muted)
            }.padding(18).width('100%').backgroundColor(this.theme().card).borderRadius(20)
              .border({ width: 1, color: this.theme().separator })
          }.enabled(!this.state.busy).onClick(() => { this.invoke(row.trusted ? 'connect' : 'inspectHost', row.id) })
        }, (row: DeviceRow) => `${row.id}|${row.name}|${row.description}|${row.online}|${row.trusted}`)
        if (!this.state.busy && this.state.devices.length === 0 && !this.state.error) {
          ListItem() { Text(runtime.translate('没有已授权主机。请先在电脑端登录同一账号。')).padding(24).fontColor(this.theme().muted) }
        }
      }.layoutWeight(1).width('100%')
      Button(runtime.translate('退出本机账号')).height(44).width('100%')
        .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
        .onClick(() => { this.invoke('logout') })
    }.width('100%').layoutWeight(1).padding(16)
  }

  @Builder
  catalog() {
    if (this.state.view === 'devices') {
      this.devicesCatalog()
    } else {
      this.homeCatalog()
    }
  }

  @Builder
  chat() {
    Column() {
      if (this.state.modelWarning) { Text(this.state.modelWarning).fontSize(11).fontColor(this.theme().muted).padding(8) }
      if (this.traceMode) { this.traceControls() }
      List({ space: 8, scroller: this.scroller }) {
        if (this.state.hasMore) {
          ListItem() { Button(runtime.translate('加载更早消息')).enabled(!this.state.busy).onClick(() => { this.invoke('history') }) }
        }
        ForEach(this.state.botExtras, (row: BotExtra) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(row.title).fontSize(13).width('100%')
              if (row.view && row.view.length > 0) LocalSurface({ kind: 'bot', payload: row.view, onAction: async (): Promise<boolean> => false })
              else LocalSurface({ kind: 'markdown', scope: this.state.sessionKey, dark: (getContext(this) as common.UIAbilityContext).config.colorMode === 0,
                payload: JSON.stringify({ text: row.text, density: this.state.typographyDensity, appearance: JSON.parse(this.state.chatAppearance), dark: (getContext(this) as common.UIAbilityContext).config.colorMode === 0 }),
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
              TraceEntry({
                row: row, label: this.categoryLabel(row.category),
                dark: this.darkMode(), accent: this.accentPreset(),
                appearance: this.state.chatAppearance, density: this.state.typographyDensity,
                onFork: this.forkRow, onFeedback: this.rateRow,
              })
            } else {
              TimelineCard({ row: row, scope: this.state.sessionKey, dark: this.darkMode(), density: this.state.typographyDensity, appearance: this.state.chatAppearance, accent: this.state.accentColor, onFork: this.forkRow, onFeedback: this.rateRow,
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
          Text(runtime.translate('送达结果未确认：' + row.error)).fontSize(12).fontColor(this.theme().danger).width('100%')
          Row({ space: 12 }) {
            Button(runtime.translate('重新发送')).enabled(this.state.connected && !this.state.busy).onClick(() => {
              promptAction.showDialog({ title: '确认重新发送', message: '主机可能已收到原消息。重新发送可能产生重复任务，是否继续？', buttons: [{ text: '取消', color: this.theme().muted }, { text: '重新发送', color: this.state.accentColor }] }).then((result: promptAction.ShowDialogSuccessResponse) => { if (result.index === 1) this.send('retrySend', { id: row.id, enabled: true }) })
            })
            Button(runtime.translate('移除')).onClick(() => { this.send('dismissSend', { id: row.id }) })
          }
        }.padding(10).width('100%')
        }
      }, (row: FailedSend) => row.id)
        if (!this.traceMode && this.state.rows.length === 0 && this.state.botExtras.length === 0 && !this.state.busy) {
          ListItem() {
            Column({ space: 10 }) {
              Text(runtime.translate('预览版')).fontSize(11).lineHeight(15).fontWeight(FontWeight.Medium)
                .fontColor(this.state.accentColor).padding({ left: 12, right: 12, top: 3, bottom: 3 })
                .backgroundColor(this.theme().surfaceStrong).borderRadius(10)
              Text(this.welcomeTitle()).fontSize(this.typography().titleSize).lineHeight(this.typography().titleLineHeight)
                .fontWeight(FontWeight.Bold).fontColor(this.theme().ink)
              Text(this.welcomeBody()).fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight)
                .fontColor(this.theme().muted)
                .textAlign(TextAlign.Center)
              Text(this.policyHint()).fontSize(this.typography().captionSize).lineHeight(this.typography().captionLineHeight)
                .fontColor(this.theme().muted).textAlign(TextAlign.Center)
            }.width('100%').padding({ left: 26, right: 26, top: 40, bottom: 24 })
              .alignItems(HorizontalAlign.Center)
          }
        }
        if (this.traceMode && this.state.rows.length > 0 && this.traceRows().length === 0) {
          ListItem() { Text(runtime.translate('没有匹配的已加载轨迹')).padding(24).fontColor(this.theme().muted) }
        }
        if (!this.traceMode && this.state.rows.length === 0 && this.state.botExtras.length === 0 && !this.state.busy) {
          ListItem() { Text(runtime.translate('继续电脑上的工作，或发送第一条消息。')).padding(24).fontColor(this.theme().muted) }
        }
      }.layoutWeight(1).width('100%').padding({ left: 16, right: 16, top: 8 })
        .onScrollIndex((start: number) => { this.firstVisibleRow = start })
        .onScrollStart(() => { if (!this.restoringReading) this.pinnedToBottom = false })
        .onScrollStop(() => { this.saveReadingPosition() })
        .onAreaChange(() => { this.restoreReadingPosition() })
      Column({ space: 8 }) {
        if (this.state.botTarget.length > 0) {
          if (this.state.botReadOnly.length > 0) Text(this.state.botReadOnly).fontSize(12).fontColor(this.theme().muted).width('100%')
          Row({ space: 8 }) {
            Button(runtime.translate('更早记录')).height(36).fontSize(12)
              .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
              .onClick(() => { this.invoke('botEarlier') })
            Button(runtime.translate('刷新智能体')).height(36).fontSize(12)
              .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
              .onClick(() => { this.invoke('botRefresh') })
            Button(runtime.translate('旁问')).height(36).fontSize(12)
              .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
              .enabled(this.state.botReadOnly.length === 0).onClick(() => { this.draft = '/btw ' + this.draft })
          }.width('100%')
        }
        if (this.state.children.length > 0) {
          Button(runtime.translate(`智能体团队 ${this.state.children.length}`)).height(44).width('100%')
            .fontSize(14).fontColor(this.theme().ink).backgroundColor(Color.Transparent).borderRadius(18)
            .border({ width: 1, color: this.theme().separator })
            .onClick(() => { this.showChildren = true })
        }
        if (this.state.activityDockMode === 'cards') {
          Column({ space: 8 }) {
            ForEach(this.state.activity.rows.slice(0, 6), (row: ActivityRow) => {
              Text(row.title + ' · ' + row.status).fontSize(13).width('100%').padding(12)
                .backgroundColor(this.theme().surface).borderRadius(16)
                .border({ width: 1, color: this.theme().separator })
                .onClick(() => { this.alignmentPanel = 'activity' })
            }, (row: ActivityRow) => row.id + '|' + row.status)
            Button(runtime.translate('全部活动')).height(38).fontSize(12).width('100%')
              .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
              .onClick(() => { this.alignmentPanel = 'activity' })
          }.width('100%')
        }
        if (this.state.activityDockMode === 'compact' && (this.state.activity.rows.length > 0 || this.state.activity.jobs.length > 0)) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(['todos', 'goal', 'team', 'subagents'], (category: string) => {
                if (this.state.activity.rows.some((row: ActivityRow) => row.category === category)) {
                  Button(runtime.translate(category === 'todos' ? '待办' : category === 'goal' ? '目标' : category === 'team' ? '团队' : '子任务') + ' ' + this.state.activity.rows.filter((row: ActivityRow) => row.category === category && row.status === 'completed').length + '/' + this.state.activity.rows.filter((row: ActivityRow) => row.category === category).length)
                    .fontSize(11).height(34).padding({ left: 12, right: 12 })
                    .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().muted).borderRadius(999)
                    .onClick(() => { this.alignmentPanel = 'activity' })
                }
              }, (category: string) => category)
              if (this.state.activity.jobs.length > 0) {
                Button(runtime.translate('后台任务') + ' ' + this.state.activity.jobs.filter((job: JobRow) => job.status === 'running').length)
                  .fontSize(11).height(34).padding({ left: 12, right: 12 })
                  .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().muted).borderRadius(999)
                  .onClick(() => { this.alignmentPanel = 'activity' })
              }
            }
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }
        if (this.state.compactionStatus.length > 0) {
          Row({ space: 8 }) {
            Text(this.state.compactionStatus).fontSize(12).fontColor(this.theme().muted).layoutWeight(1)
            if (this.state.compactionCancellable) {
              Button(runtime.translate('取消压缩')).height(34).fontSize(12)
                .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
                .onClick(() => { this.send('cancelCompaction', {}) })
            }
          }.width('100%').padding({ left: 4, right: 4 })
        }
        ForEach(this.state.stagedFiles, (file: StagedFile) => {
          Row({ space: 8 }) {
            Text('📄').fontSize(15)
            Text(file.name).fontSize(12).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('✕').accessibilityText(runtime.translate('移除')).fontSize(13).width(30).height(30).padding(0)
              .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
              .onClick(() => { this.send('removeFile', { id: file.id }) })
          }.width('100%').padding({ left: 10, right: 6, top: 6, bottom: 6 })
            .backgroundColor(this.theme().surfaceStrong).borderRadius(14)
        }, (file: StagedFile) => file.id)
        ForEach(this.promptImages, (image: PromptAttachment, index: number) => {
          Row({ space: 8 }) {
            Image(`data:${image.mediaType};base64,${image.data}`).width(38).height(38).objectFit(ImageFit.Cover).borderRadius(10)
            Text(runtime.translate(`图片 ${index + 1}`)).fontSize(12).layoutWeight(1)
            Button('✕').accessibilityText(runtime.translate('移除')).fontSize(13).width(30).height(30).padding(0)
              .backgroundColor(Color.Transparent).fontColor(this.theme().muted)
              .onClick(() => { this.promptImages = this.promptImages.filter((row: PromptAttachment, at: number) => at !== index); this.image = this.promptImages[0]?.data ?? '' })
          }.width('100%').padding({ left: 8, right: 6, top: 6, bottom: 6 })
            .backgroundColor(this.theme().surfaceStrong).borderRadius(14)
        }, (image: PromptAttachment, index: number) => String(index) + image.data.slice(0, 32))
        if (this.state.botTarget.length > 0 && this.draft.lastIndexOf('@') >= 0 && !this.draft.slice(this.draft.lastIndexOf('@')).includes(' ')) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.state.botDefinitions.filter((bot: BotDefinition) => bot.name.toLowerCase().startsWith(this.draft.slice(this.draft.lastIndexOf('@') + 1).toLowerCase())), (bot: BotDefinition) => {
                Button('@' + bot.name).fontSize(12).height(34).backgroundColor(this.theme().surfaceStrong)
                  .onClick(() => { this.draft = this.draft.slice(0, this.draft.lastIndexOf('@')) + '@' + bot.name + ' '; this.send('saveDraft', { id: this.state.sessionKey, text: this.draft }) })
              }, (bot: BotDefinition) => bot.id)
            }
          }.scrollable(ScrollDirection.Horizontal).width('100%')
        }
        if (this.imageError) {
          Text(this.imageError).fontSize(12).fontColor(this.theme().danger).width('100%').padding(10)
            .backgroundColor(this.theme().dangerSoft).borderRadius(12)
        }
        if (this.state.queue.length > 0) {
          Column({ space: 6 }) {
            Text(runtime.translate(`排队中 ${this.state.queue.length} 条消息`)).fontSize(12).fontColor(this.theme().muted).width('100%')
            ForEach(this.state.queue, (item: QueueRow) => {
              Row({ space: 8 }) {
                Text(item.preview).fontSize(13).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(runtime.translate('等待执行')).fontSize(11).fontColor(this.theme().muted)
                if (item.id.length > 0) {
                  Button(runtime.translate('立即发送')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor(this.state.accentColor)
                    .onClick(() => { this.send('queueAction', { id: item.id, mode: 'steer' }) })
                  Button(runtime.translate('移出队列')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor(this.theme().muted)
                    .onClick(() => { this.send('queueAction', { id: item.id, mode: 'remove' }) })
                }
              }.width('100%')
            }, (item: QueueRow) => `${item.id}|${item.preview}`)
          }.padding({ left: 12, right: 12, top: 10, bottom: 10 }).width('100%')
            .backgroundColor(this.theme().surface).borderRadius(16)
            .border({ width: 1, color: this.theme().separator })
        }
        if (this.state.uploadProgress.length > 0) {
          Row({ space: 8 }) {
            Text(this.state.uploadProgress).fontSize(12).fontColor(this.theme().muted).layoutWeight(1).maxLines(2)
            Button(runtime.translate('取消')).height(30).fontSize(11).backgroundColor(Color.Transparent).fontColor(this.theme().danger)
              .onClick(() => { this.send('cancelUpload', {}) })
          }.width('100%').padding({ left: 4, right: 4 })
        }
        if (this.state.running) {
          Row({ space: 8 }) {
            LoadingProgress().width(16).height(16).color(this.accentColor())
            Text(runtime.translate('主机正在回复')).fontSize(12).fontColor(this.accentColor()).layoutWeight(1)
            Button(runtime.translate('停止')).height(34).fontSize(12)
              .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
              .onClick(() => { this.invoke('interrupt') })
          }.width('100%').padding({ left: 4, right: 4 })
        }
        Column({ space: 6 }) {
          if (this.showModels) {
            Column({ space: 10 }) {
              Text(runtime.translate('模型')).fontSize(13).lineHeight(18).fontWeight(FontWeight.Medium)
                .fontColor(this.theme().muted).width('100%')
              Scroll() {
                Column({ space: 4 }) {
                  ForEach(this.state.models, (model: ModelRow, index: number) => {
                    Row({ space: 8 }) {
                      Text(model.name).fontSize(13).lineHeight(18).layoutWeight(1).maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .fontColor(this.selectedModel === index ? this.accentColor() : this.theme().ink)
                      if (this.selectedModel === index) {
                        Text('✓').fontSize(14).fontColor(this.accentColor())
                      }
                    }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
                      .backgroundColor(this.selectedModel === index ? this.theme().primarySoft : this.theme().surfaceStrong)
                      .borderRadius(12)
                      .accessibilityText(model.name)
                      .onClick(() => { this.selectedModel = index; this.effort = '' })
                  }, (model: ModelRow, index: number) => `${model.id}|${this.selectedModel === index ? 'selected' : 'idle'}`)
                }.width('100%')
              }.width('100%').constraintSize({ maxHeight: 206 }).scrollBar(BarState.Auto)
              if (this.state.models[this.selectedModel]?.efforts.length > 0) {
                Column({ space: 6 }) {
                  Text(runtime.translate('思考强度')).fontSize(13).lineHeight(18).fontWeight(FontWeight.Medium)
                    .fontColor(this.theme().muted).width('100%')
                  Scroll() {
                    Row({ space: 6 }) {
                      ForEach(this.state.models[this.selectedModel].efforts, (item: ModelEffort) => {
                        Button(item.name).height(34).fontSize(13).padding({ left: 12, right: 12 })
                          .backgroundColor(this.effort === item.id ? this.theme().primarySoft : this.theme().surfaceStrong)
                          .fontColor(this.effort === item.id ? this.accentColor() : this.theme().ink)
                          .borderRadius(999).onClick(() => { this.effort = item.id })
                      }, (item: ModelEffort) => `${item.id}|${this.effort === item.id ? 'selected' : 'idle'}`)
                    }
                  }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                }.width('100%')
              }
              Row({ space: 8 }) {
                Button(runtime.translate('取消')).layoutWeight(1).height(38).fontSize(13)
                  .backgroundColor(this.theme().surfaceStrong).fontColor(this.theme().ink).borderRadius(999)
                  .onClick(() => { this.showModels = false })
                Button(runtime.translate('应用')).layoutWeight(1).height(38).fontSize(13)
                  .backgroundColor(this.accentColor()).fontColor(this.theme().onPrimary).borderRadius(999)
                  .onClick(() => {
                    const model: ModelRow = this.state.models[this.selectedModel]
                    if (model) runtime.perform('model', JSON.stringify({ provider: model.provider, model: model.model, effort: this.effort })).catch(() => {})
                    this.showModels = false
                  })
              }.width('100%')
            }.width('100%').padding(12).backgroundColor(this.theme().background).borderRadius(16)
          }
          TextArea({ text: this.draft, placeholder: runtime.translate('输入消息…') })
            .height(this.expandedComposer ? 220 : (this.state.running ? 54 : 68)).width('100%')
            .fontSize(this.typography().bodySize).lineHeight(this.typography().bodyLineHeight + 2)
            .fontColor(this.theme().ink).placeholderColor(this.theme().subtle)
            .backgroundColor(Color.Transparent).padding({ left: 3, right: 3, top: 5, bottom: 3 })
            .onChange((value: string) => { this.draft = value; runtime.perform('saveDraft', JSON.stringify({ id: this.lastSession, text: value })).catch(() => {}) })
          Row({ space: 7 }) {
            Button('＋').accessibilityText(runtime.translate('更多操作')).width(36).height(36).padding(0).fontSize(21)
              .fontColor(this.theme().ink).backgroundColor(this.theme().surfaceStrong).borderRadius(18)
              .onClick(() => { this.openMore() }).enabled(!this.state.busy && this.state.connected)
            Button('⚡').accessibilityText(runtime.translate('快捷提示词')).width(36).height(36).padding(0).fontSize(16)
              .fontColor(this.theme().ink).backgroundColor(this.theme().surfaceStrong).borderRadius(18)
              .enabled(!this.state.busy && this.state.connected).onClick(() => { this.openPrompts() })
            if (this.state.models.length > 0) {
              Button(this.state.models[this.selectedModel]?.name ?? runtime.translate('模型'))
                .layoutWeight(1).height(36).padding({ left: 12, right: 8 }).fontSize(13)
                .fontColor(this.theme().muted).backgroundColor(Color.Transparent).borderRadius(999)
                .enabled(!this.state.running && !this.state.busy)
                .onClick(() => { this.showModels = !this.showModels })
            } else {
              Blank()
            }
            Button(this.expandedComposer ? '⌄' : '⤢').accessibilityText(runtime.translate(this.expandedComposer ? '收起输入' : '展开输入'))
              .width(32).height(36).padding(0).fontSize(16).fontColor(this.theme().muted).backgroundColor(Color.Transparent)
              .onClick(() => { this.expandedComposer = !this.expandedComposer })
            Button('↑').accessibilityText(runtime.translate('发送')).width(38).height(38).padding(0).fontSize(21).fontWeight(FontWeight.Medium)
              .backgroundColor(this.state.connected && !this.state.busy && (this.draft.trim().length > 0 || this.image.length > 0 || this.state.stagedFiles.length > 0) ? this.accentColor() : this.theme().surfaceStrong)
              .fontColor(this.state.connected && !this.state.busy && (this.draft.trim().length > 0 || this.image.length > 0 || this.state.stagedFiles.length > 0) ? this.theme().onPrimary : this.theme().subtle)
              .borderRadius(19)
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
        }.padding({ left: 10, right: 10, top: 8, bottom: 8 }).width('100%')
          .backgroundColor(this.theme().surface).border({ width: 1, color: this.theme().separator })
          .borderRadius(22).shadow({ radius: 10, color: this.theme().separator, offsetX: 0, offsetY: 3 })
        Text(this.policyHint()).fontSize(10).lineHeight(14).fontColor(this.theme().subtle).textAlign(TextAlign.Center).width('100%')
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: Math.max(8, this.bottomSafeHeight + 8) })
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
        Text(this.state.error || this.state.notice).fontSize(13).fontColor(this.state.error ? this.theme().danger : this.theme().warning)
          .width('100%').padding(12).backgroundColor(this.theme().surfaceStrong)
      }
      if (this.state.busy) { Progress({ value: 35, total: 100, type: ProgressType.Linear }).width('100%').color(this.state.accentColor) }
        if (this.state.view === 'login') { this.login() }
        else if (this.state.view === 'trust') { this.trust() }
        else if (this.state.view === 'chat') { this.chat() }
        else if (this.state.view === 'botHome') { this.botSheet() }
        else { this.catalog() }
        }.layoutWeight(1).backgroundColor(this.theme().background)
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
          Button(runtime.translate('设置')).onClick(() => { this.showHostSwitcher = false; this.settingsPage = ''; this.showSettings = true })
        }.padding(20).width('100%').backgroundColor(this.theme().background).borderRadius({ topLeft: 28, topRight: 28 })
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
