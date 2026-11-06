import { build } from 'esbuild'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { existsSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs'
const app = fileURLToPath(new URL('..', import.meta.url))
const root = path.resolve(app, '../..')
const generated = path.join(app, 'entry/src/main/ets/generated')
const shared = Object.fromEntries(['crypto', 'protocol', 'client-core', 'webrtc'].map(name => [
  `@dsh-remote/${name}`, path.join(root, `packages/${name}/src/index.ts`),
]))
await build({
  entryPoints: [path.join(app, 'core/platform.ts')], outfile: path.join(generated, 'platform.js'),
  bundle: true, platform: 'neutral', format: 'esm', target: 'es2020', external: ['@ohos.*', '@hms.*'],
})
await build({
  entryPoints: [path.join(app, 'core/runtime.ts')], outfile: path.join(generated, 'runtime.js'),
  bundle: true, platform: 'browser', format: 'esm', target: 'es2020', alias: shared,
  define: { WebSocket: 'harmonyPlatform.NativeWebSocket' },
  banner: { js: 'import * as harmonyPlatform from "./platform.js"; harmonyPlatform.installPlatform();' },
  external: ['@ohos.*', '@hms.*', './platform.js'],
  legalComments: 'eof', metafile: true,
}).then(result => {
  const forbidden = Object.keys(result.metafile.inputs).filter(name => /react-native|expo-secure|expo-crypto/.test(name))
  if (forbidden.length) throw new Error(`Android native dependency in Harmony bundle: ${forbidden.join(', ')}`)
  const licenses = new Map()
  for (const input of Object.keys(result.metafile.inputs)) {
    if (!input.includes('node_modules/')) continue
    let folder = path.dirname(path.resolve(input))
    let pkg
    while (folder !== path.dirname(folder)) {
      if (existsSync(path.join(folder, 'package.json'))) {
        const candidate = JSON.parse(readFileSync(path.join(folder, 'package.json'), 'utf8'))
        if (candidate.name && candidate.version) { pkg = candidate; break }
      }
      folder = path.dirname(folder)
    }
    if (!pkg) throw new Error(`Cannot identify bundled dependency: ${input}`)
    const key = `${pkg.name}@${pkg.version}`
    if (licenses.has(key)) continue
    const file = ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENSE-MIT'].find(name => existsSync(path.join(folder, name)))
    if (!file) throw new Error(`Missing bundled dependency license: ${key}`)
    licenses.set(key, readFileSync(path.join(folder, file), 'utf8'))
  }
  const notice = ['DSH Remote HarmonyOS native port — Third-party licenses',
    'Upstream ds-harness-remote (MIT):', readFileSync(path.join(root, 'packages/plugin/LICENSE'), 'utf8'),
    ...[...licenses].sort(([left], [right]) => left.localeCompare(right)).map(([name, license]) => `${name}\n${license}`),
  ].join('\n\n----------------------------------------\n\n')
  writeFileSync(path.join(app, 'THIRD_PARTY_NOTICES.txt'), notice)
  const rawfile = path.join(app, 'entry/src/main/resources/rawfile')
  mkdirSync(rawfile, { recursive: true })
  writeFileSync(path.join(rawfile, 'THIRD_PARTY_NOTICES.txt'), notice)

})
console.log('Harmony native platform and shared protocol bundles generated.')
