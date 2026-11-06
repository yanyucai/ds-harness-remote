import { checkedBotView } from '../../android/src/services/bot-view'
import { resolve, viewScope, viewInputs, inputDefault, choiceValue, asText, validateViewAnswer } from '../../android/src/vendor/ds-bot/views.js'

const dictionary = () => Object.create(null)
let pending = {}, view, inputs = dictionary(), forms = dictionary(), selections = dictionary(), revision = '', token = '', sending = false, submitted = false, errorText = '', replySequence = 0, pendingReply = 0
const disabled = () => pending.disabled === true || sending || submitted
const tr = (key, fallback) => pending.labels?.[key] || fallback
const host = document.getElementById('body')
const send = value => window.ReactNativeWebView.postMessage(JSON.stringify(value))
const node = (tag, text) => { const element = document.createElement(tag); if (text !== undefined) element.textContent = String(text); return element }
window.__setBotToken = value => { token = value }
function button(label, callback) { const value = node('button', label); value.disabled = disabled(); value.onclick = callback; return value }
function reply(action, own) {
  if (disabled()) return
  const values = viewInputs(view).length ? { ...own, inputs } : own
  if (validateViewAnswer(view, action, values).error) { document.getElementById('error').textContent = tr('invalid','Please check your answers'); return }
  sending = true; pendingReply = ++replySequence; errorText = ''; draw()
  send({ type: 'botReply', token, viewId: pending.id, replyId: pendingReply, action, values })
}
function chart(value, scope) {
  const holder = node('div'), svg = document.createElementNS('http://www.w3.org/2000/svg','svg')
  svg.setAttribute('viewBox','0 0 360 200'); svg.setAttribute('role','img'); svg.setAttribute('aria-label', value.caption || 'Chart')
  const categories = value.categories ?? [], series = value.series ?? [], palette = ['#4b78e6','#e69b42','#38a374','#bc729f']
  const values = series.flatMap(row => row.values.map(v => Number(resolve(v,scope,NaN))))
  if (!values.every(Number.isFinite)) return node('p','Invalid chart data')
  const magnitude = Math.max(1,...values.map(Math.abs)), low = Math.min(0,...values.map(n=>n/magnitude)), high = Math.max(0,...values.map(n=>n/magnitude)), span = high-low || 1
  const x = i=>48+(i+0.5)*284/categories.length, y=v=>164-(v/magnitude-low)/span*140, base=y(0)
  function shape(tag, attrs) { const e=document.createElementNS(svg.namespaceURI,tag); for (const [key,v] of Object.entries(attrs)) e.setAttribute(key,String(v)); svg.append(e);return e }
  if (value.kind === 'donut') {
    const list=series[0]?.values.map(v=>Number(resolve(v,scope,0)))??[],total=list.reduce((a,b)=>a+Math.max(0,b/magnitude),0);let offset=0
    list.forEach((v,i)=>{const length=total?Math.max(0,v/magnitude)/total*408.4:0;shape('circle',{cx:180,cy:95,r:65,fill:'none',stroke:palette[i%4],'stroke-width':26,'stroke-dasharray':`${length} ${408.4-length}`,'stroke-dashoffset':-offset,transform:'rotate(-90 180 95)'});offset+=length})
  } else series.forEach((row,g)=>{
    const list=row.values.map(v=>Number(resolve(v,scope,0))),color=palette[g%4]
    if(value.kind==='line'||value.kind==='area') shape('path',{d:'M '+list.map((v,i)=>`${x(i)},${y(v)}`).join(' L ')+(value.kind==='area'?` L ${x(list.length-1)},${base} L ${x(0)},${base} Z`:''),stroke:color,'stroke-width':2,fill:value.kind==='area'?color:'none','fill-opacity':0.15})
    else list.forEach((v,i)=>{if(value.kind==='hbar'){const zero=48+(0-low)/span*284,end=48+(v/magnitude-low)/span*284;shape('rect',{x:Math.min(zero,end),y:24+i*140/categories.length+g*112/categories.length/series.length,width:Math.abs(end-zero),height:Math.max(.5,100/categories.length/series.length),fill:color})}else shape('rect',{x:48+i*284/categories.length+g*228/categories.length/series.length,y:Math.min(y(v),base),width:Math.max(.5,210/categories.length/series.length),height:Math.abs(y(v)-base),fill:color})})
  })
  holder.append(svg)
  const table=node('table');const header=node('tr');header.append(node('th',value.caption||''));for(const row of series)header.append(node('th',row.name));table.append(header)
  categories.forEach((label,i)=>{const tr=node('tr');tr.append(node('td',asText(label)));for(const row of series)tr.append(node('td',Number(resolve(row.values[i],scope,NaN))));table.append(tr)})
  holder.append(table); return holder
}
function render(value, depth=0) {
  if(depth>32)return node('span')
  const scope=viewScope(view,inputs),display=v=>asText(resolve(v,scope,'—')),id=value.id??'',box=node('section')
  if(value.label)box.append(node('label',value.label))
  switch(value.type){
    case 'row':box.className='row';
    case 'stack':for(const child of value.children??[])box.append(render(child,depth+1));break
    case 'text':case 'callout':box.append(node('p',display(value.text)));break
    case 'metric':box.append(node('strong',display(value.value)),node('small',display(value.caption)));break
    case 'progress':{const progress=node('progress'),max=Number(resolve(value.max,scope,0));const percent=value.percent!==undefined?Number(resolve(value.percent,scope,0)):max>0?Number(resolve(value.value,scope,0))/max*100:0;progress.max=100;progress.value=Number.isFinite(percent)?Math.max(0,Math.min(100,percent)):0;box.append(progress);break}
    case 'chart':box.append(chart(value,scope));break
    case 'table':{const table=node('table'),head=node('tr');for(const col of value.columns??[])head.append(node('th',col.label||col.key));table.append(head);for(const row of value.rows??[]){const tr=node('tr');for(const cell of row)tr.append(node('td',display(cell)));table.append(tr)}box.append(table);break}
    case 'sources':for(const source of value.items??[]){const a=node('a',source.label||source.url);a.href='#';a.onclick=e=>{e.preventDefault();send({type:'link',url:source.url})};box.append(a)}break
    case 'html':box.append(node('p',value.summary||''),node('small',tr('html','HTML preview is unavailable')));break
    case 'slider':case 'number':case 'toggle':case 'choice':{
      if(value.type==='choice'){for(const option of value.options??[])box.append(button(option.label,()=>{inputs[id]=choiceValue(option);draw()}));break}
      const input=node('input');input.disabled=disabled();input.type=value.type==='toggle'?'checkbox':value.type==='slider'?'range':'number';input.setAttribute('aria-label',value.label||id)
      const current=Object.hasOwn(inputs,id)?inputs[id]:inputDefault(value);input.checked=current===true;input.value=String(current??'');for(const key of ['min','max','step'])if(value[key]!==undefined)input[key]=value[key]
      input.onchange=()=>{inputs[id]=value.type==='toggle'?input.checked:Number(input.value);draw()};box.append(input);break
    }
    case 'options':{const selected=new Set(selections[id] || []);for(const option of value.options??[]){const label=node('label'),input=node('input');input.type=value.multi?'checkbox':'radio';input.name=id;input.disabled=disabled();input.checked=selected.has(option.label);label.append(input,node('span',option.label),node('small',option.description||''));input.onchange=()=>{if(!value.multi)selected.clear();if(input.checked)selected.add(option.label);else selected.delete(option.label);selections[id]=[...selected]};box.append(label)}box.append(button(tr('submit','Submit'),()=>reply(id,{selected:[...selected]})));break}
    case 'confirm':box.append(button(value.cancelLabel||tr('reject','Cancel'),()=>reply(id,{confirmed:false})),button(value.confirmLabel||tr('confirm','Confirm'),()=>reply(id,{confirmed:true})));break
    case 'form':{const fields=forms[id]||(forms[id]=dictionary());for(const field of value.fields??[]){const label=node('label',field.label),input=node('input');input.placeholder=field.placeholder||'';input.maxLength=2000;input.disabled=disabled();input.value=fields[field.id]||'';input.oninput=()=>{fields[field.id]=input.value};label.append(input);box.append(label)}box.append(button(value.submitLabel||tr('submit','Submit'),()=>reply(id,{fields})));break}
    case 'submit':box.append(button(value.label||tr('submit','Submit'),()=>reply(id,{})));break
    default:box.append(node('small',tr('unknown','Unsupported card')))
  }
  return box
}
function draw(){host.replaceChildren();if(!view){host.append(node('p',tr('unknown','Invalid card')));return}host.append(node('h3',pending.title||''),render(view));const error=node('p');error.id='error';error.textContent=errorText;error.setAttribute('role','status');host.append(error);if(sending||submitted)host.append(node('p',tr(sending?'sending':'sent',sending?'Sending…':'Submitted')))}
window.receive=value=>{const blueprint=checkedBotView(value),next=JSON.stringify([value.id,blueprint]);if(next!==revision){revision=next;inputs=dictionary();forms=dictionary();selections=dictionary();sending=false;submitted=false;pendingReply=0;errorText=''}pending=value;view=blueprint;draw()}
window.__botReplyResult=(id,ok,replyId)=>{if(id!==pending.id||replyId!==pendingReply||!sending)return;sending=false;submitted=ok===true;errorText=ok?'':tr('failed','Delivery not confirmed; please try again');draw()}
new ResizeObserver(()=>send({type:'height',height:document.body.scrollHeight})).observe(document.body)
send({type:'ready'})
