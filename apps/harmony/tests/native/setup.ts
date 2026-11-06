import * as harmonyPlatform from '../../core/platform'

// Vitest transforms modules independently, unlike the production ESM bundle's
// module-local import. Apply the same free-identifier binding for shared code.
Object.assign(globalThis, { harmonyPlatform })
