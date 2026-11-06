import { readFile, writeFile, unlink } from 'node:fs/promises'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import os from 'node:os'
const app = fileURLToPath(new URL('..', import.meta.url))
const clt = process.env.HARMONYOS_CLT_ROOT ?? path.join(os.homedir(), 'Tools/command-line-tools')
const config = JSON.parse(await readFile(path.join(app, 'tsconfig.json'), 'utf8'))
config.compilerOptions.paths['@ohos.*'] = [path.join(clt, 'sdk/default/openharmony/ets/api/@ohos.*.d.ts')]
config.compilerOptions.paths['@hms.*'] = [path.join(clt, 'sdk/default/hms/ets/api/@hms.*.d.ts')]
const file = path.join(app, 'tsconfig.sdk.local.json')
try {
  await writeFile(file, JSON.stringify(config))
  const result = spawnSync(process.execPath, [path.join(app, '../../node_modules/typescript/bin/tsc'), '--noEmit', '-p', file], { stdio: 'inherit' })
  process.exitCode = result.status ?? 1
} finally { await unlink(file) }
