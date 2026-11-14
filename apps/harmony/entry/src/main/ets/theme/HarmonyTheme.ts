export interface HarmonyThemeColors {
  background: string
  surface: string
  card: string
  cardOpaque: string
  surfaceStrong: string
  grouped: string
  elevated: string
  ink: string
  muted: string
  subtle: string
  primary: string
  primaryPressed: string
  primarySoft: string
  accent: string
  accentSoft: string
  inverse: string
  onInverse: string
  success: string
  successSoft: string
  warning: string
  warningSoft: string
  danger: string
  dangerSoft: string
  border: string
  separator: string
  disabled: string
  white: string
  scrim: string
  modalBackdrop: string
  userBubble: string
  toolSurface: string
  codeSurface: string
  codeHeader: string
  onPrimary: string
}

export interface HarmonyTypeScale {
  heroSize: number
  heroLineHeight: number
  titleSize: number
  titleLineHeight: number
  headingSize: number
  headingLineHeight: number
  bodySize: number
  bodyLineHeight: number
  smallSize: number
  smallLineHeight: number
  captionSize: number
  captionLineHeight: number
}

const lightColors: HarmonyThemeColors = {
  background: '#F8F8F8',
  surface: '#FFFFFF',
  card: '#FFFFFF',
  cardOpaque: '#FFFFFF',
  surfaceStrong: '#ECEFF4',
  grouped: '#FFFFFF',
  elevated: '#FFFFFF',
  ink: '#0F0F0F',
  muted: '#59606D',
  subtle: '#B9B9BB',
  primary: '#4D6BFE',
  primaryPressed: '#3A56E6',
  primarySoft: '#EBEFFF',
  accent: '#4D6BFE',
  accentSoft: '#EBEFFF',
  inverse: '#0F0F0F',
  onInverse: '#FFFFFF',
  success: '#1E8449',
  successSoft: '#E2F3E9',
  warning: '#95600A',
  warningSoft: '#FBEFD5',
  danger: '#C2362F',
  dangerSoft: '#FBE7E5',
  border: '#EDEDED',
  separator: '#EDEDED',
  disabled: '#B3B9C4',
  white: '#FFFFFF',
  scrim: '#660F0F0F',
  modalBackdrop: '#6B0F0F0F',
  userBubble: '#ECEFF5',
  toolSurface: '#F2F4F8',
  codeSurface: '#F6F8FB',
  codeHeader: '#EDF1F7',
  onPrimary: '#FFFFFF',
}

const darkColors: HarmonyThemeColors = {
  background: '#0B0D11',
  surface: '#161A21',
  card: '#0D17191D',
  cardOpaque: '#17191D',
  surfaceStrong: '#232832',
  grouped: '#0DFFFFFF',
  elevated: '#1D222B',
  ink: '#F2F4F7',
  muted: '#A2A9B6',
  subtle: '#7A8291',
  primary: '#6F89FF',
  primaryPressed: '#5672F5',
  primarySoft: '#19213F',
  accent: '#6F89FF',
  accentSoft: '#19213F',
  inverse: '#F2F4F7',
  onInverse: '#0B0D11',
  success: '#4CC07D',
  successSoft: '#122A1D',
  warning: '#E0A53A',
  warningSoft: '#2C2312',
  danger: '#F2736C',
  dangerSoft: '#2E1618',
  border: '#2B313C',
  separator: '#252B35',
  disabled: '#4E5562',
  white: '#FFFFFF',
  scrim: '#94000000',
  modalBackdrop: '#9E000000',
  userBubble: '#1E2430',
  toolSurface: '#141820',
  codeSurface: '#131720',
  codeHeader: '#1B212E',
  onPrimary: '#FFFFFF',
}

const standardType: HarmonyTypeScale = {
  heroSize: 32,
  heroLineHeight: 38,
  titleSize: 24,
  titleLineHeight: 30,
  headingSize: 18,
  headingLineHeight: 24,
  bodySize: 16,
  bodyLineHeight: 22,
  smallSize: 14,
  smallLineHeight: 19,
  captionSize: 12,
  captionLineHeight: 16,
}

const compactType: HarmonyTypeScale = {
  heroSize: 30,
  heroLineHeight: 36,
  titleSize: 22,
  titleLineHeight: 28,
  headingSize: 17,
  headingLineHeight: 22,
  bodySize: 15,
  bodyLineHeight: 20,
  smallSize: 13,
  smallLineHeight: 17,
  captionSize: 11,
  captionLineHeight: 15,
}

interface AccentSwatch {
  lightPrimary: string
  lightPressed: string
  lightSoft: string
  darkPrimary: string
  darkPressed: string
  darkSoft: string
  darkOnPrimary: string
}

function accentSwatch(accent: string): AccentSwatch {
  if (accent === 'emerald') {
    return {
      lightPrimary: '#0D9488', lightPressed: '#0F766E', lightSoft: '#E6F7F5',
      darkPrimary: '#2DD4BF', darkPressed: '#14B8A6', darkSoft: '#112E2B', darkOnPrimary: '#08201E',
    }
  }
  if (accent === 'violet') {
    return {
      lightPrimary: '#7C5CFC', lightPressed: '#6442EE', lightSoft: '#F1EDFF',
      darkPrimary: '#A78BFA', darkPressed: '#8B5CF6', darkSoft: '#221C3D', darkOnPrimary: '#FFFFFF',
    }
  }
  if (accent === 'amber') {
    return {
      lightPrimary: '#D97706', lightPressed: '#B45309', lightSoft: '#FEF3C7',
      darkPrimary: '#F59E0B', darkPressed: '#D97706', darkSoft: '#33240E', darkOnPrimary: '#1A1104',
    }
  }
  if (accent === 'graphite') {
    return {
      lightPrimary: '#27272A', lightPressed: '#18181B', lightSoft: '#ECEEF2',
      darkPrimary: '#E4E4E7', darkPressed: '#D4D4D8', darkSoft: '#272A32', darkOnPrimary: '#0B0D11',
    }
  }
  return {
    lightPrimary: '#4D6BFE', lightPressed: '#3A56E6', lightSoft: '#EBEFFF',
    darkPrimary: '#6F89FF', darkPressed: '#5672F5', darkSoft: '#19213F', darkOnPrimary: '#FFFFFF',
  }
}

/** Mirrors Android's resolveThemeColors so native Harmony surfaces use the same visual tokens. */
export function resolveHarmonyTheme(dark: boolean, accent: string = 'deepseek'): HarmonyThemeColors {
  const base = dark ? darkColors : lightColors
  const swatch = accentSwatch(accent)
  return {
    ...base,
    primary: dark ? swatch.darkPrimary : swatch.lightPrimary,
    primaryPressed: dark ? swatch.darkPressed : swatch.lightPressed,
    primarySoft: dark ? swatch.darkSoft : swatch.lightSoft,
    accent: dark ? swatch.darkPrimary : swatch.lightPrimary,
    accentSoft: dark ? swatch.darkSoft : swatch.lightSoft,
    onPrimary: dark ? swatch.darkOnPrimary : '#FFFFFF',
  }
}

export function harmonyTypeScale(density: string): HarmonyTypeScale {
  return density === 'compact' ? compactType : standardType
}

