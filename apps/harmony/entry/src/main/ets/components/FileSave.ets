import common from '@ohos.app.ability.common'
import fs from '@ohos.file.fs'
import picker from '@ohos.file.picker'
import cryptoFramework from '@ohos.security.cryptoFramework'
import { runtime } from '../RuntimeHost'

/** User picks the destination only after the complete source passed validation. */
export async function saveWorkspaceFile(context: common.UIAbilityContext, path: string, current: () => boolean): Promise<string> {
  const nonce: string = Array.from(cryptoFramework.createRandom().generateRandomSync(16).data).join('-')
  const temporary: string = `${context.cacheDir}/workspace-download-${nonce}`
  try {
    const file: fs.File = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    try {
      await runtime.downloadWorkspaceFile(path, async (bytes: Uint8Array): Promise<void> => {
        const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
        if (await fs.write(file.fd, buffer) !== bytes.byteLength) throw new Error('文件写入不完整')
      })
    } finally { await fs.close(file.fd) }
    if (!current()) throw new Error('会话已切换，文件下载已取消')
    const name: string = path.split(/[\\/]/).pop() || 'download'
    const destinations: string[] = await new picker.DocumentViewPicker(context).save({ newFileNames: [name] })
    if (!destinations.length) return ''
    if (!current()) throw new Error('会话已切换，文件保存已取消')
    const destination: fs.File = await fs.open(destinations[0], fs.OpenMode.WRITE_ONLY)
    try { await fs.copyFile(temporary, destination.fd) } finally { await fs.close(destination.fd) }
    return destinations[0]
  } finally { try { await fs.unlink(temporary) } catch {} }
}
