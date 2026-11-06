import type { SessionTools } from '../../android/src/services/session-tools'
import { loadWorkspaceDownload } from '../../android/src/services/workspace-file-preview'

/** Read only through the existing authenticated, version-checked file protocol. */
export class DownloadTask {
  private controller?: AbortController
  cancel(): void { this.controller?.abort(); this.controller = undefined }
  async run(tools: SessionTools, session: string, path: string, current: () => boolean,
    write: (bytes: Uint8Array) => Promise<void>, progress: (bytes: number) => void): Promise<void> {
    this.cancel()
    const controller = this.controller = new AbortController()
    let bytes = 0
    const active = () => { if (controller.signal.aborted || !current()) throw new Error('文件下载已取消') }
    try {
      active()
      await loadWorkspaceDownload(tools, session, path, async chunk => {
        active(); await write(chunk); active(); bytes += chunk.byteLength; progress(bytes)
      }, controller.signal)
      active()
    } finally { if (this.controller === controller) this.controller = undefined }
  }
}
