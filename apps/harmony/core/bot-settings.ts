import { object, objects, text, type BotState } from '../../android/src/services/bot-catalog'
import { DS_BOT_CONNECTOR_CATALOG, DS_BOT_IM_PLATFORMS, buildDsBotUsageView, type UsageRangeId } from '../../android/src/screens/bot/ds-bot-usage-data'
export interface BotSettingsRow { id: string; title: string; text: string; state: string }
const labels: Record<string,string> = { thinking:'显示思考', enterToSend:'回车发送', motion:'动画风格', defaultModel:'默认模型', workDir:'工作目录', status:'状态', connected:'已连接', enabled:'已启用', available:'可用', name:'名称', model:'模型', provider:'服务商', tools:'工具', description:'说明', channel:'渠道', platform:'平台', permission:'权限', scope:'范围', title:'标题' }
const summary = (raw: unknown): string => Object.entries(object(raw)).filter(([key,value]) => key in labels && (typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number')).map(([key,value])=>`${labels[key]}：${String(value)}`).join('\n')
export function botSettingsRows(state: BotState, page: string, remote: unknown, range: UsageRangeId = '7d'): BotSettingsRow[] {
  const row = (id:string,title:string,body:string,status=''):BotSettingsRow=>({id,title,text:body,state:status})
  if (page === 'general') return [row('prefs','通用',summary(state.prefs)),row('folder','团队工作区',state.workspaceId || '主机尚未返回工作区')]
  if (page === 'models') return objects(object(remote).providers).map((value,index)=>row(text(value.id)||String(index),text(value.name)||text(value.id),summary(value)+'\n模型：'+objects(value.models).map(model=>text(model.name)||text(model.id)).join('、')))
  if (page === 'local-agents') return Object.entries(object(remote)).map(([key,value])=>row(key,key,typeof value==='boolean'?(value?'可用':'不可用'):summary(value)))
  if (page === 'connectors') {
    const live = objects(state.connectors?.items)
    return DS_BOT_CONNECTOR_CATALOG.map(value=>{const connected=live.find(item=>text(item.id)===value.id||text(item.name)===value.name);return row(value.id,value.name,value.desc+'\n'+(connected?summary(connected):'未配置；请在主机 DS-Bot 设置中完成授权。'),connected?.connected===true?'已连接':'未连接')})
  }
  if (page === 'im') return DS_BOT_IM_PLATFORMS.map(value=>row(value.id,value.name,summary(object(state.im)[value.id])+'\n'+summary(object(state.imStatus)[value.id])||'请在主机配置此渠道。'))
  if (page === 'capabilities') return (state.capabilities ?? []).map((value,index)=>row(text(value.id)||String(index),text(value.name)||text(value.id),summary(value)+'\n'+summary(object(state.capabilityStatuses)[text(value.id)])))
  if (page === 'browser') return state.bots.flatMap(bot=>(bot.browserGrants??[]).map((grant,index)=>row(`${bot.id}:${index}`,bot.name,summary(grant)))).concat([row('browser','浏览器',state.browser===true?'主机已启用浏览器能力':'主机尚未启用浏览器能力')])
  if (page === 'computer') return [row('computer','电脑操控',summary(state.computer)+'\n'+summary(state.computerLive)),row('policy','使用说明','此页面展示主机能力状态。电脑访问与授权由主机 DS-Bot 管理。')]
  if (page === 'secrets') return (state.secrets??[]).map((value,index)=>row(text(value.id)||String(index),text(value.name)||text(value.id),'••••••\n'+summary({scope:value.scope,description:value.description})))
  if (page === 'usage') {
    const view=buildDsBotUsageView(object(remote),range)
    return [row('total','总用量',`输入 ${view.total.input} · 输出 ${view.total.output} · 调用 ${view.total.calls}`),...view.byOwner.map(owner=>row(owner.key,owner.name,`输入 ${owner.input} · 输出 ${owner.output} · 调用 ${owner.calls}`))]
  }
  return []
}
