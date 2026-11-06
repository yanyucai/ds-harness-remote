export const notificationsRecord = {
  published: [] as Array<{ id: number; title: string; text: string; slotType?: number }>,
  cancelled: [] as number[],
  enabled: true,
  requestCount: 0,
  reset() {
    this.published = []
    this.cancelled = []
    this.enabled = true
    this.requestCount = 0
  },
}

export enum SlotType {
  UNKNOWN_TYPE = 0,
  SOCIAL_COMMUNICATION = 1,
  SERVICE_INFORMATION = 2,
  CONTENT_INFORMATION = 3,
  LIVE_VIEW = 4,
  CUSTOMER_SERVICE = 5,
  OTHER_TYPES = 0xFFFF,
}

export enum ContentType {
  NOTIFICATION_CONTENT_BASIC_TEXT = 0,
  NOTIFICATION_CONTENT_LONG_TEXT = 1,
  NOTIFICATION_CONTENT_PICTURE = 2,
  NOTIFICATION_CONTENT_CONVERSATION = 3,
}

export default {
  SlotType,
  ContentType,
  isNotificationEnabled: async () => notificationsRecord.enabled,
  isNotificationEnabledSync: () => notificationsRecord.enabled,
  requestEnableNotification: async () => {
    notificationsRecord.requestCount++
    notificationsRecord.enabled = true
  },
  publish: async (request: { id: number; content: { normal?: { title?: string; text?: string } }; notificationSlotType?: number }) => {
    notificationsRecord.published.push({
      id: request.id,
      title: request.content.normal?.title ?? '',
      text: request.content.normal?.text ?? '',
      slotType: request.notificationSlotType,
    })
  },
  cancel: async (id: number) => {
    notificationsRecord.cancelled.push(id)
  },
}
