// ArkWeb owns the platform RTC implementation; business data remains Noise encrypted.
import type { RtcIceServer, RtcSessionDescriptionInit, RtcIceCandidateInit } from '@dsh-remote/webrtc'
let deliver: ((raw: string) => Promise<void>) | undefined
let sequence = 0
const peers = new Map<number, HarmonyPeer>()
const calls = new Map<number, { resolve(value: unknown): void; reject(error: Error): void; timer: ReturnType<typeof setTimeout> }>()
const encode = (data: ArrayBuffer): string => {
  const bytes = new Uint8Array(data); let text = ''
  for (let i=0;i<bytes.length;i+=8192) text += String.fromCharCode(...bytes.subarray(i,i+8192))
  return btoa(text)
}
const decode = (value: string): ArrayBuffer => Uint8Array.from(atob(value), char => char.charCodeAt(0)).buffer
function command(peer: number, operation: string, payload: unknown = {}): Promise<unknown> {
  if (!deliver) return Promise.reject(new Error('RTC runtime is unavailable'))
  const id = ++sequence
  return new Promise((resolve,reject) => {
    const timer = setTimeout(() => { calls.delete(id); reject(new Error('RTC operation timed out')) },20000)
    calls.set(id,{resolve,reject,timer})
    void deliver!(JSON.stringify({ id, peer, operation, payload })).catch(() => {
      clearTimeout(timer); calls.delete(id); reject(new Error('RTC bridge unavailable'))
    })
  })
}
class HarmonyChannel {
  readyState = 'connecting'; bufferedAmount = 0; binaryType = 'arraybuffer'
  onopen: (() => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  onbufferedamountlow: (() => void) | null = null
  onmessage: ((event: { data: ArrayBuffer | string }) => void) | null = null
  constructor(readonly peer: number, readonly id: number, readonly label: string, readonly ordered = true) {}
  send(data: string | ArrayBuffer): void {
    if (this.readyState !== 'open') throw new Error('RTC channel is closed')
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data).length : data.byteLength
    if (this.bufferedAmount + bytes > 16*1024*1024) throw new Error('RTC send queue exceeded')
    this.bufferedAmount += bytes
    void command(this.peer,'send',{ channel:this.id, data:typeof data === 'string'?data:encode(data), binary:typeof data !== 'string' })
      .then(value => { this.bufferedAmount = typeof value === 'number' ? value : 0; this.onbufferedamountlow?.() })
      .catch(() => { this.onerror?.(); this.close() })
  }
  close(): void { this.readyState='closed'; void command(this.peer,'channelClose',{channel:this.id}).catch(()=>{}); this.onclose?.() }
}
class HarmonyPeer {
  connectionState='new'; iceConnectionState='new'; iceGatheringState='new'; signalingState='stable'
  onconnectionstatechange: (()=>void)|null=null
  oniceconnectionstatechange: (()=>void)|null=null
  onicegatheringstatechange: (()=>void)|null=null
  onicecandidate: ((event:{candidate:RtcIceCandidateInit|null})=>void)|null=null
  ondatachannel: ((event:{channel:HarmonyChannel})=>void)|null=null
  readonly id=++sequence
  readonly channels=new Map<number,HarmonyChannel>()
  private ready: Promise<unknown>
  constructor(configuration:{iceServers?:RtcIceServer[]}) {
    peers.set(this.id,this); this.ready=command(this.id,'create',{iceServers:configuration.iceServers??[]})
    void this.ready.catch(()=>{ this.connectionState='failed'; this.onconnectionstatechange?.() })
  }
  createDataChannel(label:string,options?:{ordered?:boolean}):HarmonyChannel {
    const id=++sequence, channel=new HarmonyChannel(this.id,id,label,options?.ordered!==false)
    this.channels.set(id,channel)
    void this.ready.then(()=>command(this.id,'channelCreate',{id,label,ordered:channel.ordered})).catch(()=>channel.onerror?.())
    return channel
  }
  async createOffer():Promise<RtcSessionDescriptionInit> { await this.ready; return await command(this.id,'createOffer') as RtcSessionDescriptionInit }
  async createAnswer():Promise<RtcSessionDescriptionInit> { await this.ready; return await command(this.id,'createAnswer') as RtcSessionDescriptionInit }
  async setLocalDescription(value?:RtcSessionDescriptionInit):Promise<void> { await this.ready; await command(this.id,'setLocalDescription',value) }
  async setRemoteDescription(value:RtcSessionDescriptionInit):Promise<void> { await this.ready; await command(this.id,'setRemoteDescription',value) }
  async addIceCandidate(value?:RtcIceCandidateInit):Promise<void> { await this.ready; await command(this.id,'addIceCandidate',value) }
  async getStats():Promise<Map<string,Record<string,unknown>>> { return new Map(await command(this.id,'getStats') as Array<[string,Record<string,unknown>]>) }
  close():void {
    peers.delete(this.id); this.connectionState='closed'
    for(const channel of this.channels.values()){ channel.readyState='closed'; channel.onclose?.() }
    void command(this.id,'close').catch(()=>{})
  }
}
export function attachRtcBridge(send:(raw:string)=>Promise<void>):void {
  deliver=send
  // Only the reviewed RTC adapter owns this global; NetworkKit WebSocket stays intact.
  ;(globalThis as unknown as { RTCPeerConnection: typeof HarmonyPeer }).RTCPeerConnection=HarmonyPeer
}
export function receiveRtcBridge(raw:string):void {
  if(raw.length>24*1024*1024) return
  try {
    const msg=JSON.parse(raw)
    if(msg.type==='reply') {
      const pending=calls.get(msg.id); if(!pending)return
      calls.delete(msg.id); clearTimeout(pending.timer)
      if(msg.ok)pending.resolve(msg.value);else pending.reject(new Error('RTC platform operation failed'))
      return
    }
    const peer=peers.get(msg.peer); if(!peer)return
    if(msg.type==='state') {
      peer.connectionState=msg.connectionState;peer.iceConnectionState=msg.iceConnectionState
      peer.iceGatheringState=msg.iceGatheringState;peer.signalingState=msg.signalingState
      peer.onconnectionstatechange?.();peer.oniceconnectionstatechange?.();peer.onicegatheringstatechange?.()
    } else if(msg.type==='candidate') peer.onicecandidate?.({candidate:msg.candidate})
    else if(msg.type==='channel') {
      const channel=new HarmonyChannel(peer.id,msg.channel,msg.label,msg.ordered)
      peer.channels.set(msg.channel,channel);peer.ondatachannel?.({channel})
    } else {
      const channel=peer.channels.get(msg.channel);if(!channel)return
      if(msg.type==='open'){channel.readyState='open';channel.onopen?.()}
      if(msg.type==='close'){channel.readyState='closed';channel.onclose?.()}
      if(msg.type==='error')channel.onerror?.()
      if(msg.type==='data')channel.onmessage?.({data:msg.binary?decode(msg.data):msg.data})
    }
  } catch { /* Never log SDP, candidate addresses or encrypted payloads. */ }
}
