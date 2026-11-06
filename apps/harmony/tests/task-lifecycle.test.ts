import { afterEach, describe, expect, it, vi } from 'vitest'
import { TaskNotifications, activeTask, type ObservedTask } from '../core/notification-state'
import { DownloadTask } from '../core/download-task'
import { startResidentTask, stopResidentTask, residentTaskActive } from '../core/background'
import nativeBackground from '@ohos.resourceschedule.backgroundTaskManager'
import { cancelResident } from './native/background'
import wantAgent from '@ohos.app.ability.wantAgent'
import type { SessionTools } from '../../android/src/services/session-tools'

const task = (id: string, rest: Partial<ObservedTask> = {}): ObservedTask => ({ id, title: id, watched: true, running: false, inputIds: [], updatedAt: 0, summary: '', ...rest })
afterEach(async () => { await stopResidentTask({}); vi.restoreAllMocks() })

describe('Harmony task observation boundaries', () => {
  it('tracks known transitions and input ids without replaying notices after reset', () => {
    const tracker = new TaskNotifications()
    expect(tracker.observe([task('a',{running:true})], 'a', true, true)).toEqual([])
    expect(tracker.observe([task('a')], 'b', true, true)).toEqual([{id:'a',title:'a',kind:'ended'}])
    const pending = task('a',{inputIds:['q']})
    expect(tracker.observe([pending], 'b', true, true)).toHaveLength(1)
    expect(tracker.observe([pending], 'b', true, true)).toEqual([])
    tracker.reset()
    expect(tracker.observe([task('a')], 'b', true, true)).toEqual([])
  })
  it.each([
    {foreground:true,selected:'a',enabled:true,watched:true},
    {foreground:false,selected:'b',enabled:false,watched:true},
    {foreground:false,selected:'b',enabled:true,watched:false},
  ])('suppresses unwatched, disabled or already visible tasks: %j', state => {
    const tracker = new TaskNotifications()
    tracker.observe([task('a',{running:true,watched:state.watched})],state.selected,state.foreground,state.enabled)
    expect(tracker.observe([task('a',{watched:state.watched,inputIds:['q']})],state.selected,state.foreground,state.enabled)).toEqual([])
  })
  it('prioritizes confirmation, then selected session and recency for the activity notification', () => {
    const rows = [task('a',{running:true,updatedAt:100}),task('b',{inputIds:['q']}),task('unwatched',{inputIds:['q'],watched:false})]
    expect(activeTask(rows,'a')?.id).toBe('b')
    expect(activeTask([rows[0],task('c',{running:true,updatedAt:200})],'a')?.id).toBe('a')
  })
})

describe('Harmony native lifetime cancellation', () => {
  it('does not acquire residency after disconnect while creating the WantAgent', async () => {
    let release!: (value: unknown) => void
    vi.spyOn(wantAgent,'getWantAgent').mockImplementation(() => new Promise(resolve => { release=resolve }) as never)
    const start = vi.spyOn(nativeBackground,'startBackgroundRunning')
    const pending = startResidentTask({})
    const stopping = stopResidentTask({})
    release({})
    await Promise.all([pending,stopping])
    expect(start).not.toHaveBeenCalled()
    expect(residentTaskActive()).toBe(false)
  })
  it('releases a native start that finishes after disconnect', async () => {
    let release!: () => void
    const start = vi.spyOn(nativeBackground,'startBackgroundRunning').mockImplementation(() => new Promise<void>(resolve => { release=resolve }))
    const stop = vi.spyOn(nativeBackground,'stopBackgroundRunning')
    const pending = startResidentTask({})
    await vi.waitFor(() => expect(start).toHaveBeenCalled())
    const stopping = stopResidentTask({})
    release()
    await Promise.all([pending,stopping])
    expect(stop).toHaveBeenCalledTimes(1)
    expect(residentTaskActive()).toBe(false)
  })
  it('honors a new connection requested while the previous native stop is pending', async () => {
    await startResidentTask({})
    let release!: () => void
    const stop = vi.spyOn(nativeBackground,'stopBackgroundRunning').mockImplementationOnce(() => new Promise<void>(resolve => { release=resolve }))
    const start = vi.spyOn(nativeBackground,'startBackgroundRunning')
    const stopping = stopResidentTask({})
    await vi.waitFor(() => expect(stop).toHaveBeenCalled())
    const restarting = startResidentTask({})
    release()
    await Promise.all([stopping,restarting])
    expect(start).toHaveBeenCalledTimes(1)
    expect(residentTaskActive()).toBe(true)
  })
  it('keeps a system-cancelled start inactive even if its native promise resolves late', async () => {
    let release!: () => void
    const start = vi.spyOn(nativeBackground,'startBackgroundRunning').mockImplementationOnce(() => new Promise<void>(resolve => { release=resolve }))
    const pending = startResidentTask({})
    await vi.waitFor(() => expect(start).toHaveBeenCalled())
    cancelResident(); release(); await pending
    expect(residentTaskActive()).toBe(false)
    await startResidentTask({})
    expect(residentTaskActive()).toBe(true)
  })
  it('rejects a delayed file chunk after navigation before touching the sink', async () => {
    let current = true
    const sink = vi.fn(async () => {})
    const transfer = new DownloadTask()
    const bytes = new Uint8Array([1,2,3])
    const tools = {
      statFile: async () => ({absolutePath:'/root/a',version:'1',bytes:3}),
      readBytes: async () => { current=false; return {absolutePath:'/root/a',version:'1',data:btoa(String.fromCharCode(...bytes)),offset:0,bytes:3,eof:true} },
    } as unknown as SessionTools
    await expect(transfer.run(tools,'session','a',()=>current,sink,()=>{})).rejects.toThrow('文件下载已取消')
    expect(sink).not.toHaveBeenCalled()
  })
})
