import webview from '@ohos.web.webview'
import url from '@ohos.url'
import { runtime } from '../RuntimeHost'

interface DshWebPayload {
  url: string
  browserGrant: string
  expiresAt: number
  lan: boolean
}

@Component
export struct DshWebView {
  @Prop @Watch('configure') payload: string = '{}'
  @Prop surfaceColor: string = '#FFFFFF'
  @Prop ink: string = '#171717'
  @Prop muted: string = '#59606D'
  @Prop accent: string = '#4D6BFE'
  onReady: () => void = () => {}
  onRetry: () => void = () => {}
  @State loaded: boolean = false
  @State failed: boolean = false
  private controller: webview.WebviewController = new webview.WebviewController()
  private attached: boolean = false
  private loading: boolean = false
  private timer: number = -1

  aboutToAppear(): void {
    this.configure()
  }

  aboutToDisappear(): void {
    clearTimeout(this.timer)
    this.timer = -1
  }

  private value(): DshWebPayload | undefined {
    try {
      const value: DshWebPayload = JSON.parse(this.payload) as DshWebPayload
      if (!value.url || value.browserGrant.length !== 43 || value.expiresAt <= Date.now()) return undefined
      const parsed: url.URL = url.URL.parseURL(value.url)
      if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') || parsed.pathname !== '/') return undefined
      return value
    } catch {
      return undefined
    }
  }

  private bootstrap(value: DshWebPayload): string {
    return '<!doctype html><meta name="referrer" content="same-origin">'
      + '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; form-action \'self\'">'
      + '<form method="post" action="/__remote/session"><input type="hidden" name="browserGrant" value="'
      + value.browserGrant + '"></form><script>document.forms[0].submit()</script>'
  }

  private configure(): void {
    clearTimeout(this.timer)
    this.timer = -1
    this.loaded = false
    this.failed = false
    this.loading = false
    this.load()
  }

  private load(): void {
    if (!this.attached || this.loading || this.loaded) return
    const value: DshWebPayload | undefined = this.value()
    if (!value) {
      this.failed = true
      return
    }
    this.loading = true
    this.timer = setTimeout(() => {
      if (!this.loaded) {
        this.loading = false
        this.failed = true
      }
    }, 20000)
    try {
      this.controller.loadData(this.bootstrap(value), 'text/html', 'UTF-8', value.url, value.url)
    } catch {
      clearTimeout(this.timer)
      this.loading = false
      this.failed = true
    }
  }

  private sameOrigin(value: DshWebPayload, candidate: string): boolean {
    try {
      return url.URL.parseURL(candidate).origin === url.URL.parseURL(value.url).origin
    } catch {
      return false
    }
  }

  private fail(): void {
    if (this.loaded) return
    clearTimeout(this.timer)
    this.timer = -1
    this.loading = false
    this.failed = true
  }

  build() {
    Column() {
      if (this.failed) {
        Column({ space: 14 }) {
          Text('⚠').fontSize(30).fontColor(this.muted)
          Text(runtime.translate('无法打开 DSH Web')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink)
          Text(runtime.translate('请确认电脑端 DSH Web 已开启且当前网络能够访问主机。'))
            .fontSize(13).lineHeight(19).fontColor(this.muted).textAlign(TextAlign.Center)
          Button(runtime.translate('重试')).height(42).padding({ left: 24, right: 24 })
            .backgroundColor(this.accent).fontColor(Color.White).borderRadius(999)
            .onClick(() => { this.failed = false; this.loaded = false; this.loading = false; this.onRetry() })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(28)
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Web({ src: 'about:blank', controller: this.controller })
            .javaScriptAccess(true).domStorageAccess(true).databaseAccess(true).fileAccess(false)
            .mixedMode(MixedMode.None).cacheMode(CacheMode.Online)
            .backgroundColor(this.surfaceColor)
            .onControllerAttached(() => {
              this.attached = true
              this.load()
            })
            .onPageEnd((event: OnPageEndEvent) => {
              const value: DshWebPayload | undefined = this.value()
              if (!value) { this.fail(); return }
              try {
                const current: url.URL = url.URL.parseURL(event.url)
                if (current.origin !== url.URL.parseURL(value.url).origin) { this.fail(); return }
                if (current.pathname === '/') {
                  clearTimeout(this.timer)
                  this.timer = -1
                  this.loading = false
                  this.loaded = true
                  this.failed = false
                  this.onReady()
                } else if (current.pathname === '/__remote/session' || current.pathname === '/__remote/session-bootstrap') {
                  this.fail()
                }
              } catch {
                this.fail()
              }
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              if (event.request.isMainFrame()) this.fail()
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
              if (event.request.isMainFrame() && event.response.getResponseCode() >= 400) this.fail()
            })
            .onOverrideUrlLoading((request: WebResourceRequest) => {
              const candidate: string = request.getRequestUrl()
              if (candidate === 'about:blank') return false
              const value: DshWebPayload | undefined = this.value()
              if (value && this.sameOrigin(value, candidate)) return false
              if (/^(?:https?|mailto):/i.test(candidate)) {
                runtime.perform('openLink', JSON.stringify({ text: candidate })).catch(() => {})
              }
              return true
            })
            .onConsole(() => false)
            .width('100%').height('100%')
          if (!this.loaded) {
            Column({ space: 12 }) {
              LoadingProgress().width(28).height(28).color(this.accent)
              Text(runtime.translate('正在验证访问并加载页面…')).fontSize(13).fontColor(this.muted)
            }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(this.surfaceColor)
          }
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(this.surfaceColor)
  }
}
