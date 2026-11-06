import { nativeLabels } from './native-labels'
import { alignmentLabels } from './alignment-labels'
import { getActiveLanguage, messageCatalogs } from '../../android/src/locales/i18n'
const paths = new Map<string,string[]>()
function index(value: unknown,path: string[]=[]):void {
  if(typeof value==='string'){if(!paths.has(value))paths.set(value,path);return}
  if(value&&typeof value==='object')for(const [key,row]of Object.entries(value))index(row,[...path,key])
}
index(messageCatalogs['zh-CN'])
const native: Record<string,string[]> = {
  '会话活动':['Session activity','會話活動','会話のアクティビティ','Actividad de la sesión','Sitzungsaktivität','Activité de la session'],
  '管理对话':['Manage conversations','管理對話','会話を管理','Gestionar conversaciones','Unterhaltungen verwalten','Gérer les conversations'],
  '选择主机目录':['Choose host directory','選擇主機目錄','ホストのフォルダーを選択','Elegir directorio del equipo','Host-Verzeichnis auswählen','Choisir le dossier hôte'],
  '启动恢复上次对话':['Restore last conversation on launch','啟動恢復上次對話','起動時に最後の会話を復元','Restaurar última conversación al iniciar','Letzte Unterhaltung beim Start wiederherstellen','Restaurer la dernière conversation au démarrage'],
  '新建 / 编辑任务':['Create / edit task','新增 / 編輯任務','タスクの作成・編集','Crear / editar tarea','Aufgabe erstellen / bearbeiten','Créer / modifier une tâche'],
  '编辑自动化任务':['Edit scheduled tasks','編輯自動化任務','自動タスクを編集','Editar tareas programadas','Geplante Aufgaben bearbeiten','Modifier les tâches planifiées'],
  '智能体与群组':['Agents and groups','智慧體與群組','エージェントとグループ','Agentes y grupos','Agenten und Gruppen','Agents et groupes'],
  '展开输入':['Expand composer','展開輸入','入力欄を展開','Expandir editor','Eingabe erweitern','Développer la saisie'],
  '收起输入':['Collapse composer','收起輸入','入力欄を折りたたむ','Contraer editor','Eingabe einklappen','Réduire la saisie'],
  '查看输出':['View output','查看輸出','出力を表示','Ver salida','Ausgabe anzeigen','Afficher la sortie'],
  '部分输出已截断，仅显示末尾内容':['Earlier output was truncated; showing the tail','部分輸出已截斷，僅顯示末尾內容','前の出力は省略され、末尾のみ表示','Salida anterior truncada; se muestra el final','Frühere Ausgabe gekürzt; Ende wird angezeigt','Sortie précédente tronquée ; fin affichée'],
}
const locales=['en-US','zh-TW','ja-JP','es-ES','de-DE','fr-FR']
export function translateNative(source:string):string {
  const language=getActiveLanguage();if(language==='zh-CN')return source
  const custom=alignmentLabels[source]??native[source]??nativeLabels[source];if(custom)return custom[locales.indexOf(language)]??custom[0]
  const background = /^后台持续任务不可用（([^）]+)）$/.exec(source)
  if (background) return `${translateNative('后台持续任务不可用')} (${background[1]})`
  const numbered = /^(图片|子任务|已归档|排队中) (\d+)(?: 条消息)?$/.exec(source)
  if (numbered) {
    const labels: Record<string,string[]> = { '图片':['Image','圖片','画像','Imagen','Bild','Image'], '子任务':['Subtasks','子工作','サブタスク','Subtareas','Unteraufgaben','Sous-tâches'], '已归档':['Archived','已封存','アーカイブ済み','Archivadas','Archiviert','Archivées'], '排队中':['Queued','排隊中','待機中','En cola','In Warteschlange','En attente'] }
    return `${labels[numbered[1]][locales.indexOf(language)]} ${numbered[2]}`
  }
  const path=paths.get(source)
  let value:unknown=messageCatalogs[language]
  if(path){for(const key of path)value=value&&typeof value==='object'?(value as Record<string,unknown>)[key]:undefined;if(typeof value==='string')return value}
  return source
}
