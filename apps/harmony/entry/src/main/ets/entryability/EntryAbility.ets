import UIAbility from '@ohos.app.ability.UIAbility'
import window from '@ohos.window'
import Want from '@ohos.app.ability.Want'
import AbilityConstant from '@ohos.app.ability.AbilityConstant'
import { runtime } from '../RuntimeHost'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    runtime.attachContext(this.context)
    if (want?.parameters?.sessionId) {
      runtime.handleNotificationNavigation(
        (want.parameters.hostId as string) ?? '',
        (want.parameters.sessionId as string) ?? ''
      ).catch(() => {})
    }
    const shared: string = (want?.parameters?.['ohos.extra.param.key.text'] as string) ?? ''
    if (typeof shared === 'string' && shared.length > 0) runtime.stageSharedText(shared)
    if (want?.uri) {
      runtime.handleDeepLink(want.uri).catch(() => {})
    }
  }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want?.parameters?.sessionId) {
      runtime.handleNotificationNavigation(
        (want.parameters.hostId as string) ?? '',
        (want.parameters.sessionId as string) ?? ''
      ).catch(() => {})
    }
    const shared: string = (want?.parameters?.['ohos.extra.param.key.text'] as string) ?? ''
    if (typeof shared === 'string' && shared.length > 0) runtime.stageSharedText(shared)
    if (want?.uri) {
      runtime.handleDeepLink(want.uri).catch(() => {})
    }
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    // Favorites, recents and view options live in preferences, never the asset vault.
    runtime.attachContext(this.context)
    try { stage.loadContent('pages/Index') } catch { console.error('DSH Remote: UI initialization failed.') }
  }
  onBackground(): void {
    // The resident task keeps the carrier alive while hidden, mirroring the
    // Android foreground service; approvals and streams stay pending.
    runtime.onBackground().catch(() => {})
  }
  onForeground(): void {
    // Android reconnects the remembered host on foreground; same bounded rules.
    runtime.onForeground().catch(() => {})
  }
  onDestroy(): void { runtime.dispose().catch(() => {}) }
}
