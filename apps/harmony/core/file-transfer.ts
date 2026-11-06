import { createNativeRpcId } from '../../android/src/services/rpc-id'
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
