const mockWindow = {
  async setWindowSystemBarEnable(_names: string[]): Promise<void> {},
}
const window = {
  async getLastWindow(_context: unknown): Promise<typeof mockWindow> { return mockWindow },
}
export default window
