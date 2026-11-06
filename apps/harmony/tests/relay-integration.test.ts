import { expect, it } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { once } from 'node:events'
import { WebSocket } from 'ws'
import { createRemoteServer } from '../../server/src/server'
import { RemoteServerApi } from '../../android/src/services/api'
import { SecureTransport } from '../../android/src/services/secure-transport'
import { AdaptiveTransport } from '@dsh-remote/webrtc'
import { RemoteClientCore } from '@dsh-remote/client-core'
import { generateKeyPair, NoiseIkSession, createNoisePrologue, toBase64Url, fromBase64Url } from '@dsh-remote/crypto'
import { createControlFrame, SecureMessageCodec, decodeMessage, encodeMessage, createRpcResponse } from '@dsh-remote/protocol'
import { installPlatform } from '../core/platform'
import type { DeviceIdentity, RemoteDevice } from '../../android/src/types'

// Only OS bindings are substituted. HTTP/WSS routing, membership, Noise IK,
// counters, framing, and the RPC codec below are the actual pinned upstream code.
it('interoperates through the real upstream relay with native adapters and fails closed on replay', async () => {
  Object.defineProperty(globalThis, 'crypto', { value: globalThis.crypto, writable: true, configurable: true })
  installPlatform()
  const dir = await mkdtemp(join(tmpdir(), 'dsh-harmony-relay-'))
  const app = createRemoteServer({ account: 'owner@example.com', password: '{{SECRET_rbw3iviu}}', dataFile: join(dir, 'state.json'), publicUrl: 'http://127.0.0.1' })
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening')
  const base = `http://127.0.0.1:${(app.server.address() as { port: number }).port}`
  let hostSocket: WebSocket | undefined
  let core: RemoteClientCore | undefined
  let noise: NoiseIkSession | undefined
  try {
    const api = new RemoteServerApi(base)
    const login = await api.loginAccount('owner@example.com', '{{SECRET_rbw3iviu}}')
    const identity: DeviceIdentity = { ...generateKeyPair(), deviceId: crypto.randomUUID(), name: 'Harmony test', platform: 'harmonyos' as DeviceIdentity['platform'] }
    const credentials = await api.registerDevice(identity, login.token)
    const hostKeys = generateKeyPair()
    const hostId = crypto.randomUUID()
    const registered = await fetch(`${base}/api/v1/devices/register`, { method: 'POST', headers: { Authorization: `Bearer ${login.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ v: 1, device: { deviceId: hostId, name: 'Host', role: 'host', platform: 'linux', identityKey: hostKeys.publicKey, clientVersion: '0.5.23' } }) })
    expect(registered.status).toBe(200)
    const hostCredentials = JSON.parse(await registered.text())
    const hostApi = new RemoteServerApi(base, credentials.accessToken)
    const peer = await hostApi.deviceFor(hostId)
    const host: RemoteDevice = { ...peer, online: true, trusted: true }
    hostSocket = new WebSocket(base.replace('http:', 'ws:') + '/ws/v1/connect')
    const wire: Array<{ type: string; payload: Record<string, any> }> = []
    hostSocket.on('message', raw => wire.push(JSON.parse(raw.toString())))
    const next = async (type: string) => {
      for (let attempt = 0; attempt < 300; attempt++) {
        const index = wire.findIndex(frame => frame.type === type)
        if (index >= 0) return wire.splice(index, 1)[0].payload
        await new Promise(resolve => setTimeout(resolve, 10))
      }
      throw new Error(`Expected Host frame ${type}`)
    }
    const send = (type: Parameters<typeof createControlFrame>[0], payload: unknown) => hostSocket!.send(JSON.stringify(createControlFrame(type, payload)))
    await once(hostSocket, 'open')
    send('hello', { role: 'host', deviceId: hostId, accessToken: hostCredentials.accessToken, protocols: [1], capabilities: ['transport.relay'] })
    await next('hello.ack')
    const transport = new AdaptiveTransport(base.replace('http:', 'ws:') + '/ws/v1/connect', { role: 'client', deviceId: identity.deviceId, targetDeviceId: hostId, accessToken: credentials.accessToken, forceRelay: true, preferredTransports: ['relay'] })
    core = new RemoteClientCore(new SecureTransport(transport, identity, host), 1000)
    const connecting = core.connect()
    const incoming = await next('connect.incoming')
    expect(incoming.clientIdentityKey).toBe(identity.publicKey)
    const connectionId = incoming.connectionId as string
    send('connect.accepted', { connectionId })
    noise = new NoiseIkSession({ role: 'responder', localPrivateKey: hostKeys.privateKey, localPublicKey: hostKeys.publicKey, remotePublicKey: identity.publicKey, prologue: createNoisePrologue(connectionId, hostId, identity.deviceId) })
    noise.readHandshake(fromBase64Url((await next('secure.handshake')).data))
    send('secure.handshake', { connectionId, targetDeviceId: identity.deviceId, step: 2, data: toBase64Url(noise.writeHandshake()) })
    await connecting
    expect(noise.complete).toBe(true)
    const result = core.rpc('harness.transport.describe', {})
    const inbound = await next('relay')
    expect(inbound.ciphertext).not.toContain('harness.transport.describe')
    const decoded = new SecureMessageCodec().decode(noise.decrypt(fromBase64Url(inbound.ciphertext)))!
    const request = decodeMessage(decoded)
    const encoded = new SecureMessageCodec().encode(encodeMessage(createRpcResponse(request.id, { capabilities: ['harness.remote.v1'] })))
    const ciphertext = toBase64Url(noise.encrypt(encoded[0]))
    send('relay', { connectionId, targetDeviceId: identity.deviceId, counter: 0, ciphertext })
    await expect(result).resolves.toEqual({ capabilities: ['harness.remote.v1'] })
    const closed = new Promise<void>(resolve => core!.onClose(() => resolve()))
    // A fresh relay counter must not let an old Noise ciphertext through.
    send('relay', { connectionId, targetDeviceId: identity.deviceId, counter: 1, ciphertext })
    await closed
    await expect(core.rpc('harness.transport.describe', {})).rejects.toThrow()
  } finally {
    await core?.close(); noise?.destroy(); hostSocket?.terminate()
    await app.close(); await rm(dir, { recursive: true, force: true })
  }
})
