// Records resident-task requests so tests can assert keep-alive semantics.
export const resident = { started: 0, stopped: 0, mode: 0 }
export const BackgroundMode = {
  DATA_TRANSFER: 1, AUDIO_PLAYBACK: 2, AUDIO_RECORDING: 3, LOCATION: 4,
  BLUETOOTH_INTERACTION: 5, MULTI_DEVICE_CONNECTION: 6, VOIP: 8, TASK_KEEPING: 9,
}
let onCancel: () => void = () => {}
export function cancelResident(): void { onCancel() }
export default {
  on: (_event: string, callback: () => void) => { onCancel = callback },
  BackgroundMode,
  startBackgroundRunning: async (_context: unknown, mode: number, _agent: unknown): Promise<void> => {
    resident.started += 1
    resident.mode = mode
  },
  stopBackgroundRunning: async (_context: unknown): Promise<void> => { resident.stopped += 1 },
}
