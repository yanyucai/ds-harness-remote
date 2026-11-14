// Harmony uses its native NetworkKit binary socket and reviewed ArkWeb RTC bridge.
// Android-only cipher/RTC accelerators are optional; shared crypto stays authoritative.
export function nativeChaChaEncryptor(): undefined { return undefined }
export function nativeRtcFactory(): undefined { return undefined }
export function nativeWebSocketSender(): (socket: unknown, data: Uint8Array) => void {
  return (socket, data) => {
    if (!data.byteLength || data.byteLength > 65535) throw new Error('Invalid binary socket payload')
    const target = socket as { send(data: ArrayBuffer): void }
    target.send(new Uint8Array(data).buffer)
  }
}
