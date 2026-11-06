let clipboardText = ''
const systemPasteboard = {
  async setData(record: { text: string }): Promise<void> { clipboardText = record.text },
  async getData(): Promise<{ text: string }> { return { text: clipboardText } },
}
const pasteboard = {
  MIMETYPE_TEXT_PLAIN: 'text/plain',
  createData(_mime: string, text: string) { return { text } },
  getSystemPasteboard() { return systemPasteboard },
}
export default pasteboard
