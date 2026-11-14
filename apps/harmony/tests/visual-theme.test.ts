import { describe, expect, it } from 'vitest'
import { harmonyTypeScale, resolveHarmonyTheme } from '../entry/src/main/ets/theme/HarmonyTheme'

describe('Harmony visual theme', () => {
  it('matches Android DeepSeek colors in both schemes', () => {
    const light = resolveHarmonyTheme(false)
    const dark = resolveHarmonyTheme(true)
    expect([light.background, light.card, light.ink, light.primary, light.muted]).toEqual([
      '#F8F8F8', '#FFFFFF', '#0F0F0F', '#4D6BFE', '#59606D',
    ])
    expect([dark.background, dark.surface, dark.ink, dark.primary, dark.muted]).toEqual([
      '#0B0D11', '#161A21', '#F2F4F7', '#6F89FF', '#A2A9B6',
    ])
  })

  it('keeps accent choices scheme-aware and exposes Android type scales', () => {
    expect(resolveHarmonyTheme(false, 'emerald').primary).toBe('#0D9488')
    expect(resolveHarmonyTheme(true, 'emerald').primary).toBe('#2DD4BF')
    expect(harmonyTypeScale('compact')).toMatchObject({
      titleSize: 22, bodySize: 15, bodyLineHeight: 20, captionSize: 11, captionLineHeight: 15,
    })
    expect(harmonyTypeScale('standard')).toMatchObject({
      titleSize: 24, bodySize: 16, bodyLineHeight: 22, captionSize: 12, captionLineHeight: 16,
    })
  })
})
