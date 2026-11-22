import fs from '@ohos.file.fs'
import { uploadFileReaderToWorkspace, workspaceUploadMaxBytes, type RpcCaller } from '../../../packages/app-core/src/screens/chat-files'
import { createNativeRpcId } from '../../../packages/app-core/src/services/rpc-id'
export async function uploadFile(
  rpc: (method: string, args: unknown, signal?: AbortSignal) => Promise<unknown>,
  sessionId: string, name: string, data: string, current: () => boolean, signal: AbortSignal,
): Promise<string> {
  if (!name || name.length > 255 || /[\\/\u0000]/.test(name) || !/^[A-Za-z0-9+/]+={0,2}$/.test(data) || data.length > 28*1024*1024) throw new Error('附件名称或内容无效。')
  const raw = atob(data), totalBytes = raw.length
  if (!totalBytes || totalBytes > 20*1024*1024) throw new Error('附件超过 20 MiB 限制。')
  const uploadId = createNativeRpcId()
  const active = () => { if (signal.aborted || !current()) throw new Error('上传已取消。') }
  let committed = false
  try {
    active(); await rpc('workspace.upload.open', { sessionId, uploadId, name, totalBytes }, signal)
    for(let offset=0;offset<totalBytes;offset+=64*1024) {
      active(); await rpc('workspace.upload.chunk', { sessionId, uploadId, offset, data:btoa(raw.slice(offset,offset+64*1024)) }, signal)
    }
    active()
    const result = await rpc('workspace.upload.commit', {sessionId, uploadId}, signal) as {path?:unknown}
    active()
    if(typeof result?.path !== 'string' || !result.path) throw new Error('主机未确认上传结果，请检查后重试。')
    committed=true;return result.path
  } finally {
    if(!committed) {
      const control = new AbortController(), timer=setTimeout(()=>control.abort(),5000)
      try { if(current()) await rpc('workspace.upload.abort',{sessionId,uploadId},control.signal) } catch {} finally { clearTimeout(timer) }
    }
  }
}


/** Keep native picker files on disk; only one negotiated chunk is read at a time. */
export async function uploadNativeFile(rpc: RpcCaller, sessionId: string, name: string, uri: string,
  current: () => boolean, signal: AbortSignal, mode?: string,
  progress?: (bytes: number, total: number) => void): Promise<string> {
  if (!uri.startsWith('file://')) throw new Error('请选择系统文件选择器中的文件。')
  const file = await fs.open(uri, fs.OpenMode.READ_ONLY)
  let handedOff = false
  try {
    const stat = await fs.stat(file.fd)
    if (stat.size <= 0 || stat.size > workspaceUploadMaxBytes(mode)) throw new Error('文件超过当前传输通道的大小限制。')
    const active = () => { signal.throwIfAborted(); if (!current()) throw new Error('会话已切换，附件上传已取消。') }
    const guarded: RpcCaller = (method, args, abort) => { if (method === 'workspace.upload.abort') { if (!current()) throw new Error('上传连接已变化。') } else active(); return rpc(method, args, abort) }
    guarded.supportsBinaryUpload = rpc.supportsBinaryUpload
    handedOff = true
    const result = await uploadFileReaderToWorkspace(guarded, sessionId, { id: '', name, uri, size: stat.size }, {
      totalBytes: stat.size,
      async read(offset, length) {
        active()
        const now = await fs.stat(file.fd)
        if (now.size !== stat.size || now.mtime !== stat.mtime) throw new Error('上传期间文件发生变化，请重新选择。')
        const buffer = new ArrayBuffer(length)
        const count = await fs.read(file.fd, buffer, { offset, length })
        active()
        return new Uint8Array(buffer, 0, count)
      },
      close: () => fs.close(file.fd),
    }, signal, progress)
    active(); return result.path
  } finally { if (!handedOff) await fs.close(file.fd) }
}
