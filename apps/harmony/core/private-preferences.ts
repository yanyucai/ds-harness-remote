import { encryptFrame, decryptFrame, fromBase64Url, toBase64Url } from '@dsh-remote/crypto'
import { prefRead, prefWriteStrict, vaultRead, vaultWrite } from './platform.js'

const KEY = 'dsh.harmony.browse.key.v1'
let writes = Promise.resolve()
const sensitive = (name: string) => name === 'hostModes' || name === 'drafts' || name === 'prompts' || name.startsWith('view.') || name.startsWith('dshremote.harmony-browse')
async function key(): Promise<Uint8Array> {
  const saved = await vaultRead(KEY)
  if (saved) return fromBase64Url(saved)
  const value = crypto.getRandomValues(new Uint8Array(32))
  await vaultWrite(KEY, toBase64Url(value))
  return value
}
export async function readPreference(name: string): Promise<string> {
  await writes
  const raw = await prefRead(name)
  if (!raw || !sensitive(name)) return raw
  const value = JSON.parse(raw)
  if (value?.format === 'sealed-v1') {
    const saved = await vaultRead(KEY)
    if (!saved) throw new Error('本地浏览数据密钥不可用。')
    return new TextDecoder().decode(decryptFrame(fromBase64Url(saved), value.frame, name))
  }
  // Seal existing local data before returning it; never fall back to plaintext writes.
  await writePreference(name, raw)
  return raw
}
export function writePreference(name: string, value: string): Promise<void> {
  const work = writes.catch(() => {}).then(async () => {
    const raw = sensitive(name) ? JSON.stringify({ format: 'sealed-v1', frame: encryptFrame(await key(), new TextEncoder().encode(value), name) }) : value
    await prefWriteStrict(name, raw)
  })
  writes = work
  return work
}
