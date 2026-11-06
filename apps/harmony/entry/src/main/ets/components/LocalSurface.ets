import { runtime } from '../RuntimeHost'
import webview from '@ohos.web.webview'
import promptAction from '@ohos.promptAction'
import cryptoFramework from '@ohos.security.cryptoFramework'

class SurfaceBridge {
  handle: (raw: string) => void = () => {}
  post(raw: string): void { if (raw.length < 1024 * 1024) this.handle(raw) }
}
interface TerminalPayload { data?: string; chunk?: string; reset?: boolean; enabled?: boolean; scope?: string; revision?: number }
interface SurfaceMessage { replyId?: number; viewId?: string; type: string; path?: string; stamp?: number; data?: string; text?: string; url?: string; height?: number; cols?: number; rows?: number; id?: number; token?: string; page?: number; pages?: number; zoom?: number }

/** Only bundled documents can access this bridge. Model HTML is never the root page. */
@Component
export struct LocalSurface {
  @Prop kind: string = 'markdown'
  @Prop scope: string = ''
  @Prop dark: boolean = false
  @Prop @Watch('update') payload: string = '{}'
  onAction: (raw: string) => Promise<boolean> = async () => false
  @State contentHeight: number = 120
  @State failure: string = ''
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: SurfaceBridge = new SurfaceBridge()
  private terminalText: string = ''
  private terminalId: number = 0
  private terminalAck: number = 0
  private terminalRevision: number = 0
  private terminalScope: string = ''
  private terminalTimer: number = -1
  private ready: boolean = false
  private revision: number = 0
  private lastRequest: number = -1
  private confirming: boolean = false
  @State pdfPage: number = 1
  @State pdfPages: number = 0
  @State pdfZoom: number = 1
  private token: string = ''

  aboutToAppear(): void {
    try { this.token = Array.from(cryptoFramework.createRandom().generateRandomSync(24).data).join('-') }
    catch { this.failure = '安全随机数暂不可用，请重新打开'; return }
    this.bridge.handle = (raw: string) => {
      try {
        const message: SurfaceMessage = JSON.parse(raw) as SurfaceMessage
        if (this.kind === 'markdown' && message.type === 'image' && message.path) {
          const captured: string = this.payload, scope: string = this.scope
          runtime.readMarkdownImage(message.path, scope).then((uri: string) => { if (this.ready && captured === this.payload && scope === this.scope) this.controller.runJavaScript(`window.__image(${message.stamp},${message.id},${JSON.stringify(uri)});`).catch(() => {}) }).catch(() => {}); return
        }
        if (this.kind === 'markdown' && message.type === 'copy' && message.text) { runtime.perform('copyText', JSON.stringify({ text: message.text })).catch(() => {}); return }
        if (message.type === 'ack' && message.id === this.terminalAck) {
          runtime.acknowledgeTerminalRender(this.terminalScope, this.terminalRevision)
          clearTimeout(this.terminalTimer); this.terminalAck = 0; this.update(); return
        }
        if (message.type === 'rendered' && this.kind === 'pdf') { this.pdfPage = message.page ?? 1; this.pdfPages = message.pages ?? 0; return }
        if (message.type === 'ready') { this.ready = true; this.update(); return }
        if (message.type === 'height' || message.type === 'resize') {
          if (typeof message.height === 'number') this.contentHeight = Math.min(4000, Math.max(60, message.height))
        }
        if (this.kind === 'terminal' && ['data', 'resize', 'ready'].includes(message.type)) this.onAction(raw)
        else if ((this.kind === 'markdown' || this.kind === 'bot') && message.type === 'link' && message.url) this.onAction(raw)
        else if (this.kind === 'intelligent' && message.token === this.token && message.type === 'prompt' && message.text && message.text.length <= 4000) {
          const id: number = message.id ?? -1
          if (this.confirming || id <= this.lastRequest) return
          this.lastRequest = id; this.confirming = true
          const captured: string = this.payload
          void promptAction.showDialog({ title: '发送到当前对话', message: message.text,
            buttons: [{ text: '取消', color: '#888888' }, { text: '发送', color: '#4B78E6' }] })
            .then(async (result: promptAction.ShowDialogSuccessResponse) => {
              const ok: boolean = result.index === 1 && this.ready && this.payload === captured ? await this.onAction(raw) : false
              if (this.ready) this.controller.runJavaScript(`window.__diuiReply&&window.__diuiReply(${id},${ok},"Delivery not confirmed")`).catch(() => {})
            }).finally(() => { this.confirming = false })
        }
        else if (this.kind === 'bot' && message.type === 'botReply' && message.token === this.token) {
          const captured: string = this.scope
          this.onAction(raw).then((ok: boolean) => {
            if (this.ready && this.scope === captured && this.token === message.token) this.controller.runJavaScript(`window.__botReplyResult&&window.__botReplyResult(${JSON.stringify(message.viewId)},${ok},${message.replyId})`).catch(() => {})
          }).catch(() => {
            if (this.ready && this.scope === captured && this.token === message.token) this.controller.runJavaScript(`window.__botReplyResult&&window.__botReplyResult(${JSON.stringify(message.viewId)},false,${message.replyId})`).catch(() => {})
          })
        }
        else if (message.type === 'error') this.failure = '文档暂时无法显示，请重新打开'
      } catch {}
    }
  }
  aboutToDisappear(): void { this.ready = false; clearTimeout(this.terminalTimer); runtime.setTerminalRenderer(this.terminalScope, false); this.bridge.handle = () => {} }
  private update(): void {
    if (!this.ready) return
    try {
      const data: string = this.payload.replace(/</g, '\\u003c')
      let code: string = `window.receive&&window.receive(${data});`
      if (this.kind === 'terminal') { this.updateTerminal(); return }
      if (this.kind === 'pdf') { void this.renderPdf(); return }
      if (this.kind === 'intelligent') code = `window.__diuiSetArtifact&&window.__diuiSetArtifact(${data});`
      this.controller.runJavaScript(code).catch(() => { this.failure = '文档暂时无法显示' })
    } catch { this.failure = '文档暂时无法显示' }
  }
  private updateTerminal(): void {
    if (!this.ready || this.terminalAck !== 0) return
    const value: TerminalPayload = JSON.parse(this.payload) as TerminalPayload
    this.controller.runJavaScript(`window.receive({type:"enabled",value:${value.enabled === true}});`).catch(() => {})
    const text: string = value.data ?? ''
    const scope: string = value.scope ?? ''
    const revision: number = value.revision ?? 0
    runtime.setTerminalRenderer(scope, true)
    if (scope === this.terminalScope && revision === this.terminalRevision && text === this.terminalText) { runtime.acknowledgeTerminalRender(scope, revision); return }
    const reset: boolean = scope !== this.terminalScope || revision === this.terminalRevision || value.reset === true
    const data: string = reset ? text : value.chunk ?? text.slice(this.terminalText.length)
    const id: number = ++this.terminalId
    this.terminalAck = id; this.terminalScope = scope; this.terminalText = text; this.terminalRevision = revision
    this.terminalTimer = setTimeout(() => { if (this.terminalAck === id) { this.failure = '终端渲染确认超时，请重新打开'; this.ready = false; runtime.setTerminalRenderer(scope, false) } }, 10000)
    this.controller.runJavaScript(`window.receive(${JSON.stringify({ type: 'write', id: id, reset: reset, data: data })});`)
      .catch(() => { clearTimeout(this.terminalTimer); this.failure = '终端暂时无法显示'; this.ready = false; runtime.setTerminalRenderer(scope, false) })
  }
  private async renderPdf(): Promise<void> {
    const revision: number = ++this.revision
    const base64: string = JSON.parse(this.payload) as string
    const id: string = String(revision)
    try {
      await this.controller.runJavaScript(`window.beginPdf(${JSON.stringify(id)});`)
      for (let offset: number = 0; offset < base64.length; offset += 32768) {
        if (!this.ready || revision !== this.revision) return
        await this.controller.runJavaScript(`window.appendPdfChunk(${JSON.stringify(id)},${JSON.stringify(base64.slice(offset, offset + 32768))});`)
      }
      if (this.ready && revision === this.revision) await this.controller.runJavaScript(`window.finishPdf(${JSON.stringify(id)});`)
    } catch { if (revision === this.revision) this.failure = 'PDF 暂时无法显示' }
  }
  private source(): Resource {
    if (this.kind === 'bot') return $rawfile('bot.html')
    if (this.kind === 'terminal') return $rawfile('terminal.html')
    if (this.kind === 'pdf') return $rawfile('pdf.html')
    if (this.kind === 'intelligent') return $rawfile('intelligent.html')
    return $rawfile('markdown.html')
  }
  build() {
    Column() {
      if (this.failure) { Text(this.failure).fontSize(12).fontColor('#C64B43') }
      if (this.kind === 'pdf') {
        Row({ space: 10 }) {
          Button('‹').onClick(() => { this.controller.runJavaScript(`window.showPage(${Math.max(1,this.pdfPage-1)})`) })
          Text(`${this.pdfPage}/${this.pdfPages}`).layoutWeight(1)
          Button('›').onClick(() => { this.controller.runJavaScript(`window.showPage(${Math.min(this.pdfPages,this.pdfPage+1)})`) })
          Button('−').onClick(() => { this.pdfZoom = Math.max(0.25,this.pdfZoom/1.25); this.controller.runJavaScript(`window.zoomPdf(${this.pdfZoom})`) })
          Button('+').onClick(() => { this.pdfZoom = Math.min(8,this.pdfZoom*1.25); this.controller.runJavaScript(`window.zoomPdf(${this.pdfZoom})`) })
        }.width('100%')
      }
      Web({ src: this.source(), controller: this.controller })
        .backgroundColor(this.dark ? '#202124' : '#FFFFFF')
        .javaScriptAccess(true).domStorageAccess(false).databaseAccess(false).fileAccess(false)
        .javaScriptProxy({ object: this.bridge, name: 'dshNative', methodList: ['post'], controller: this.controller })
        .onPageEnd(() => {
          if (this.token.length === 0) return
          if (this.kind === 'bot') this.controller.runJavaScript(`window.__setBotToken(${JSON.stringify(this.token)});`).then(() => { this.ready = true; this.update() }).catch(() => {})
          else if (this.kind === 'intelligent') this.controller.runJavaScript(`window.__setDiuiToken&&window.__setDiuiToken(${JSON.stringify(this.token)});`).then(() => { this.ready = true; this.update() }).catch(() => {})
          else { this.ready = true; this.update() }
        })
        .onOverrideUrlLoading((request: WebResourceRequest) => {
          const url: string = request.getRequestUrl()
          return !url.startsWith('resource://') && url !== 'about:blank'
        })
        .onConsole(() => true)
        .width('100%').height(this.kind === 'markdown' || this.kind === 'intelligent' || this.kind === 'bot' ? this.contentHeight : 400)
    }.width('100%')
  }
}
