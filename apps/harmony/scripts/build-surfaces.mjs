// Local, reviewed renderers only. Invoked during the final build phase.
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, resolve } from 'node:path'
import { build } from 'esbuild'
import { createHash } from 'node:crypto'
const app = resolve(import.meta.dirname, '..')
const android = resolve(app, '../android')
const out = resolve(app, 'entry/src/main/resources/rawfile')
await mkdir(out, { recursive: true })
const inline = code => code.replaceAll('</script', '<\\/script').replaceAll('<!--', '<\\!--')
const bridge = `<script>window.ReactNativeWebView={postMessage:function(raw){if(window.top===window&&window.dshNative)window.dshNative.post(raw)}};for(const n of ['log','warn','error','info','debug'])console[n]=function(){};window.open=function(){return null}</script>`
for (const [name, generator] of [['terminal','terminal'], ['pdf','pdf'], ['mermaid','mermaid']]) {
  await import(resolve(android, `scripts/build-${generator}.mjs`))
  const source = await readFile(resolve(android, `src/generated/${name}-html.ts`), 'utf8')
  const literal = source.slice(source.indexOf(' = ') + 3).trim().replace(/;$/, '')
  let html = JSON.parse(literal)
  html = html.replace('</head>', `${bridge}</head>`)
  if (name === 'terminal') html = html.replace('window.receive = message => {', 'window.receive = message => {')
  await writeFile(resolve(out, `${name}.html`), html)
}
const rendererPath = resolve(app, 'vendor/intelligent-ui/renderer.js')
const renderer = await readFile(rendererPath)
const rendererHash = createHash('sha1').update(Buffer.from(`blob ${renderer.length}\0`)).update(renderer).digest('hex')
if (rendererHash !== 'ebac4a4c2199383458d4e1fa2121be0e6043c5c0') throw new Error('Pinned Intelligent UI renderer content differs from Android release baseline')
process.env.DSH_INTELLIGENT_UI_RENDERER_BUNDLE = rendererPath
process.env.DSH_REQUIRE_INTELLIGENT_UI = '1'
await import(resolve(android, 'scripts/build-intelligent-ui.mjs'))
const card = await readFile(resolve(android, 'src/screens/intelligent-ui-card.tsx'), 'utf8')
const fn = card.slice(card.indexOf('function documentFor('), card.indexOf('export function IntelligentUiCard'))
const ui = await readFile(resolve(android, 'src/generated/intelligent-ui-renderer-code.ts'), 'utf8')
const result = await build({ stdin: { contents: ui + '\n' + fn + '\nexport {documentFor}', loader: 'ts' }, format: 'esm', write: false, target: 'es2020' })
const module = await import('data:text/javascript;base64,' + Buffer.from(result.outputFiles[0].text).toString('base64'))
await writeFile(resolve(out,'intelligent.html'), module.documentFor('DSH_TOKEN_PLACEHOLDER').replace('var token="DSH_TOKEN_PLACEHOLDER";', 'var token="";window.__setDiuiToken=function(v){token=v};').replace('</head>', bridge + '</head>'))
const require = createRequire(resolve(android, 'package.json'))
const mermaidCode = await readFile(resolve(dirname(require.resolve('mermaid/package.json')), 'dist/mermaid.min.js'),'utf8')
const markdownCode = await build({ entryPoints: [resolve(app,'surfaces/markdown.js')], minify: true, bundle: true, write: false, format: 'iife', target: 'es2020', nodePaths: [resolve(android,'node_modules')] })
const markdown = `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">${bridge}<style>html,body{background:transparent}body{margin:8px;font:15px/1.5 system-ui;overflow-wrap:anywhere}pre{overflow:auto;padding:12px;background:#8881;border-radius:8px}pre button{display:block;color:#4b78e6;background:transparent;border:0;padding:4px}code{font-family:monospace}table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid #8885;padding:6px}img{max-width:100%}a{color:#4b78e6}blockquote{border-left:3px solid #888;padding-left:12px}</style></head><body><main id="body"></main><script>${inline(mermaidCode)}</script><script>window.mermaid.initialize({startOnLoad:false,securityLevel:'strict'});</script><script>${inline(markdownCode.outputFiles[0].text)}</script></body></html>`
await writeFile(resolve(out,'markdown.html'),markdown)
const bot = await build({ entryPoints: [resolve(app,'surfaces/bot-view.js')], bundle: true, write: false, format: 'iife', target: 'es2020' })
await writeFile(resolve(out,'bot.html'),`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'none'; img-src data:; base-uri 'none'; form-action 'none'">${bridge}<style>body{margin:8px;font:15px/1.5 system-ui;color:#888;background:transparent}section{margin:8px 0}label,small{display:block}button,input{min-height:40px;margin:4px;max-width:95%}button{border:1px solid #8885;border-radius:8px;padding:6px 12px;color:inherit;background:#8881}input{color:inherit;background:#8881;border:1px solid #8885}table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid #8885;padding:6px}.row{display:flex;flex-wrap:wrap;gap:8px}a{color:#4b78e6}svg{width:100%}p{white-space:pre-wrap}#error{color:#c64b43}</style></head><body><main id="body"></main><script>${inline(bot.outputFiles[0].text)}</script></body></html>`)
await writeFile(resolve(out,'INTELLIGENT_UI_LICENSE.txt'),await readFile(resolve(app,'vendor/intelligent-ui/LICENSE'),'utf8'))
