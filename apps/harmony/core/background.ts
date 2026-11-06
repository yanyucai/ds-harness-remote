import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager'
import wantAgent from '@ohos.app.ability.wantAgent'
import common from '@ohos.app.ability.common'

let resident = false
let wanted = false
let starting: Promise<void> | undefined
let owner: common.UIAbilityContext | undefined
let listening = false
let cancellationVersion = 0
let failure = ''
let changed: () => void = () => {}

export function residentTaskActive(): boolean { return resident }
export function residentTaskError(): string { return failure }
export function observeResidentTask(listener: () => void): void { changed = listener }

/** One reconciler serializes native changes and always converges to the latest intent. */
function reconcile(): Promise<void> {
  if (starting) return starting
  const task = (async () => {
    while (owner && resident !== wanted) {
      const ability = owner
      if (!wanted) {
        try { await backgroundTaskManager.stopBackgroundRunning(ability) }
        catch { /* The system may already have cancelled the task. */ }
        resident = false; failure = ''; changed()
        continue
      }
      try {
        const agent = await wantAgent.getWantAgent({
          wants: [{ bundleName: ability.abilityInfo?.bundleName ?? 'io.github.dshremote.harmony', abilityName: ability.abilityInfo?.name ?? 'EntryAbility' }],
          operationType: wantAgent.OperationType.START_ABILITY, requestCode: 0,
          wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
        })
        if (!wanted) continue
        const cancellation = cancellationVersion
        await backgroundTaskManager.startBackgroundRunning(ability, backgroundTaskManager.BackgroundMode.MULTI_DEVICE_CONNECTION, agent)
        if (cancellation !== cancellationVersion) { resident = false; changed(); break }
        resident = true; failure = ''; changed()
      } catch (error) {
        resident = false
        failure = wanted ? `后台持续任务不可用（${String((error as { code?: unknown }).code ?? 'unknown')}）` : ''
        changed(); break
      }
    }
  })()
  starting = task
  return task.finally(() => { if (starting === task) starting = undefined })
}
export async function startResidentTask(context: Object | undefined): Promise<void> {
  if (!context) return
  owner = context as common.UIAbilityContext
  wanted = true
  if (!listening) {
    try {
      backgroundTaskManager.on('continuousTaskCancel', () => {
        ++cancellationVersion
        resident = false
        failure = wanted ? '后台持续任务已被系统取消，请检查应用后台设置' : ''
        changed()
      })
      listening = true
    } catch { /* Older systems still support the start/stop APIs. */ }
  }
  await reconcile()
}
export async function stopResidentTask(context: Object | undefined): Promise<void> {
  if (context) owner = context as common.UIAbilityContext
  wanted = false
  await reconcile()
  if (!wanted && !resident) { failure = ''; changed() }
}

export async function openAppPowerManagementPage(context: Object | undefined): Promise<void> {
  if (!context) throw new Error('应用设置暂不可用')
  const ability = context as common.UIAbilityContext
  // HarmonyOS NEXT resolves app details through the Settings URI entry.
  // The older action.settings.app.info action is not exported on current devices.
  await ability.startAbility({
    bundleName: 'com.huawei.hmos.settings',
    abilityName: 'com.huawei.hmos.settings.MainAbility',
    uri: 'application_info_entry',
    parameters: { pushParams: ability.abilityInfo.bundleName },
  })
}
