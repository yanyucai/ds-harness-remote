// Native HarmonyOS notification dispatcher for background task completion and approval prompts.
import notificationManager from '@ohos.notificationManager'
import wantAgent from '@ohos.app.ability.wantAgent'
import common from '@ohos.app.ability.common'

export function hashString(str: string): number {
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i)
    hash |= 0
  }
  return Math.abs(hash) || 1
}

export async function isNotificationsEnabled(): Promise<boolean> {
  try {
    return await notificationManager.isNotificationEnabled()
  } catch {
    return false
  }
}

export async function requestNotificationPermission(context: Object | undefined): Promise<boolean> {
  if (context === undefined) return false
  try {
    const ability = context as common.UIAbilityContext
    await notificationManager.requestEnableNotification(ability)
    return await notificationManager.isNotificationEnabled()
  } catch (error) {
    console.warn(`DSH Remote: requestEnableNotification failed (${String((error as { code?: unknown }).code ?? error)}).`)
    return false
  }
}

export async function publishTaskNotification(
  context: Object | undefined,
  hostId: string,
  sessionId: string,
  title: string,
  body: string,
): Promise<void> {
  try {
    if (!await isNotificationsEnabled()) return
    const ability = context as common.UIAbilityContext | undefined
    const info = ability?.abilityInfo
    const bundleName = info?.bundleName ?? 'io.github.dshremote.harmony'
    const abilityName = info?.name ?? 'EntryAbility'
    const id = hashString(JSON.stringify([hostId, sessionId])) % 2000000000

    let agent: object | undefined
    try {
      agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName,
          abilityName,
          parameters: { hostId, sessionId },
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: id,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      })
    } catch {
      agent = undefined
    }

    const request: notificationManager.NotificationRequest = {
      id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title.slice(0, 100),
          text: body,
        },
      },
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      wantAgent: agent as object,
    }

    await notificationManager.publish(request)
    console.info('DSH Remote: task notification published.')
  } catch (error) {
    console.warn(`DSH Remote: publishTaskNotification failed (${String((error as { code?: unknown }).code ?? error)}).`)
  }
}

const ACTIVITY_ID = 2147483000
export interface ActivityNotification { hostId: string; sessionId: string; title: string; status: string; summary: string; updatedAt: number }
let revision = 0
let latest = '\u0000initial'
let tail: Promise<void> = Promise.resolve()
/** Serial native writes prevent a slow publish from resurrecting a cleared task. */
export function updateActivityNotification(context: Object | undefined, task?: ActivityNotification): void {
  const key = task ? JSON.stringify(task) : ''
  if (key === latest) return
  latest = key
  const ticket = ++revision
  tail = tail.then(async () => {
    if (ticket !== revision) return
    if (!task) { await notificationManager.cancel(ACTIVITY_ID).catch(() => {}); return }
    if (!context || !await isNotificationsEnabled() || ticket !== revision) return
    const ability = context as common.UIAbilityContext
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: ability.abilityInfo.bundleName, abilityName: ability.abilityInfo.name,
        parameters: { hostId: task.hostId, sessionId: task.sessionId } }],
      operationType: wantAgent.OperationType.START_ABILITY, requestCode: ACTIVITY_ID,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    })
    if (ticket !== revision) return
    await notificationManager.publish({ id: ACTIVITY_ID, notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: true, isAlertOnce: true, tapDismissed: false, deliveryTime: task.updatedAt || Date.now(),
      content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: task.title.slice(0,100), text: task.status, additionalText: task.summary.slice(0,240) } }, wantAgent: agent,
    })
  }).catch(() => { if (ticket === revision) latest = '\u0000retry' })
}

export async function cancelTaskNotification(hostId: string, sessionId: string): Promise<void> {
  try { await notificationManager.cancel(hashString(JSON.stringify([hostId, sessionId])) % 2000000000) }
  catch { /* Notification may already be dismissed. */ }
}
