# 鸿蒙移植版与安卓版功能差异（基线 v0.5.23）

> 当前版本已升级为 0.6.3-harmony.29（6830），比较基准 origin/main 24160bd5。下文为历史记录，当前实现及验证矩阵见 [harmonyos-alignment-0.6.3.md](harmonyos-alignment-0.6.3.md)。历史“缺 RTC/renderer/终端”等结论不再代表当前实现；未验收项也不能算通过。

## 最新复核：harmony.24（2026-11-05，versionCode 6825）

本节为当前源码复核结果；下方 harmony.9 分层表保留为历史基线，不是当前完成清单。

本批修复：恢复失败后继续有限重试，主机查询失败也能退出挂起；恢复参数 forceRelay 生效；服务端 retryable=false 时停止自动重试；返回取消后迟到结果不再重开会话；恢复期间回前台保留当前会话。已信任设备连接不再先切入指纹页，每次仍重新查询身份并校验固定公钥。聊天增加已完成/已停止/回复失败状态，保留思考与错误详情。原生 HTTP 层保留非 JSON 429/5xx 的状态分类，避免误报数据格式错误；成功响应仍要求有效 JSON。

| 能力 | 当前代码与验收边界 | 后续工作 |
| --- | --- | --- |
| 长时任务、通知、文件预览、插件/任务、CodeX 分页 | 已有调用和界面，部分真机写入与多后端路径待验收 | 分场景真机验证 |
| LAN/P2P/TURN | 已有偏好与探测参数；共享 AdaptiveTransport 需要 rtcFactory 或全局 RTCPeerConnection，鸿蒙适配未提供 RTC 实现 | 原生 RTC 接入，不能称为直连已实现 |
| 终端 | runtime.stripTerminalAnsi 剥离控制序列后展示文本，与安卓 xterm 渲染不同 | 屏幕缓冲、光标、全屏应用与 resize |
| 多语言 | 偏好与共享 strings 已接入，Index.ets 仍有大量中文 | 替换全部界面文案，不能称全界面多语言对等 |
| 工具访问与恢复偏好 | 鸿蒙未完整对齐 Android 工具访问面板、阅读位置与上次会话 | 优先补偏好与对应交互 |
| 真实模型完整回复与工具调用 | harmony.23 验证了发送与缺少 API Key 的失败回传 | 待可用 Host 模型配置后验证成功生成 |

本批 check、78 项测试及构建通过。真机覆盖安装与启动；连接测试观察到身份接口一次返回非 JSON HTTP 429，随后正常返回字段；加密连接仍失败，目录一度报告主机离线。自动恢复故障注入测试不计作真机网络切换验证。日志在 harmony.24 交付目录中。

生成日期：2026-11-02（Asia/Shanghai），并在同一台 HarmonyOS 测试设备 上完成了安卓版真机走查。对照对象：`apps/android`（React Native/Expo）与 `apps/harmony`（ArkUI/ArkTS，内部版本 0.5.23-harmony.9 / versionCode 6809）。

本文件在 harmony.6 与 harmony.7 两批补全后更新，并在 harmony.9 复核了界面对齐与自动连接：A 类已完成项标 ✅ 并注明落点构建，未做项保持原样。✅ 只表示代码已实现并通过 `check`/`test`/`build` 与装机，真机逐项验收仍以文末「验收口径」为准。

## 口径

- 能力上限由 Host 侧固定 allowlist 决定：`packages/plugin/src/harness-remote-bridge.ts:110` 的 `HARNESS_REMOTE_ALLOWLIST`。两端任何新功能只能来自这些端点，超出的设想一律需要 Host 改动。
- 共享数据面已经打进鸿蒙包：`packages/client-core/src/harness-alpha-client.ts`、`packages/crypto`、`packages/protocol`、`packages/webrtc`，以及 Android 的平台无关逻辑（`state/event-reducer.ts`、`screens/session-title.ts`、`services/codex.ts`、`services/cursor.ts` 等）。因此「已具备调用点、只缺界面」的功能属于低成本补全。
- 鸿蒙侧的实际能力面以 `apps/harmony/core/runtime.ts` 的 `perform()` 动作表为准。基线走查时为 22 个动作（login、qr、cancelQr、refresh、inspectHost、trustHost、connect、disconnect、catalog、workspace、session、newSession、newWorkspace、prompt、interrupt、approval、question、model、history、logout、renameHost、back）；harmony.6 与 harmony.7 补全后新增 backend、groupMode、sortMode、archiveFilter、toggleGroup、showMore、favorite、archive、fork、feedback、morePanel、selectMode、selectPermission、queueAction、saveDraft、savePrompt、deletePrompt、renameWorkspace、deleteWorkspace、moveWorkspace、moveSession、forgetHost，harmony.9 再加 reconnect 并移除 overview（会话列表改为本地抽屉覆盖层，不再占用导航状态），共 45 个动作。界面以 `apps/harmony/entry/src/main/ets/pages/Index.ets`（现 1127 行）为准。下面所有「鸿蒙缺失」都对照过这两处，不是按 Android 源码推测。

## 真机核对方法与结论

安卓版与鸿蒙版共存于同一台 HarmonyOS 测试设备，包名不同：鸿蒙包 `io.github.dshremote.harmony`，安卓版跑在系统的安卓兼容层（`/data/virt_service/rgm_hmos/anco_hmos_data/…`）里，`bm dump -a` 只列鸿蒙 bundle，查不到它。

核对手段因此受限，但不是不可用：

- `hdc shell uitest dumpLayout` 对安卓容器无效，导出的层级只有 `com.ohos.sceneboard` 和状态栏（83 个节点，无应用内容），拿不到元素文本和坐标。
- `hdc shell snapshot_display` 能截到安卓版画面，配合 `uitest uiInput click/longClick/swipe` 按屏幕比例换算坐标（设备 1276×2848，回显图 918×2048，系数 ≈1.39）即可逐屏走查。本轮截图存于 `artifacts/harmony-fix/a-*.jpeg`。

两台 Host 不同（鸿蒙连 `host-a.local`，安卓连 `host-b.local`），因此下面区分了两类差异：客户端功能差异按安卓版界面判定；Host 侧插件与模型目录差异不计入鸿蒙缺口。

## 已对等的部分

| 领域 | 鸿蒙现状 |
| --- | --- |
| 账号与设备 | 服务器自定义、邮箱密码登录、本机注册、凭据恢复与刷新、退出本机账号、同账号主机列表、主机重命名 |
| 扫码授权 | GitHub / 知乎二维码本地渲染、轮询、取消 |
| 安全连接 | 系统 CSPRNG、Noise IK、X25519/ChaChaPoly、首次指纹确认、公钥变更拦截、加密中继、重放拒绝 |
| 本机存储 | 安全资产（Asset）保存身份与凭据，按服务器与账号隔离，锁定失败不重置身份 |
| Harness | 工作区列表与创建、会话新建与切换、历史与更早分页、流式文字/思考/工具详情、发送、停止、一次审批、用户提问表单、模型与推理强度、会话名称投影 |
| CodeX / ACP | CodeX 与 Pi / Claude / OpenCode / Antigravity / Cursor 目录、历史、流式、取消、一次审批、模型目录 |
| 原生交互 | 系统深浅色、列表搜索、正文与详情复制、系统相册选图 |
| 后台语义 | 转后台主动断开并取消待审批，回前台手动重连 |
| 会话浏览（harmony.6） | 跨工作区总览、后端标签、分组/平铺、手动与最近排序、收藏、最近访问、归档筛选、每组展开剩余、标题搜索、轨迹视图、消息分支与点赞点踩与 token 计数 |
| 输入区（harmony.7） | 更多操作面板、拍照/相册/文件附件、模式与操作权限预设、快捷提示词库、空白会话移动工作区、排队消息 dock（移出/立即发送）、按会话草稿 |
| 主机与工作区管理（harmony.7） | 工作区重命名/上移/下移/删除（CodeX 与 ACP 只读拦截）、解除主机绑定 |
| 界面对齐（harmony.9） | 会话抽屉、后端标签常驻、「更多操作」下钻、快捷提示词三级、工作区长按管理、按后端空态文案与「预览版」标记 |
| 自动连接（harmony.9） | 冷启动/登录/回前台自动连接记住且仍在线受信任的主机；断线 1s/3s/8s 有限重试并回到原会话；手动断开后抑制；指纹确认与公钥变更拦截不变 |

一处有意的差异：鸿蒙把多后端目录合并成一张工作区列表（`runtime.ts:loadCatalog`，后端名写在工作区副标题），安卓版用 DSH / CodeX / OpenCode 三个标签页分栏。数据都在，只是呈现不同，不算缺失，但见 A 类「后端分栏」。

## 差距分层

### A 类：可直接补全（共享代码已有调用点或无需新端点，缺 ArkUI 与本机持久化）

会话与浏览：

| 功能 | Android 位置 | 已就绪的共享调用点 | 鸿蒙改动量 |
| --- | --- | --- | --- |
| ✅ 轨迹模式（对话/轨迹切换）〔harmony.6〕 | `screens/chat-trajectory.tsx` | 无新端点，直接读现有时间线 | 中：搜索消息/工具/轮次，全部·系统·用户·上下文·助手·工具六个分类，轮次标注，逐条展开，附件计数，「仅显示已加载的真实消息」提示 |
| ✅ 会话抽屉与视图选项〔harmony.6〕 | `screens/host-sessions-drawer.tsx:65` | `workspace/follow` 的 `archivedSessionIds`（`harness-alpha-client.ts:594,1022`） | 中：按工作区分组 / 平铺列表、手动排序 / 最近更新、隐藏已归档 / 全部对话 / 仅已归档、最近访问分组、每工作区默认 3 条加「展开剩余 N 个会话」、工作区搜索、新建工作区入口 |
| ✅ 后端分栏〔harmony.6〕 | `screens/workspaces-screen.tsx` | 已在 `loadCatalog` 结果里 | 小：把合并列表按 DSH / CodeX / OpenCode 分标签，图标随后端变化（DSH 文件夹、CodeX `</>`） |
| ✅ 收藏工作区〔harmony.6〕 | `workspaces-screen.tsx` 星标 | 本机偏好即可 | 小 |
| ✅ 会话归档 / 取消归档〔harmony.6〕 | `workspaces-screen.tsx` | `harness-alpha-client.ts:594` | 小 |
| ✅ 空白会话移动到工作区〔harmony.7〕 | `chat-screen.tsx:1432` | 现有 `session/create` + `archiveSession` | 小：仅未发言会话可移，已发言改为「在目标工作区新建对话」 |
| ✅ 消息 token 计数〔harmony.6〕 | `screens/message-actions.tsx` | 现有 usage 字段 | 小：气泡下方与复制、分支并排 |
| ✅ 会话分支 fork〔harmony.6〕 | `services/message-actions.ts` | `harness-alpha-client.ts:331` | 小：消息操作行 |
| ✅ 回答点赞/点踩〔harmony.6〕 | `state/session-actions.ts` | `harness-alpha-client.ts:315-325` | 小 |
| ✅ 排队消息移除 / 立即发送〔harmony.7〕 | `screens/chat/*` | `harness-alpha-client.ts:535` | 小-中：需要「排队中 N 条消息 / 等待执行」行渲染 |
| 子任务会话面板 | `screens/chat/agents.tsx:16` | `sessionList` 已带子会话标记 | 小-中：标题栏入口 + 列表跳转 |
| 对话信息面板 | `screens/chat/session-info.tsx` | 现有主机/工作区/会话字段 | 小 |
| ✅ 空态与欢迎文案〔harmony.9〕 | `chat-screen.tsx` 的 welcome* 串 | 无 | 小：按后端切换文案，含品牌空态与「预览版」标记 |

输入区：

| 功能 | Android 位置 | 已就绪的共享调用点 | 鸿蒙改动量 |
| --- | --- | --- | --- |
| ✅ 更多操作面板〔harmony.7〕 | `chat-screen.tsx` 的 `moreActions` | 汇总下面几项 | 中：三宫格附件 + 四行设置，是其余输入区功能的入口 |
| ✅ 拍照 / 文件附件〔harmony.7〕 | 同上 | 同一附件通道 | 中：相机权限申请与 `@ohos.file.picker` 文档选择；鸿蒙现在只有相册 |
| ✅ 快捷提示词库〔harmony.7〕 | `services/storage.ts:336-400`（`dshremote.custom-prompts.v1`） | 无新端点，点击即发送 | 中：内置提示词 + 增删改，落本机首选项 |
| ✅ 模式（Agent 预设）〔harmony.7〕 | `screens/chat/pickers.tsx` | `harness-alpha-client.ts:386,397` | 中：标准 / PTC / 极简 / 创造四档，且只能在开场前改，改后要提示新建会话 |
| 工具访问开关 | `chat/pickers.tsx` | `connection.requireSessionTools()` | 小-中：提示词 / 文件 / 终端三项开关 |
| ✅ 操作权限预设〔harmony.7〕 | `chat/pickers.tsx` | 已有 | 小：仅可查看 / 工作区内修改 / 完全权限三档带说明 |
| Slash 命令 | `services/session-tools.ts` | `harness-alpha-client.ts:377` | 中：命令面板 |
| 紧凑历史开关 | `state/preference-actions.ts` | `connection.configureHistory` | 小 |
| ✅ 草稿与超长拦截〔harmony.7〕 | `state/preference-actions.ts` | 本机存储 | 小 |

主机与工作区管理：

| 功能 | Android 位置 | 已就绪的共享调用点 | 鸿蒙改动量 |
| --- | --- | --- | --- |
| ✅ 工作区重命名、删除〔harmony.7〕 | `workspaces-screen.tsx:672` 管理工作区表单 | `harness-alpha-client.ts:582,590` | 小-中：确认框；CodeX 工作区只读，改名/排序/删除由电脑端管理，需要按后端禁用 |
| ✅ 工作区手动排序（上移/下移）〔harmony.7〕 | `workspaces-screen.tsx:672-673` | `harness-alpha-client.ts:599` `workspace/insertBefore` | 小 |
| ✅ 移除主机 / 解除绑定〔harmony.7〕 | `services/api.ts:189,194` | 同一 `RemoteServerApi`，已在包内 | 小：两个按钮加确认框 |
| 文件树与只读预览 | `screens/workspace-files-panel.tsx`、`services/workspace-file-preview.ts` | `connection.requireSessionTools()`（`workspaceFiles/*`、`officeToPdf/*`） | 中：服务层无 RN 依赖，可直接打包；界面与下载缓存需重写 |
| 插件管理页 | `screens/plugins-modal.tsx` | `harness-alpha-client.ts:628-687` | 中：列表 + 按 schema 生成的设置表单 |
| 自动化任务管理 | `screens/automation-tasks-modal.tsx` | `harness-alpha-client.ts:608-628` | 中 |
| CodeX 历史分页 | `state/session-actions.ts` | 共享 CodeX 目录逻辑 | 小-中 |
| 多语言与主题密度 | `state/preference-actions.ts`、`locales/i18n` | 已在包内（现固定 `zh-CN`） | 中：偏好项落盘 |

存储边界已按上述建议落地：收藏、最近访问、分组/排序/归档筛选、折叠状态、提示词库与会话草稿全部走 `@ohos.data.preferences`（库名 `dsh.remote.prefs`，见 `core/platform.ts:attachPreferences`），按 `服务器|账号|主机` 作用域隔离；Asset 只留身份与凭据。harmony.8 另外修掉了首选项的初始化竞态，见 `docs/harmonyos.md`。

### 呈现差异（harmony.9 已按安卓版对齐）

基线走查记录的几处差异已在 harmony.9 消除：会话总览改为右锚抽屉（带半透明遮罩与 ✕/遮罩关闭）；「更多操作」改为三宫格加下钻行；快捷提示词拆成列表→编辑→新建三级并移到输入区 chip；工作区管理增加长按入口（⋮ 保留）；后端标签在工作区页顶部常驻。

仍然保留的差异，验收时不要按安卓截图逐像素比对：抽屉没有安卓的左滑关闭手势，只用遮罩与 ✕；视图选项在鸿蒙是抽屉内展开的选项块，安卓是浮动 popover；安卓抽屉里的「插件」「自动化」两个导航项在鸿蒙没有（对应页面尚未移植，见 A 类）；提示词编辑器与列表同层，安卓是独立路由页。

### B 类：需要额外系统能力或产品决策

| 功能 | 阻碍点 | 可行路径 |
| --- | --- | --- |
| 交互终端 | Android 用 `react-native-webview` 渲染主机送来的屏幕快照（`screens/terminal-panel.tsx:163`） | 端点 `terminal/follow|write|resize` 与 `services/terminal-attachment.ts`（无 RN 依赖）可复用；鸿蒙需二选一：ArkWeb 承载同一 HTML，或自研原生屏幕缓冲（含 ANSI、键位、resize） |
| Intelligent UI 卡片 | 同样依赖 WebView 沙箱与固定版本渲染器 | ArkWeb + 与 Android 一致的「不执行模型 HTML」边界；工作量大 |
| Bot 模式与智能体团队面板 | 卡片解释器、审批与状态机 UI；团队快照来自 bot 状态 | `connection.requireBotClient()` 与 `plugin.route`/`api/bot` 白名单可复用，界面基本重写 |
| 主机网络详情 | 安卓有 ICE 路径、往返延迟、可用上行带宽、本次流量、连接时间；鸿蒙是 Relay-only，没有这些指标 | 先补中继侧可得的连接时间与收发字节；其余等 P2P 落地 |
| 浏览器 OAuth 回跳、账号注册 | 需要 App Linking / Deep Link 与服务器域名校验文件 | 需服务器与域名配置配合，属跨端项目 |
| 完成通知、后台保活与自动重连 | 通知权限、HarmonyOS 长时任务（continuous task）申请与理由合规 | 自动重连已在 harmony.9 落地（直接复用 `services/connection-recovery.ts` 与 `lib/auto-connect.ts`，仅前台）；后台保活与完成通知仍需单独申请与验收 |
| LAN / P2P / TURN 直连 | 鸿蒙无系统级 WebRTC，`packages/webrtc` 依赖 werift 的 ICE/DTLS/SCTP | 需要基于 `@ohos.net.socket` 自建传输或引入原生库，建议单列项目；当前 Relay-only 已能保持同一 Noise 密文边界 |

### C 类：不宣称对等

平板完整双栏、读屏无障碍细节、Remote Tools 注入（Host 默认关闭）、Desktop 专属的 loopback 预览。另外真机验收仍未覆盖：扫码登录、相册图片、真实模型回复、各 ACP/CodeX 后端全链路、锁屏与横竖屏切换。安卓版本轮只核对界面与入口，未逐项触发写操作（删除工作区、归档、fork 等），补做时应在测试 Host 上进行。

## 建议推进顺序

第 1～5 项已在 harmony.6 与 harmony.7 落地，第 6 项的「偏好迁出 Asset」已在 harmony.6 完成，其余按下面顺序推进：

1. 真机逐项验收 harmony.6-9 新增界面与自动连接，尤其是拍照附件、文件选择、模式与权限下钻、提示词三级、队列 dock、工作区删除、抽屉与后端标签，以及冷启动/回前台自动连接和断线重试；这些是新代码，尚未在设备上跑过。
2. 输入区收尾：工具访问开关（提示词/文件/终端三项）、Slash 命令面板、紧凑历史开关。
3. 子任务会话面板与对话信息面板。
4. 文件树与只读预览（`workspaceFiles/*`、`officeToPdf/*`，服务层无 RN 依赖可直接打包）。
5. 插件管理页、自动化任务管理、CodeX 历史分页。
6. 本地偏好：多语言、主题与密度、阅读位置、上次会话。
7. 完成通知与自动重连。
8. 终端。
9. Bot 模式与 Intelligent UI。
10. P2P/TURN 与主机网络详情（单列项目，不与上述混排）。

## 验收口径

沿用 `apps/harmony` 的 `check`/`test`/`build` 加真机验证。协议、加密、授权、fail-closed 与状态机改动补契约测试；纯界面与文案不单独加测试。任何阶段都不把鸿蒙版描述成与 Android 功能对等或已发布版本。

2026-11-06 真机验收补充：harmony.29 已验证启动/自动 LAN 连接、工作区层级与长路径、持续任务状态、更新查询、系统应用详情跳转及文件下载选择器取消；修复旧 settings action 无匹配错误。文件落盘、真实通知、长期锁屏和逐后端尚未完成验收，详见 docs/harmonyos-alignment-0.6.3.md。
