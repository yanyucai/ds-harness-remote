import MarkdownIt from 'markdown-it'
import { installMath } from '../../android/src/ui/markdown-math'
import { renderMathSvg } from '../../android/src/ui/math-svg'
const send = value => window.ReactNativeWebView.postMessage(JSON.stringify(value))
const md = new MarkdownIt({ html: false, linkify: true, breaks: true })
installMath(md)
for (const name of ['math_block','math_inline']) md.renderer.rules[name] = (tokens,index) => {
  const source = tokens[index].content, result = renderMathSvg(source, name === 'math_block')
  return result ? `<span role="img" aria-label="${md.utils.escapeHtml(source)}" style="display:${name==='math_block'?'block':'inline-block'};overflow:auto">${result.xml}</span>` : md.utils.escapeHtml(source)
}
let revision = 0
window.__image = (stamp,index,uri) => { if (stamp !== revision || !/^data:image\/(png|jpeg|gif|webp);base64,/.test(uri)) return; const image=document.querySelector(`[data-image="${index}"]`);if(image)image.src=uri }
window.receive = async value => {
  const stamp = ++revision
  document.body.style.color = value.dark ? '#ddd' : '#222'
  document.body.style.fontSize = value.density === 'standard' ? '16px' : '15px'
  document.body.style.lineHeight = value.density === 'standard' ? '1.7' : '1.5'
  document.getElementById('body').innerHTML = md.render(value.text || '')
  let index = 0
  for (const image of document.images) {
    const source = image.getAttribute('src') || ''
    if (source.startsWith('data:image/')) continue
    image.removeAttribute('src')
    if (/^(https?:)?\/\//i.test(source) || /^[a-z]+:/i.test(source) && !source.startsWith('workspace:')) { image.replaceWith(document.createTextNode(image.alt || '[image]'));continue }
    image.setAttribute('data-image', String(++index))
    send({ type: 'image', path: source, stamp, id: index })
  }
  for (const block of document.querySelectorAll('pre')) {
    const code=block.querySelector('code');if(!code || code.classList.contains('language-mermaid'))continue
    const copy=document.createElement('button');copy.textContent=value.copyLabel || 'Copy';copy.onclick=()=>send({type:'copy',text:code.textContent});block.prepend(copy)
  }
  for (const code of document.querySelectorAll('code.language-mermaid')) {
    try { const result = await window.mermaid.render(`diagram-${stamp}-${Math.random().toString(36).slice(2)}`,code.textContent);if(stamp!==revision)return;const diagram=document.createElement('div');diagram.innerHTML=result.svg;code.parentNode.replaceWith(diagram) } catch { /* Keep the original source visible. */ }
  }
}
document.addEventListener('click',event=>{const link=event.target.closest('a');if(link){event.preventDefault();send({type:'link',url:link.getAttribute('href')})}})
new ResizeObserver(()=>send({type:'height',height:document.body.scrollHeight})).observe(document.body)
send({type:'ready'})
