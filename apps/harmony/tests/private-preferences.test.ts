import { beforeAll, beforeEach, describe, expect, it } from 'vitest'
import { attachPreferences, installPlatform } from '../core/platform'
import { readPreference, writePreference } from '../core/private-preferences'
import { controls, prefs, secrets } from './native/state'

beforeAll(() => {
  Object.defineProperty(globalThis, 'crypto', { value: globalThis.crypto, writable: true, configurable: true })
  installPlatform()
})
beforeEach(async () => { prefs.clear(); secrets.clear(); controls.vaultFailure = false; await attachPreferences({}) })

describe('Harmony private navigation storage', () => {
  it('seals existing drafts, authenticates the preference name and rejects tampering', async () => {
    const content = JSON.stringify({ accountA: 'private draft' })
    prefs.set('drafts', content)
    expect(await readPreference('drafts')).toBe(content)
    const sealed = prefs.get('drafts')!
    expect(sealed).not.toContain('private draft')
    expect(JSON.parse(sealed).format).toBe('sealed-v1')
    expect([...secrets.keys()]).toContain('dsh.harmony.browse.key.v1')
    prefs.set('prompts', sealed)
    await expect(readPreference('prompts')).rejects.toThrow()
    const record = JSON.parse(sealed)
    record.frame.ciphertext = 'tampered'
    prefs.set('drafts', JSON.stringify(record))
    await expect(readPreference('drafts')).rejects.toThrow()
  })

  it('serializes writes and never overwrites private data with plaintext on a vault failure', async () => {
    await writePreference('drafts', 'first')
    await Promise.all([writePreference('drafts', 'second'), writePreference('drafts', 'third')])
    expect(await readPreference('drafts')).toBe('third')
    const previous = prefs.get('drafts')
    controls.vaultFailure = true
    await expect(writePreference('drafts', 'must not persist')).rejects.toThrow()
    expect(prefs.get('drafts')).toBe(previous)
    expect(prefs.get('drafts')).not.toContain('must not persist')
    controls.vaultFailure = false
    await writePreference('drafts', 'recovered')
    expect(await readPreference('drafts')).toBe('recovered')
  })
})
