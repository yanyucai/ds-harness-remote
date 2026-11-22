import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { installPlatform, attachPreferences } from '../core/platform'
import { compactionStore, setCompactionOwner } from '../core/compaction-store'
import { prefs, secrets } from './native/state'
import { files, handles } from './native/fs'
import { uploadNativeFile } from '../core/file-transfer'
import { nativeLabels } from '../core/native-labels'
import type { RpcCaller } from '../../../packages/app-core/src/screens/chat-files'

beforeEach(async () => { Object.defineProperty(globalThis,'crypto',{value:globalThis.crypto,writable:true,configurable:true}); prefs.clear(); secrets.clear(); files.clear(); handles.clear(); installPlatform(); await attachPreferences({}) })
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers() })
describe('Harmony native alignment boundaries', () => {
  it('keeps tracked compactions encrypted and isolated across account/Host scopes, including queued writes', async () => {
    setCompactionOwner('server|account-a|host|key')
    const write = compactionStore.save('host',{sessionId:'s',requestId:'private-attempt',state:'running',updatedAt:1})
    setCompactionOwner('server|account-b|host|key')
    await write
    expect(await compactionStore.load('host','s')).toBeUndefined()
    setCompactionOwner('server|account-a|host|key')
    expect((await compactionStore.load('host','s'))?.requestId).toBe('private-attempt')
    expect([...prefs.values()].join('')).not.toContain('private-attempt')
    expect(await compactionStore.load('different-host','s')).toBeUndefined()
  })
  it('uploads native files in negotiated bounded binary chunks and closes the source', async () => {
    const data=Uint8Array.from({length:524301},(_,i)=>i%251)
    files.set('file://fixture.bin',{data,mtime:1})
    const received:number[]=[]
    const rpc:RpcCaller=async(method,raw)=>{
      const args=raw as any
      if(method.endsWith('.open'))return {chunkBytes:262144,encoding:'binary-v1',uploadId:args.uploadId}
      if(method.endsWith('.binary')){expect(args.data).toBeInstanceOf(Uint8Array);expect(args.data.length).toBeLessThanOrEqual(262144);for(const byte of args.data)received.push(byte);return {uploadId:args.uploadId,receivedBytes:args.offset+args.data.length}}
      if(method.endsWith('.commit'))return {path:'./fixture.bin',name:'fixture.bin',bytes:data.length}
      return {}
    }
    rpc.supportsBinaryUpload=true
    expect(await uploadNativeFile(rpc,'s','fixture.bin','file://fixture.bin',()=>true,new AbortController().signal,'LAN')).toBe('./fixture.bin')
    expect(new Uint8Array(received)).toEqual(data);expect(handles.size).toBe(0)
  })
  it('cancels native uploads without committing/replaying and refuses to clean up through a different Host', async () => {
    for(const kind of ['abort','switch','mutation'] as const){
      files.set('file://cancel.bin',{data:new Uint8Array(300000),mtime:1})
      const abort=new AbortController();let current=true;const methods:string[]=[]
      const rpc:RpcCaller=async(method,raw)=>{methods.push(method);const args=raw as any
        if(method.endsWith('.open'))return {chunkBytes:65536,encoding:'binary-v1',uploadId:args.uploadId}
        if(method.endsWith('.binary')){if(kind==='abort')abort.abort();if(kind==='switch')current=false;if(kind==='mutation')files.get('file://cancel.bin')!.mtime++;return {uploadId:args.uploadId,receivedBytes:args.offset+args.data.length}}
        return {}
      };rpc.supportsBinaryUpload=true
      await expect(uploadNativeFile(rpc,'s','cancel.bin','file://cancel.bin',()=>current,abort.signal,'LAN')).rejects.toThrow()
      expect(methods).not.toContain('workspace.upload.commit');expect(handles.size).toBe(0)
      if(kind==='switch')expect(methods).not.toContain('workspace.upload.abort')
      else expect(methods).toContain('workspace.upload.abort')
    }
  })
  it('provides cancellation composition and timeout when the Ark runtime lacks AbortSignal statics', () => {
    vi.useFakeTimers()
    const names=['AbortSignal','AbortController'] as const
    const saved=names.map(name=>Object.getOwnPropertyDescriptor(globalThis,name))
    try {
      for(const name of names)Reflect.deleteProperty(globalThis,name)
      installPlatform()
      const first=new AbortController(), second=new AbortController()
      const merged=AbortSignal.any([first.signal,second.signal])
      second.abort('cancelled');expect(merged.aborted).toBe(true);expect(merged.reason).toBe('cancelled')
      expect(AbortSignal.any([first.signal,second.signal]).aborted).toBe(true)
      const timeout=AbortSignal.timeout(50);vi.advanceTimersByTime(50);expect(timeout.aborted).toBe(true)
      expect(AbortSignal.abort('done').reason).toBe('done')
    } finally { names.forEach((name,index)=>{if(saved[index])Object.defineProperty(globalThis,name,saved[index]!)}) }
  })
  it('ships all six translations for the new appearance and DS-Bot controls', () => {
    const labels=['聊天外观','字号','行距','字距','主题色','气泡','代码配色','恢复默认外观','活动显示','通用偏好','开启思考显示','关闭思考显示','应用工作目录','加载可用模型','默认模型','选择 Bot','询问记忆','计划任务','Agent 引擎（留空使用默认）','私有 Bot','群公告']
    for(const label of labels) {
      expect(nativeLabels[label], label).toHaveLength(6)
      expect(nativeLabels[label].every(Boolean), label).toBe(true)
      expect(nativeLabels[label][0], label).not.toBe(label)
    }
  })
})
