import { afterEach, beforeAll, describe, expect, it } from 'vitest'
import { controls, requests, secrets } from './native/state'
import { installPlatform, NativeWebSocket, vaultRead, vaultWrite, vaultDelete } from '../core/platform'
import { RemoteServerApi } from '../../android/src/services/api'

beforeAll(() => {
  Object.defineProperty(globalThis, 'crypto', { value: globalThis.crypto, writable: true, configurable: true })
  installPlatform()
})
afterEach(() => { controls.vaultFailure = false; controls.fetch = undefined; requests.length = 0; secrets.clear() })

describe('Harmony native security boundary', () => {
  it('keeps the system WebSocket constructor available to the native factory without recursion', () => {
    const original = Object.getOwnPropertyDescriptor(globalThis, 'WebSocket')
    let constructions = 0
    class SystemSocket { constructor() { ++constructions } }
    Object.defineProperty(globalThis, 'WebSocket', { value: SystemSocket, writable: true, configurable: true })
    controls.onCreateSocket = () => { new (globalThis as any).WebSocket() }
    try {
      installPlatform()
      installPlatform()
      const socket = new NativeWebSocket('ws://127.0.0.1:1')
      void socket.close()
      expect(constructions).toBe(1)
      expect((globalThis as any).WebSocket).toBe(SystemSocket)
    } finally {
      controls.onCreateSocket = undefined
      if (original) Object.defineProperty(globalThis, 'WebSocket', original)
      else delete (globalThis as any).WebSocket
    }
  })

  it('stores and removes secrets with the native Map contract; a locked vault is an error', async () => {
    await vaultWrite('test-identity', 'private-test-data')
    expect(await vaultRead('test-identity')).toBe('private-test-data')
    controls.vaultFailure = true
    await expect(vaultRead('test-identity')).rejects.toThrow('安全存储读取失败')
    controls.vaultFailure = false
    await vaultDelete('test-identity')
    expect(await vaultRead('test-identity')).toBe('')
  })

  it('does not follow a credential-bearing cross-origin redirect', async () => {
    controls.fetch = async () => new Response('', { status: 302, headers: { Location: 'https://untrusted.example/steal' } })
    const response = await fetch('https://server.example/api/v1/devices', { headers: { Authorization: 'Bearer test-credential' } })
    expect(response.status).toBe(302)
    expect(requests).toHaveLength(1)
    expect(requests[0].redirect).toBe('manual')
  })

  it('preserves HTTP error classification when the gateway responds with HTML', async () => {
    for (const [status, code] of [[429, 'RATE_LIMITED'], [503, 'CONNECTION_FAILED'], [401, 'AUTH_INVALID']] as const) {
      controls.fetch = async () => new Response('<html>gateway failure</html>', { status })
      await expect(new RemoteServerApi('https://server.example', 'test').listDevices())
        .rejects.toMatchObject({ code, status })
    }
    controls.fetch = async () => new Response('<html>unexpected success</html>', { status: 200 })
    await expect(new RemoteServerApi('https://server.example', 'test').listDevices())
      .rejects.toMatchObject({ code: 'INVALID_MESSAGE' })
  })

  it('provides strict UTF-8 and native secure randomness for shared protocol code', () => {
    const text = '鸿蒙 🚀 Noise IK'
    expect(new TextDecoder('utf-8', { fatal: true }).decode(new TextEncoder().encode(text))).toBe(text)
    expect(() => new TextDecoder('utf-8', { fatal: true }).decode(new Uint8Array([0xc0, 0xaf]))).toThrow()
    expect(crypto.getRandomValues(new Uint8Array(32))).toHaveLength(32)
    expect(crypto.randomUUID()).toMatch(/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/)
    expect(() => crypto.getRandomValues(new Uint8Array(65537))).toThrow()
  })
})
