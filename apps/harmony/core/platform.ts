// Native HarmonyOS adapters. No WebView, remote script, or Android runtime.
import cryptoFramework from '@ohos.security.cryptoFramework'
import util from '@ohos.util'
import url from '@ohos.url'
import rcp from '@hms.collaboration.rcp'
import webSocket from '@ohos.net.webSocket'
import asset from '@ohos.security.asset'
import dataPreferences from '@ohos.data.preferences'
import i18n from '@ohos.i18n'
import pasteboard from '@ohos.pasteboard'
import systemShare from '@hms.collaboration.systemShare'
import window from '@ohos.window'
import type common from '@ohos.app.ability.common'

const encoder = new util.TextEncoder()
const decoder = util.TextDecoder.create('utf-8', { fatal: true })
const encode = (text: string) => encoder.encodeInto(text)
const decode = (bytes: Uint8Array) => decoder.decodeToString(bytes)

export async function vaultRead(key: string): Promise<string> {
  try {
    const rows = await asset.query(new Map<asset.Tag, asset.Value>([
      [asset.Tag.ALIAS, encode(key)], [asset.Tag.RETURN_TYPE, asset.ReturnType.ALL],
    ]))
    return rows.length ? decode(rows[0].get(asset.Tag.SECRET) as Uint8Array) : ''
  } catch (error) {
    if ((error as { code?: number }).code === asset.ErrorCode.NOT_FOUND) return ''
    throw new Error('安全存储读取失败，请解锁设备后重试。')
  }
}
export async function vaultWrite(key: string, value: string): Promise<void> {
  await asset.add(new Map<asset.Tag, asset.Value>([
    [asset.Tag.ALIAS, encode(key)], [asset.Tag.SECRET, encode(value)],
    [asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED],
    [asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE],
  ]))
}
export async function vaultDelete(key: string): Promise<void> {
  try { await asset.remove(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, encode(key)]])) }
  catch (error) { if ((error as { code?: number }).code !== asset.ErrorCode.NOT_FOUND) throw new Error('安全存储删除失败。') }
}

// Preferences hold high-frequency UI state (favorites, recents, ordering, view
// options). The asset vault above is key-only and throttles writes, so nothing
// here may carry secrets; a missing store degrades to session-only memory.
type PreferencesContext = Parameters<typeof dataPreferences.getPreferences>[0]
let store: dataPreferences.Preferences | undefined

export async function attachPreferences(context: Object): Promise<void> {
  if (store) return
  try { store = await dataPreferences.getPreferences(context as PreferencesContext, 'dsh.remote.prefs') }
  catch { store = undefined }
}
export async function prefRead(key: string): Promise<string> {
  if (!store) return ''
  try {
    const value = await store.get(key, '')
    return typeof value === 'string' ? value : ''
  } catch { return '' }
}
export async function prefWrite(key: string, value: string): Promise<void> {
  if (!store) return
  try { await store.put(key, value); await store.flush() } catch { /* view state is disposable; never fail the action for it */ }
}
export async function prefWriteStrict(key: string, value: string): Promise<void> {
  if (!store) throw new Error('本地存储暂不可用，请解锁后重试。')
  await store.put(key, value)
  await store.flush()
}

export function systemLocale(): string {
  try {
    const locale = i18n.System.getSystemLocale()
    return typeof locale === 'string' && locale.length > 0 ? locale : 'zh-CN'
  } catch { return 'zh-CN' }
}

export class NativeWebSocket {
  static readonly OPEN = 1
  static readonly CONNECTING = 0
  static readonly CLOSING = 2
  static readonly CLOSED = 3
  readyState = 0
  bufferedAmount = 0
  binaryType = 'arraybuffer'
  onopen?: () => void
  onmessage?: (event: { data: string | ArrayBuffer }) => void
  onerror?: () => void
  onclose?: (event: { code: number; reason: string }) => void
  private socket = webSocket.createWebSocket()
  private tail = Promise.resolve()
  private closeNotified = false
  constructor(address: string) {
    this.socket.on('open', () => {
      if (this.readyState !== 0) return
      this.readyState = 1; this.onopen?.()
    })
    this.socket.on('message', (error, data) => {
      if (this.readyState !== 1) return
      if (error && error.code) { this.fail(); return }
      this.onmessage?.({ data })
    })
    this.socket.on('error', () => this.fail())
    this.socket.on('close', (_error, result) => this.finish(result?.code ?? 1006, result?.reason ?? ''))
    // Match browser timing: consumers install callbacks after the constructor.
    void Promise.resolve().then(async () => {
      if (this.readyState !== 0) return
      try { await this.socket.connect(address) } catch { this.fail() }
    })
  }
  send(data: string | ArrayBuffer): void {
    if (this.readyState !== 1) throw new Error('WebSocket is closed.')
    const bytes = typeof data === 'string' ? encode(data).length : data.byteLength
    if (this.bufferedAmount + bytes > 16 * 1024 * 1024) { this.fail(); throw new Error('WebSocket queue exceeded.') }
    this.bufferedAmount += bytes
    this.tail = this.tail.then(async () => {
      if (this.readyState !== 1) throw new Error('WebSocket is closed.')
      const accepted = await this.socket.send(data)
      if (!accepted) throw new Error('WebSocket send failed.')
    }).catch(() => this.fail()).finally(() => { this.bufferedAmount -= bytes })
  }
  close(code = 1000, reason = ''): void {
    if (this.readyState >= 2) return
    this.readyState = 2
    void this.socket.close({ code, reason }).catch(() => undefined).finally(() => this.finish(code, reason))
  }
  private fail(): void {
    if (this.readyState >= 2) return
    this.onerror?.(); this.close(1006)
  }
  private finish(code: number, reason: string): void {
    this.readyState = 3
    if (this.closeNotified) return
    this.closeNotified = true; this.onclose?.({ code, reason })
  }
}

// AbortController is absent in some Ark runtimes. This implements exactly the
// event contract used by the shared client, including already-aborted signals.
class NativeAbortSignal {
  aborted = false
  reason: unknown
  private listeners = new Map<() => void, boolean>()
  addEventListener(_type: string, handler: () => void, options?: { once?: boolean }): void { this.listeners.set(handler, options?.once === true) }
  removeEventListener(_type: string, handler: () => void): void { this.listeners.delete(handler) }
  throwIfAborted(): void { if (this.aborted) throw this.reason }
  abort(reason?: unknown): void {
    if (this.aborted) return
    this.aborted = true; this.reason = reason ?? Object.assign(new Error('Cancelled'), { name: 'AbortError' })
    for (const [listener, once] of [...this.listeners]) { if (once) this.listeners.delete(listener); listener() }
  }
}
class NativeAbortController {
  readonly signal = new NativeAbortSignal()
  abort(reason?: unknown): void { this.signal.abort(reason) }
}

export function installPlatform(): void {
  const random = cryptoFramework.createRandom()
  const globals = globalThis as unknown as Record<string, unknown>
  globals.crypto = {
    getRandomValues: (target: Uint8Array) => {
      if (!(target instanceof Uint8Array) || target.length > 65536) throw new TypeError('Invalid random byte request.')
      target.set(random.generateRandomSync(target.length).data); return target
    },
    randomUUID: () => {
      const bytes = random.generateRandomSync(16).data
      bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128
      const h = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('')
      return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
    },
  }
  globals.URL = url.URL
  globals.URLSearchParams = url.URLSearchParams
  globals.TextEncoder = class { encode(text = '') { return encode(text) } }
  globals.TextDecoder = class {
    private native: util.TextDecoder
    constructor(label = 'utf-8', options: { fatal?: boolean } = {}) { this.native = util.TextDecoder.create(label, options) }
    decode(data: Uint8Array) { return this.native.decodeToString(data) }
  }
  globals.btoa = (input: string) => new util.Base64Helper().encodeToStringSync(Uint8Array.from(input, c => c.charCodeAt(0)))
  globals.atob = (input: string) => Array.from(new util.Base64Helper().decodeSync(input), byte => String.fromCharCode(byte)).join('')
  if (globals.AbortController === undefined) { globals.AbortController = NativeAbortController; globals.AbortSignal = NativeAbortSignal }
  // NetworkKit createWebSocket() looks up the native constructor on globalThis.
  // Replacing it makes its factory recursively re-enter this adapter. Shared
  // protocol code receives NativeWebSocket as a module-local build binding.
  globals.fetch = async (address: string, init: RequestInit = {}) => {
    const session = rcp.createSession({ requestConfiguration: { transfer: { autoRedirect: false, timeout: { connectMs: 15000, transferMs: 15000 } } } })
    const abort = () => session.cancel()
    if (init.signal?.aborted) throw Object.assign(new Error('Cancelled'), { name: 'AbortError' })
    init.signal?.addEventListener('abort', abort, { once: true })
    try {
      const response = await session.fetch(new rcp.Request(address, (init.method ?? 'GET') as rcp.HttpMethod,
        init.headers as rcp.RequestHeaders, init.body as string | undefined))
      if ((response.body?.byteLength ?? 0) > 32 * 1024 * 1024) throw new Error('Response exceeds limit.')
      let text = response.toString() ?? ''
      if (response.statusCode >= 400) {
        // Gateways can return HTML for 429/5xx. Preserve the HTTP status for
        // the shared API error mapper instead of misreporting invalid JSON.
        try { JSON.parse(text) } catch {
          text = JSON.stringify({ error: { message: 'The server rejected the request.', retryable: response.statusCode === 429 || response.statusCode >= 500 } })
        }
      }
      return { ok: response.statusCode >= 200 && response.statusCode < 300, status: response.statusCode, text: async () => text }
    } catch {
      if (init.signal?.aborted) throw Object.assign(new Error('Cancelled'), { name: 'AbortError' })
      throw new Error('网络请求失败，请检查服务器地址与网络。')
    } finally { init.signal?.removeEventListener('abort', abort); session.close() }
  }
}

export async function copyText(value: string): Promise<void> {
  await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value))
}
export async function shareText(context: Object, value: string): Promise<void> {
  const data = new systemShare.SharedData({ utd: 'general.plain-text', content: value })
  await new systemShare.ShareController(data).show(context as common.UIAbilityContext, {})
}

export async function setStatusBarVisible(context: Object, visible: boolean): Promise<void> {
  const target = await window.getLastWindow(context as common.UIAbilityContext)
  await target.setWindowSystemBarEnable(visible ? ['status','navigation'] : ['navigation'])
}
export async function clearLocalPreferences(): Promise<void> { if(store) { await store.clear(); await store.flush() } }
export async function clearBrowsePreferences(): Promise<void> {
  if (!store) throw new Error('本地存储暂不可用。')
  const values = await store.getAll()
  for (const key of Object.keys(values)) {
    if (key === 'hostModes' || key === 'drafts' || key === 'prompts' || key.startsWith('view.') || key.startsWith('dshremote.harmony-browse') || key.startsWith('lastHost.')) await store.delete(key)
  }
  await store.flush()
}
