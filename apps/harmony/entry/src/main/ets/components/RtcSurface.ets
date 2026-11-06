import webview from '@ohos.web.webview'
import { runtime } from '../RuntimeHost'
class RtcNativeBridge { post(raw: string): void { runtime.receiveRtcBridge(raw) } }
@Component
export struct RtcSurface {
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: RtcNativeBridge = new RtcNativeBridge()
  build() {
    Web({ src: $rawfile('rtc.html'), controller: this.controller })
      .javaScriptAccess(true).fileAccess(false).domStorageAccess(false).databaseAccess(false)
      .javaScriptProxy({ object: this.bridge, name: 'rtcNative', methodList: ['post'], controller: this.controller })
      .onPageEnd(() => {
        runtime.attachRtcBridge(async (raw: string) => { await this.controller.runJavaScript(`window.rtcCommand(${raw});`) })
      })
      .onOverrideUrlLoading((request: WebResourceRequest) => !request.getRequestUrl().startsWith('resource://'))
      .onConsole(() => true)
      .width(1).height(1).opacity(0.01).hitTestBehavior(HitTestMode.None)
  }
}
