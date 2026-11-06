import { runtime } from '../RuntimeHost'
import { ViewState, BotExtra, NamedOption, emptyState, CatalogRow, ActivityRow, JobRow, TaskDefinition, BotDefinition, BotRoom, BotRequest, DirectoryEntry } from '../models/ViewState'
interface Choice { id: string; name: string }
interface TaskTiming { kind?: string; at?: string; every_seconds?: number; daily?: TaskDaily; weekly?: TaskWeekly; cron?: TaskCron }
interface TaskDaily { time: string; time_zone: string }
interface TaskWeekly extends TaskDaily { weekdays: number[] }
interface TaskCron { expression: string; time_zone: string }
interface TaskRequest { title: string; prompt: string; after_seconds?: number; at?: string; every_seconds?: number; daily?: TaskDaily; weekly?: TaskWeekly; cron?: TaskCron }
interface BotPayload { id?: string; roomId?: string; sessionId?: string; name?: string; role?: string; instructions?: string; model?: string; effort?: string; members?: string[]; admin?: string; notice?: string; text?: string; questionId?: string; answer?: string; choice?: string }

/** Native controls for the upstream workflows, not an arbitrary RPC/JSON console. */
@Component
export struct AlignmentPanel {
  @Prop state: ViewState = emptyState()
  @Prop availableHeight: number = 480
  @Prop mode: string = 'activity'
  onClose: () => void = () => {}
  onPath: (path: string) => void = () => {}
  @State selected: string = ''
  @State selectedSession: string = ''
  @State name: string = ''
  @State body: string = ''
  @State detail: string = ''
  @State model: string = ''
  @State effort: string = ''
  @State kind: string = 'after'
  @State seconds: string = '3600'
  @State timing: string = ''
  @State zone: string = 'Asia/Shanghai'
  @State weekdays: string = '1,2,3,4,5'
  @State members: string[] = []
  @State category: string = 'all'
  @State filter: string = ''
  @State confirmation: string = ''
  @State botKind: string = 'bot'
  @State operation: string = 'update-bot'
  private t(value: string): string { return runtime.translate(value) }
  private run(action: string, payload: string = '{}'): void { runtime.perform(action,payload).catch(() => {}) }
  private bot(op: string, payload: BotPayload): void { this.run('botOperation',JSON.stringify({ mode:op,text:JSON.stringify(payload) })) }
  private chooseTask(row: TaskDefinition): void {
    this.selected=row.id;this.selectedSession=row.sessionId;this.name=row.title;this.body=row.prompt;this.kind=row.kind==='after'?'at':row.kind
    this.seconds=String(row.afterSeconds??row.everySeconds??3600);this.timing=row.time??(row.kind==='cron'?row.expression??'':row.scheduledAt)
    this.zone=row.timeZone??'Asia/Shanghai';this.weekdays=(row.weekdays??[1,2,3,4,5]).join(',')
  }
  private saveTask(): void {
    const request: TaskRequest={title:this.name,prompt:this.body}
    const change: TaskTiming={kind:this.kind}
    if(this.kind==='after') {
      request.after_seconds=Number(this.seconds)
      if(this.selected) { change.kind='at';change.at=new Date(Date.now()+Number(this.seconds)*1000).toISOString() }
    }
    if(this.kind==='at'){request.at=this.timing;change.at=this.timing}
    if(this.kind==='every'){request.every_seconds=Number(this.seconds);change.every_seconds=Number(this.seconds)}
    if(this.kind==='daily'){request.daily={time:this.timing,time_zone:this.zone};change.daily=request.daily}
    if(this.kind==='weekly'){request.weekly={time:this.timing,time_zone:this.zone,weekdays:this.weekdays.split(',').map((v:string)=>Number(v))};change.weekly=request.weekly}
    if(this.kind==='cron'){request.cron={expression:this.timing,time_zone:this.zone};change.cron=request.cron}
    this.run('taskSave',JSON.stringify({text:JSON.stringify({id:this.selected||undefined,session:this.selectedSession,request:request,change:this.selected?change:undefined})}))
  }
  @Builder
  activity() {
    Scroll() {
      Column({space:10}) {
        Select([{value:this.t('全部')},{value:this.t('待办')},{value:this.t('目标')},{value:this.t('团队')},{value:this.t('子任务')}])
          .value(this.t('活动筛选')).onSelect((index:number)=>{this.category=['all','todos','goal','team','subagents'][index]})
        ForEach(this.state.activity.rows.filter((row:ActivityRow)=>this.category==='all'||row.category===this.category),(row:ActivityRow)=>{
          Column({space:5}) {
            Text(`${row.status==='completed'?'✓':row.status==='in_progress'?'●':'○'} ${row.title}`).fontSize(15).width('100%')
            Text(this.t(row.status)).fontSize(11).fontColor($r('sys.color.font_secondary')).width('100%')
            if(row.detail)Text(row.detail).fontSize(12).copyOption(CopyOptions.LocalDevice).width('100%')
            if(row.session&&this.state.sessions.some((session:CatalogRow)=>session.id===row.session))Button(this.t('打开对话')).onClick(()=>{this.run('session',JSON.stringify({id:row.session}));this.onClose()})
          }.padding(12).width('100%').backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(12)
        },(row:ActivityRow)=>`${row.category}|${row.id}|${row.status}|${row.title}`)
        Text(this.t('后台任务')).fontSize(16).width('100%')
        if(this.state.activity.loading)LoadingProgress().width(24).height(24)
        if(this.state.activity.error)Text(this.state.activity.error).fontSize(12).fontColor('#C64B43')
        ForEach(this.state.activity.jobs,(job:JobRow)=>{
          Column({space:5}) {
            Text(job.label).fontSize(14).width('100%')
            Text(`${this.t(job.status)} ${job.progress??''}`).fontSize(12).width('100%')
            if(job.detail)Text(job.detail).fontSize(12).width('100%')
            Row({space:10}) {
              Button(this.t('查看输出')).onClick(()=>{this.run('jobOutput',JSON.stringify({id:job.id}))})
              if(job.status==='running'||job.status==='stopping')Button(this.confirmation===job.id?this.t('确认停止'):this.t('停止'))
                .onClick(()=>{if(this.confirmation===job.id){this.run('jobKill',JSON.stringify({id:job.id}));this.confirmation=''}else this.confirmation=job.id})
            }
          }.padding(12).width('100%').backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(12)
        },(job:JobRow)=>`${job.id}|${job.status}|${job.progress}`)
        if(this.state.activity.outputJob) {
          if(this.state.activity.lossy)Text(this.t('部分输出已截断，仅显示末尾内容')).fontSize(11).fontColor('#9D6B20')
          Text(this.state.activity.output||this.t('等待输出')).fontFamily('monospace').fontSize(12).copyOption(CopyOptions.LocalDevice).width('100%')
        }
        if(this.state.activity.rows.length===0&&this.state.activity.jobs.length===0&&!this.state.activity.loading)Text(this.t('暂无活动')).padding(16)
      }.width('100%')
    }.width('100%').height(Math.min(480, this.availableHeight))
  }
  @Builder
  sessions() {
    Column({space:8}) {
      TextInput({text:this.filter,placeholder:this.t('搜索对话')}).onChange((v:string)=>{this.filter=v})
      TextInput({text:this.name,placeholder:this.t('新的对话名称')}).onChange((v:string)=>{this.name=v})
      List({space:8}) {
        ForEach(this.state.managedSessions.filter((row:CatalogRow)=>row.name.toLowerCase().includes(this.filter.toLowerCase())),(row:CatalogRow)=>{
          ListItem() {
            Column({space:6}) {
              Text((this.state.pinnedSessionIds.includes(row.id)?'📌 ':'')+row.name).fontSize(14).width('100%')
              Row({space:5}) {
                Button(this.t('打开')).fontSize(11).onClick(()=>{this.run('session',JSON.stringify({id:row.id}));this.onClose()})
                if(row.backend==='harness') {
                  Button(this.state.pinnedSessionIds.includes(row.id)?this.t('取消置顶'):this.t('置顶')).fontSize(11)
                    .onClick(()=>{this.run('sessionManage',JSON.stringify({id:row.id,mode:this.state.pinnedSessionIds.includes(row.id)?'unpin':'pin'}))})
                  Button(this.t('重命名')).fontSize(11).enabled(this.name.trim().length>0)
                    .onClick(()=>{this.run('sessionManage',JSON.stringify({id:row.id,mode:'rename',name:this.name}))})
                  Button(this.t('分支')).fontSize(11).onClick(()=>{this.run('sessionManage',JSON.stringify({id:row.id,mode:'fork'}))})
                }
              }
              Button(row.archived?this.t('取消归档'):this.t('归档')).fontSize(11).enabled(['harness','codex','opencode'].includes(row.backend))
                .onClick(()=>{this.run(row.archived?'sessionManage':'archive',JSON.stringify({id:row.id,mode:'unarchive'}))})
            }.padding(10).width('100%').backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(12)
          }
        },(row:CatalogRow)=>`${row.id}|${row.name}|${row.archived}|${this.state.pinnedSessionIds.includes(row.id)}`)
      }.width('100%').height(Math.min(380, this.availableHeight - 100))
    }.width('100%')
  }
  @Builder
  directory() {
    Column({space:10}) {
      TextInput({text:this.body||this.state.hostDirectory.path,placeholder:this.t('主机目录路径')}).onChange((v:string)=>{this.body=v})
      Row({space:8}) {
        Button(this.t('打开目录')).onClick(()=>{this.run('hostDirectory',JSON.stringify({path:this.body||this.state.hostDirectory.path}))})
        Button(this.t('上级目录')).onClick(()=>{const crumbs:DirectoryEntry[]=this.state.hostDirectory.crumbs??[];this.run('hostDirectory',JSON.stringify({path:crumbs.length>1?crumbs[crumbs.length-2].path:this.state.hostDirectory.home??''}))})
        Button(this.t('选择此目录')).enabled(this.state.hostDirectory.path.length>0).onClick(()=>{this.onPath(this.state.hostDirectory.path);this.onClose()})
      }
      List({space:4}) {
        ForEach(this.state.hostDirectory.entries,(entry:DirectoryEntry)=>{
          ListItem(){Text('📁 '+entry.name).padding(12).width('100%')}.onClick(()=>{this.body=entry.path;this.run('hostDirectory',JSON.stringify({path:entry.path}))})
        },(entry:DirectoryEntry)=>entry.path)
      }.height(Math.min(350, this.availableHeight - 110)).width('100%')
      if(this.state.hostDirectory.truncated)Text(this.t('目录条目过多，仅显示一部分')).fontSize(11)
    }.width('100%')
  }
  private timingTitle(): string {
    const kinds: string[] = ['after','at','every','daily','weekly','cron']
    const labels: string[] = ['延迟执行','指定时间','固定间隔','每天','每周','Cron']
    return this.t(labels[Math.max(0,kinds.indexOf(this.kind))])
  }
  @Builder
  taskForm() {
    Scroll() {
      Column({space:10}) {
        Select(this.state.taskDefinitions.map((row:TaskDefinition):SelectOption=>({value:row.title||row.id})))
          .value(this.t('选择要编辑的任务')).onSelect((index:number)=>{this.chooseTask(this.state.taskDefinitions[index])})
        Button(this.t('新建任务')).onClick(()=>{this.selected='';this.name='';this.body='';this.kind='after'})
        Select(this.state.sessions.filter((row:CatalogRow)=>row.backend==='harness').map((row:CatalogRow):SelectOption=>({value:row.name})))
          .value(this.t('所属对话')).onSelect((index:number)=>{this.selectedSession=this.state.sessions.filter((row:CatalogRow)=>row.backend==='harness')[index].id})
        TextInput({text:this.name,placeholder:this.t('任务名称')}).onChange((v:string)=>{this.name=v})
        TextArea({text:this.body,placeholder:this.t('任务提示词')}).height(110).onChange((v:string)=>{this.body=v})
        Select([{value:this.t('延迟执行')},{value:this.t('指定时间')},{value:this.t('固定间隔')},{value:this.t('每天')},{value:this.t('每周')},{value:'Cron'}])
          .value(this.timingTitle()).onSelect((index:number)=>{this.kind=['after','at','every','daily','weekly','cron'][index]})
        if(this.kind==='after'||this.kind==='every')TextInput({text:this.seconds,placeholder:this.t('间隔秒数')}).type(InputType.Number).onChange((v:string)=>{this.seconds=v})
        else TextInput({text:this.timing,placeholder:this.kind==='at'?'2026-11-06T09:00:00+08:00':this.kind==='cron'?'0 9 * * *':'09:00'}).onChange((v:string)=>{this.timing=v})
        if(['daily','weekly','cron'].includes(this.kind))TextInput({text:this.zone,placeholder:this.t('时区')}).onChange((v:string)=>{this.zone=v})
        if(this.kind==='weekly')TextInput({text:this.weekdays,placeholder:this.t('星期，以逗号分隔')}).onChange((v:string)=>{this.weekdays=v})
        Button(this.t('保存任务')).enabled(!this.state.busy&&this.name.trim().length>0&&this.body.trim().length>0&&this.selectedSession.length>0).onClick(()=>{this.saveTask()})
      }.width('100%')
    }.height(Math.min(480, this.availableHeight)).width('100%')
  }
  private selectBot(bot: BotDefinition): void {
    this.selected=bot.id;this.name=bot.name;this.detail=bot.role;this.body=bot.instructions;this.model=bot.model;this.effort=bot.effort;this.botKind='bot'
  }
  @Builder
  bots() {
    Scroll() {
      Column({space:10}) {
        Row({space:10}) {
          Button(this.t('新建智能体')).onClick(()=>{this.selected='';this.name='';this.body='';this.botKind='bot'})
          Button(this.t('新建群组')).onClick(()=>{this.selected='';this.name='';this.body='';this.botKind='room'})
        }
        Row({space:8}) {
          Button(this.t('用量')).onClick(()=>{this.run('botRead',JSON.stringify({mode:'usage'}))})
          Button(this.t('计划任务')).onClick(()=>{this.run('botRead',JSON.stringify({mode:'schedules'}))})
        }
        ForEach(this.state.botReport,(row:BotExtra)=>{
          Text(row.title).fontSize(15).width('100%')
          Text(row.text).fontSize(13).width('100%').copyOption(CopyOptions.LocalDevice)
        },(row:BotExtra)=>`report|${row.id}|${row.text}`)
        ForEach(this.state.botDefinitions,(bot:BotDefinition)=>{
          Row({space:8}) {
            Text((bot.main?'★ ':'')+bot.name).layoutWeight(1)
            Button(this.t('打开')).onClick(()=>{this.run('botSelect',JSON.stringify({id:bot.id}));this.onClose()})
            Button(this.t('编辑')).onClick(()=>{this.selectBot(bot)})
          }.width('100%')
        },(bot:BotDefinition)=>`${bot.id}|${bot.name}|${bot.main}`)
        ForEach(this.state.botRooms,(room:BotRoom)=>{
          Row({space:8}) {
            Text(room.name).layoutWeight(1)
            Button(this.t('打开')).onClick(()=>{this.run('botSelect',JSON.stringify({id:room.id}));this.onClose()})
            Button(this.t('编辑')).onClick(()=>{this.botKind='room';this.selected=room.id;this.name=room.name;this.body=room.notice;this.members=room.members;this.selectedSession=room.admin})
            if(room.paused)Button(this.t('继续')).onClick(()=>{this.bot('room-continue',{roomId:room.id})})
          }.width('100%')
        },(room:BotRoom)=>`${room.id}|${room.name}|${room.paused}`)
        Divider()
        TextInput({text:this.name,placeholder:this.t('名称')}).onChange((v:string)=>{this.name=v})
        if(this.botKind==='bot') {
          TextInput({text:this.detail,placeholder:this.t('角色')}).onChange((v:string)=>{this.detail=v})
          TextArea({text:this.body,placeholder:this.t('指令')}).height(90).onChange((v:string)=>{this.body=v})
          Button(this.t('选择模型')).onClick(()=>{this.run('botRead',JSON.stringify({mode:'models'}))})
        Select(this.state.botModelOptions.map((row:NamedOption):SelectOption=>({value:row.name}))).value(this.model).onSelect((index:number)=>{this.model=this.state.botModelOptions[index].id;this.run('botRead',JSON.stringify({mode:'efforts',name:this.model}))})
        Select(this.state.botEffortOptions.map((row:NamedOption):SelectOption=>({value:row.name}))).value(this.effort).onSelect((index:number)=>{this.effort=this.state.botEffortOptions[index].id})
        TextInput({text:this.model,placeholder:this.t('模型')}).onChange((v:string)=>{this.model=v})
          TextInput({text:this.effort,placeholder:this.t('思考强度')}).onChange((v:string)=>{this.effort=v})
          Button(this.t('保存智能体')).enabled(this.name.trim().length>0).onClick(()=>{this.bot(this.selected?'update-bot':'create-bot',{id:this.selected||undefined,name:this.name,role:this.detail,instructions:this.body,model:this.model||undefined,effort:this.effort||undefined})})
          if(this.selected) {
            Row({space:8}) {
              Button(this.t('设为主智能体')).onClick(()=>{this.bot('set-main',{id:this.selected})})
              Button(this.t('复制智能体')).onClick(()=>{this.bot('duplicate-bot',{id:this.selected})})
              Button(this.t('停止工作')).onClick(()=>{this.bot('stop-member-work',{sessionId:this.state.botDefinitions.find((row:BotDefinition)=>row.id===this.selected)?.sessionId??this.selected})})
            }
          }
        } else {
          TextArea({text:this.body,placeholder:this.t('群公告')}).height(70).onChange((v:string)=>{this.body=v})
          ForEach(this.state.botDefinitions,(bot:BotDefinition)=>{
            Toggle({type:ToggleType.Checkbox,isOn:this.members.includes(bot.id)}).onChange((on:boolean)=>{this.members=on?[...this.members,bot.id]:this.members.filter((id:string)=>id!==bot.id)})
            Text(bot.name).fontSize(13)
          },(bot:BotDefinition)=>`member|${bot.id}`)
          Select(this.state.botDefinitions.filter((bot:BotDefinition)=>this.members.includes(bot.id)).map((bot:BotDefinition):SelectOption=>({value:bot.name})))
            .value(this.t('群管理员')).onSelect((index:number)=>{this.selectedSession=this.state.botDefinitions.filter((bot:BotDefinition)=>this.members.includes(bot.id))[index].id})
          Button(this.t('保存群组')).enabled(this.name.trim().length>0&&this.members.length>=2).onClick(()=>{this.bot(this.selected?'update-room':'create-room',{id:this.selected||undefined,name:this.name,members:this.members,notice:this.body,admin:this.selectedSession||this.members[0]})})
        }
        if(this.selected)Button(this.confirmation===this.selected?this.t('确认删除'):this.t('删除')).fontColor('#C64B43')
          .onClick(()=>{if(this.confirmation===this.selected){this.bot(this.botKind==='bot'?'delete-bot':'delete-room',{id:this.selected});this.selected='';this.confirmation=''}else this.confirmation=this.selected})
        ForEach(this.state.botApprovals,(request:BotRequest)=>{
          Text(request.title+'\n'+request.detail).fontSize(13)
          Row({space:8}) {
            Button(this.t('允许一次')).onClick(()=>{this.bot('approval-answer',{id:request.id,choice:'allow'})})
            Button(this.t('拒绝')).onClick(()=>{this.bot('approval-answer',{id:request.id,choice:'reject'})})
          }
        },(request:BotRequest)=>`approval|${request.id}`)
        ForEach(this.state.botQuestions,(request:BotRequest)=>{
          Text(request.title+'\n'+request.detail).fontSize(13)
          TextInput({text:this.timing,placeholder:this.t('你的回答')}).onChange((v:string)=>{this.timing=v})
          Row({space:8}) {
            Button(this.t('回答')).onClick(()=>{this.bot('answer-question',{sessionId:request.session,questionId:request.id,answer:this.timing})})
            Button(this.t('忽略')).onClick(()=>{this.bot('dismiss-question',{sessionId:request.session,questionId:request.id})})
          }
        },(request:BotRequest)=>`question|${request.id}`)
      }.width('100%')
    }.height(Math.min(480, this.availableHeight)).width('100%')
  }
  build() {
    Column({space:12}) {
      Row() {
        Text(this.t(this.mode==='activity'?'会话活动':this.mode==='sessions'?'管理对话':this.mode==='tasks'?'编辑自动化任务':this.mode==='directory'?'选择主机目录':'智能体与群组')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('✕').backgroundColor(Color.Transparent).fontColor($r('sys.color.font_primary')).onClick(()=>{this.onClose()})
      }.width('100%')
      if(this.state.error) Text(this.state.error).fontSize(13).fontColor('#C64B43').width('100%')
      if(this.state.notice) Text(this.state.notice).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      if(this.mode==='activity')this.activity()
      else if(this.mode==='sessions')this.sessions()
      else if(this.mode==='directory')this.directory()
      else if(this.mode==='tasks')this.taskForm()
      else this.bots()
    }.padding(20).width('100%').backgroundColor($r('sys.color.background_primary')).borderRadius({topLeft:24,topRight:24})
  }
}
