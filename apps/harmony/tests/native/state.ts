import { randomFillSync } from 'node:crypto'
import { TextEncoder, TextDecoder } from 'node:util'
import { WebSocket } from 'ws'
export const nativeFetch = globalThis.fetch.bind(globalThis)
export const secrets = new Map<string, Uint8Array>()
export const requests: Array<{ url: string; method: string; headers: Record<string, string>; content?: string; redirect: string }> = []
export const controls = { vaultFailure: false, sendFailure: false, onCreateSocket: undefined as undefined | (() => void), fetch: undefined as undefined | ((request: typeof requests[number]) => Promise<Response>) }
export const nativeCrypto = { createRandom: () => ({ generateRandomSync: (length: number) => ({ data: randomFillSync(new Uint8Array(length)) }) }) }
export const nativeUtil = {
  TextEncoder: class { encodeInto(text: string) { return new TextEncoder().encode(text) } },
  TextDecoder: class {
    static create(label: string, options: object) { const native = new TextDecoder(label, options); return { decodeToString: (data: Uint8Array) => native.decode(data) } }
  },
  Base64Helper: class {
    encodeToStringSync(data: Uint8Array) { return Buffer.from(data).toString('base64') }
    decodeSync(text: string) { return new Uint8Array(Buffer.from(text, 'base64')) }
  },
}
export const nativeAsset = {
  Tag: { ALIAS: 1, SECRET: 2, RETURN_TYPE: 3, ACCESSIBILITY: 4, IS_PERSISTENT: 5, CONFLICT_RESOLUTION: 6 },
  ReturnType: { ALL: 0 }, Accessibility: { DEVICE_UNLOCKED: 2 }, ConflictResolution: { OVERWRITE: 0 }, ErrorCode: { NOT_FOUND: 24000002 },
  query: async (query: Map<number, unknown>) => {
    if (controls.vaultFailure) throw { code: 24000005 }
    if (!(query instanceof Map)) throw new Error('Native Asset requires Map')
    const key = Buffer.from(query.get(1) as Uint8Array).toString()
    const value = secrets.get(key)
    if (!value) throw { code: 24000002 }
    return [new Map([[2, value]])]
  },
  add: async (attrs: Map<number, unknown>) => {
    if (controls.vaultFailure) throw { code: 24000005 }
    if (!(attrs instanceof Map) || attrs.has(5)) throw new Error('Invalid Asset contract')
    secrets.set(Buffer.from(attrs.get(1) as Uint8Array).toString(), attrs.get(2) as Uint8Array)
  },
  remove: async (query: Map<number, unknown>) => { secrets.delete(Buffer.from(query.get(1) as Uint8Array).toString()) },
}
export const prefs = new Map<string, string>()
export const nativePreferences = {
  getPreferences: async (_context: unknown, name: string) => {
    if (typeof name !== 'string' || name.length === 0) throw new Error('Invalid preferences name')
    return {
      get: async (key: string, def: string | number | boolean) => (typeof def === 'string' ? prefs.get(key) ?? def : def),
      put: async (key: string, value: string | number | boolean) => { prefs.set(key, String(value)) },
      flush: async () => undefined,
      delete: async (key: string) => { prefs.delete(key) },
    }
  },
}
export const nativeRcp = {
  Request: class {
    constructor(public url: string, public method: string, public headers: Record<string, string>, public content?: string) {}
  },
  createSession: (config: { requestConfiguration: { transfer: { autoRedirect: boolean } } }) => {
    const controller = new AbortController()
    return {
      fetch: async (request: InstanceType<typeof nativeRcp.Request>) => {
        const req = { ...request, redirect: config.requestConfiguration.transfer.autoRedirect ? 'follow' : 'manual' }
        requests.push(req)
        const response = controls.fetch ? await controls.fetch(req) : await nativeFetch(request.url, { method: request.method, headers: request.headers, body: request.content, redirect: req.redirect as RequestRedirect, signal: controller.signal })
        const buffer = await response.arrayBuffer()
        return { statusCode: response.status, body: buffer, toString: () => new TextDecoder().decode(buffer) }
      },
      cancel: () => controller.abort(), close: () => undefined,
    }
  },
}
export const nativeSocket = {
  createWebSocket: () => {
    controls.onCreateSocket?.()
    const handlers = new Map<string, (...args: unknown[]) => void>()
    let socket: WebSocket | undefined
    return {
      on: (type: string, cb: (...args: unknown[]) => void) => handlers.set(type, cb),
      connect: async (address: string) => {
        socket = new WebSocket(address)
        socket.on('open', () => handlers.get('open')?.({}, {}))
        socket.on('message', raw => handlers.get('message')?.({}, raw.toString()))
        socket.on('error', () => handlers.get('error')?.({ code: 1 }))
        socket.on('close', (code, reason) => handlers.get('close')?.({}, { code, reason: reason.toString() }))
        return true
      },
      send: async (data: string | ArrayBuffer) => {
        if (controls.sendFailure) throw new Error('Native send failure')
        await new Promise<void>((resolve, reject) => socket!.send(data, error => error ? reject(error) : resolve()))
        return true
      },
      close: async (options: { code: number; reason: string }) => {
        if (options.code === 1006) socket?.terminate(); else socket?.close(options.code, options.reason)
        return true
      },
    }
  },
}
