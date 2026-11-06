export const OperationType = { START_ABILITY: 0, SEND_MESSAGE: 1 }
export const WantAgentFlags = { UPDATE_PRESENT_FLAG: 1 }
export default {
  OperationType,
  WantAgentFlags,
  getWantAgent: async (_options: unknown): Promise<unknown> => ({ stub: true }),
}
