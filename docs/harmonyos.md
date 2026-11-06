# HarmonyOS NEXT 移植记录

验证日期：2026-11-01（Asia/Shanghai）。

## 基线与原文件

- 上游：[liguobao/ds-harness-remote](https://github.com/liguobao/ds-harness-remote)，tag `v0.5.23`。
- 精确提交：`74a3c8af42a46384a6c8c59f03f4b80fae167080`。
- 参考 APK：`dsh-remote-android-v0.5.23.apk`，包名 `io.github.liguobao.dshremote`，versionName `0.5.23`，versionCode `68`；由 Android aapt 读取。
- APK SHA-256：`4cec0c7c2d913b4eb7caaa654591ceab549d490cce354c65b73785c088ae5b3c`。
- 独立本地分支：`codex/harmony-next`。原 Downloads 目录中的已有未提交源码与旧 HAP 均保留。
- 新工程：`apps/harmony`。应用版本 `0.5.23` / `6801`；移植迭代号 `0.5.23-harmony.1`。

本机原先已有一套未提交鸿蒙工程及 1.1 MB 的 HAP。源码审查发现其 CryptoService 使用 Math.random 与异或模拟密钥和加密，ConnectionService 的消息及 RPC 格式也未遵循上游协议；本次没有把它当作已通过验收的移植成果。仅复用了其基础工程配置和图标资源，在独立的上游 v0.5.23 工作树实现客户端。

## 架构与边界

ArkUI 页面 → 静态 JSON DTO → 本地打包 TypeScript → 上游 RemoteClientCore / HarnessAlphaClient / CodeX / ACP → 上游 SecureTransport + AdaptiveTransport（强制 Relay）→ 鸿蒙原生 WebSocket。

CryptoFramework 提供 CSPRNG，真正的 Noise IK 来自上游 packages/crypto。没有编写另一套业务协议或伪加密，也没有改 Host 的 allowlist。HTTP 使用 RCP 且关闭重定向，避免凭据跟随重定向。Asset 持久化身份与凭据；聊天、审批句柄、图片不持久化。Host fingerprint 首次由人确认，后续不同公钥拒绝连接。

原生 JS 适配层是同一个 HAP 内的本地模块，编译为 Ark 字节码。不是 WebView、远端脚本，也不依赖 Android/Expo runtime。共享代码的 Node 测试只作为协议/适配验证，不能替代 Ark runtime 真机测试。

## 首轮验证（harmony.1 历史记录）

- 真实 SDK 声明下 TypeScript 检查通过。
- 真实 Hvigor / ArkTS 编译、资源编译与 HAP 打包通过。SDK 26.0.0，Hvigor 6.26.8；没有配置签名。
- 3 个测试文件、10 个核心测试通过。覆盖 Asset Map 契约/锁屏读取失败、HTTP 禁止重定向、UTF-8/CSPRNG 适配、显式信任/公钥变化、服务器隔离、身份恢复、设备列表错误保留、断开时取消迟到连接、请求未完成期间的一次审批及断开失效。
- 其中一项集成测试启动了真正的上游单账号 Relay Server，走真实 loopback HTTP/WebSocket、账号登录、双方设备注册、同账号 membership、Noise IK、加密 RPC，再以新的 Relay counter 重放旧 Noise 密文，确认关闭通道。只有鸿蒙系统 API 使用 Node 契约替身；服务器、网络、加密与 RPC 没有 mock。
- 测试中的 `Secure receive failed` 是主动重放攻击被拒绝时的预期日志，不是正常会话成功日志。
- 本机 hdc 设备列表为空，未完成手机/平板安装、截图、相册、扫码登录、真实 Harness/CodeX/ACP 工作区或后台切换验收。
- unsigned HAP 的成功构建不代表可直接安装。签名、设备适配和实际后端验收仍是交付限制。

## 后续验收

- [ ] 使用设备调试 Profile 签名，安装并确认实际 Ark runtime 启动与系统接口可用。
- [ ] 默认公网服务与自部署服务：密码/扫码、凭据刷新、主机指纹核对与拒绝。
- [ ] Harness：工作区、新会话、分页历史、文字/图片、工具、一次审批、用户提问、停止与模型切换。
- [ ] 各启用的 CodeX/ACP 后端分别验证历史、流式、审批、取消和模型。
- [ ] 锁屏、后台、进程重启、服务器更换、横竖屏、大字体、深色模式。
- [ ] 按 apps/harmony/README.md 的功能缺口推进 Android 功能对等；当前不宣称全量移植完成。


## harmony.2 并存安装与真机启动（2026-11-01）

- 冲突已确认：手机已有 Android 版 DSH Remote 0.5.23（68），同包名 `io.github.liguobao.dshremote` 在 BMS 扩展登记。未卸载或覆盖该应用。
- 鸿蒙版改为独立包名 `io.github.dshremote.harmony`，桌面标签「DSH Remote 鸿蒙」，versionCode 6802，内部迭代号 0.5.23-harmony.2。
- 新包 TypeScript 检查与真实 SDK/Hvigor HAP 构建通过；本次仅更改应用身份与标签，未修改协议/会话逻辑。
- 使用本机 HoKit 1.8.10 完成初始化检查、设备授权、签名及安装；HoKit 显示安装成功，bm dump 确认独立包名、0.5.23 / 6802。
- 真机：华为 HarmonyOS 测试设备（LMR-AL10），系统 7.0.0.111 / API 26。解锁后启动 EntryAbility，投屏确认 ArkUI 原生登录页正常显示。
- 只确认安装与首次启动，不将其扩大为账号登录、网络会话、后台稳定性或全部功能通过。
- 签名 HAP 和首次启动截图保存于本机 deliverables/dsh-remote-harmony-0.5.23-harmony.2；签名密钥、证书密码、个人 Profile 不进入仓库。

## harmony.3：连接主机时 Stack overflow 修复（2026-11-01）

- 真机在信任已保存的主机页面报 `Stack overflow!`，应用日志出现重复 `napi_new_instance`。
- 根因：全局 `WebSocket` 被兼容类覆盖，NetworkKit `createWebSocket()` 从全局读取构造函数，再次进入兼容类构造，形成无限递归。参见 [OpenHarmony 工厂实现](https://github.com/openharmony/communication_netstack/blob/master/utils/napi_utils/src/module_template.cpp) 的 `DefineClass` / `NewInstanceWithSharedManager`。
- 修复：保留系统全局构造函数，esbuild 仅将共享代码内的自由 `WebSocket` 引用绑定到模块导入的 `harmonyPlatform.NativeWebSocket`；不修改上游共享协议实现。
- 回归用例模拟原生工厂查找全局构造函数的行为：旧实现抛出 Maximum call stack size exceeded，修复后通过。11 项核心测试（含真实本地 Relay / Noise IK / 重放拒绝）、SDK 类型检查及 ArkTS/HAP 构建通过。
- versionCode 6803，内部版本 0.5.23-harmony.3。复用 HoKit 已有目标设备 Profile、证书及随软件分发的签名工具完成签名，hdc 更新安装成功；未卸载应用或删除安全存储。
- 真机更新后由用户点击同一主机连接，截图确认 `Noise IK · 加密中继` 状态及真实 Harness 工作区列表；新应用进程日志未出现 Stack overflow 或递归 NAPI 构造错误。未发送测试 Prompt，模型回复、文件操作及其余功能不计为本次验收。

## harmony.4：会话列表全部显示「新对话」修复（2026-11-02）

- 真机现象：进入工作区后每条 Harness 会话都显示「新对话」，看不到主机上的真实任务名称。
- 根因：官方 `session/list` 行不在顶层放 `title`，名称在 `projections.values`（`title`、`sessionListMetadata.title` 等）。Android 经 `resolveSessionDisplayTitle`（`apps/android/src/screens/session-title.ts`）解析，鸿蒙 `core/runtime.ts` 此前只读 `session.title`，因此全部回落到占位文案。本机 `~/.dsh/storages/session_projcache` 的 27 条会话投影证实：17 条有非空 `title` 投影，顶层字段缺失。
- 修复：鸿蒙复用同一 Android 解析函数（纯类型依赖，不引入 React Native）；会话行与聊天页标题统一走该解析。回合结束（`turn/end`）后回读一次 `sessionList`，只合并 `title`/`projections`/`blank` 显示字段，失败静默，不把改名刷新报成连接错误。
- ArkUI 列表键此前只用 `row.id`，改名后 ForEach 判定同一项不重绘；键改为 `id|name|description`，重命名与「回复中」状态即时可见。
- 回归：新增 1 个契约测试，覆盖投影取名、空白会话回落、回合结束刷新改名；把解析退回旧的 `session.title` 时该测试失败（`['新对话', '新对话']`），修复后通过。12 项核心测试、SDK 类型检查与 HAP 构建通过。
- versionCode 6804，内部版本 0.5.23-harmony.4；复用 HoKit 已有目标设备 Profile、证书及随软件分发的签名工具签名，hdc 更新安装成功，未卸载或清理数据。真机显示验收见下。

## harmony.4 真机验收与 harmony.5：主机离线报错本地化（2026-11-02）

- 真机确认 harmony.4 的会话名称修复生效：`default-workspace` 列表显示「安装并授权夸克网盘Skill」「校园小黄文创作」等主机标题，聊天页标题同步显示，不再全为「新对话」。
- 用户报「无法连接主机」时，手机画面为 `host is offline`。排查结果不是客户端回归：服务器设备列表与信任页均显示 `darwin · 离线`，本机 ping/ARP 显示主机所在 Mac mini 当时未响应；主机恢复在线后同一入口连接成功并进入 `Noise IK · 加密中继`。
- 缺陷是提示：鸿蒙 `safeError` 未查 Android 的本地化错误表，服务器英文文本直接透出。修复后 `HOST_OFFLINE`/`DEVICE_OFFLINE` 走 `strings.errors`，并对只有英文文本、没有错误码的旧 Server 响应做 `is offline` 兜底；信任页新增主机离线提示行。
- 新增 1 个契约测试：服务器返回 HOST_OFFLINE 时显示中文原因、不建立已连接状态、不打开 transport。13 项核心测试、SDK 类型检查与 HAP 构建通过；versionCode 6805，复用 HoKit 已有证书/Profile 与自带签名工具签名，hdc 更新安装，未清数据。

## harmony.6：第一批功能补全（2026-11-02）

对照 `docs/harmonyos-gap.md` 的 A 类清单，本批补全只依赖现有 Host 投影、不新增协议能力的项：

- 会话总览页：跨工作区列出会话，后端标签切换、按工作区分组或平铺、手动/最近更新排序、收藏与最近访问、归档筛选（隐藏/全部/仅已归档）、每组默认 3 条并可展开剩余、标题搜索。
- 轨迹视图：聊天页在「消息 / 轨迹」之间切换，按分类筛选、整行搜索，展示轮次、时间、预览与附件数。
- 消息操作行：分支（fork）、点赞/点踩反馈、token 计数。
- 视图状态迁移到 `@ohos.data.preferences`（库名 `dsh.remote.prefs`），按 `服务器|账号|主机` 作用域隔离；Asset 仍只存身份与凭据，偏好写入失败不影响操作结果。
- 呈现差异：鸿蒙用整页总览替换 Android 的抽屉浮层；Android 列表键与分组交互按其语义重实现，不复制 RN 组件。
- 新增 6 个契约测试；`check`、`test`、HAP 构建通过；versionCode 6806，内部版本 0.5.23-harmony.6。

## harmony.7：第二批功能补全（2026-11-02）

- 输入区「更多操作」面板：拍照、相册、文件三种附件入口，模式与操作权限预设，快捷提示词库新建/编辑/删除，把尚未开始的对话移动到其他工作区。主机未发布预设时面板内提示而不是报错。
- 排队消息 dock：读取 Host inbox 投影，展示排队中的消息并支持移出队列。
- 工作区管理：会话列表 ⋮ 菜单重命名、上移、下移、删除；CodeX 与 ACP 工作区为共享只读目录，操作前拦截。
- 信任页「解除这台主机的绑定」走 `removeAccountDevice`，与 Android 的 Host 移除等价。
- 按会话保存未发送文本草稿（上限 4000 字符），重进会话恢复。
- 与 Android 的交互差异：更多操作在鸿蒙是平铺 chip 面板，Android 为逐项下钻；提示词编辑复用同一表单页而不是独立路由。
- 新增 7 个契约测试（含 CodeX/ACP 只读拦截、主机无预设时 fail-quiet、草稿与队列投影）；`check`、`test`、HAP 构建通过；versionCode 6807，内部版本 0.5.23-harmony.7。

## harmony.8：修复偏好存储首次读取竞态（2026-11-02）

- 现象：冷启动后收藏、最近访问、分组与排序选择可能全部回落默认值，重启一次才生效。
- 根因：`EntryAbility.onWindowStageCreate()` 里 `attachContext()` 是 async 且未等待，`loadContent()` 紧接着执行；页面触发的 `initialize()` 可能在 `dataPreferences.getPreferences()` resolve 之前就跑完 `loadLocalPrefs()`，此时 store 为 `undefined`，`prefRead` 全部静默返回空串。写入路径同样可能在 store 就绪前丢弃首帧偏好。
- 修复：`attachContext()` 改为同步保存 context，实际的 `attachPreferences()` 在 `initialize()` 内、`loadLocalPrefs()` 之前 await，保证首次读取有序；ArkTS 侧声明同步签名，页面不必再处理 Promise。
- 偏好 store 缺失时仍按原设计降级为进程内状态，不阻塞登录与连接。
- 测试改为在 `beforeEach` 统一注入 context，去掉各用例内重复的 await；26 项测试与 `check` 通过；versionCode 6808，内部版本 0.5.23-harmony.8。

## harmony.9：界面对齐安卓版与自动连接主机（2026-11-02）

界面（`entry/src/main/ets/pages/Index.ets`）：

- 会话总览从独立整页改为安卓那样的右侧抽屉：主机名、⟳ 刷新、✕ 关闭、＋ 新建对话、后端标签、「工作区」标题行加 🔍/⚙ 工具栏、可选搜索框、视图选项面板、分组列表与「展开剩余 N 个会话」。抽屉是本地覆盖层，不再占用 runtime 的 `view`，因此 `overview` 动作被移除，归档与删除工作区后回到工作区页。
- 后端标签在工作区页顶部常驻（DSH / CodeX / ACP 系），与安卓的 `workspaces-screen.tsx` 标签页一致。
- 「更多操作」由平铺 chip 改为下钻：首屏是拍照/相册/文件三宫格加「工作区 / 模式 / 操作权限」三行（行尾显示当前值），点击进入对应选择页，返回键回到首屏。文案沿用安卓 `zh-CN` 的 `chat.selectMode`、`chat.approvalMode`、`chat.moveSessionHint`。
- 快捷提示词从「更多操作」里拆出，成为输入区独立 chip，并按安卓的三级结构实现：提示词列表（点击即发送）→ 编辑提示词（列表＋＋新建）→ 编辑器。
- 工作区行支持长按进入「管理工作区」表单（与 ⋮ 入口并存）。
- 空会话按后端显示安卓的欢迎文案（`welcomeTitle`/`welcomeBody`/`policyHint` 七套）加「预览版」标记。

自动连接（`core/runtime.ts`）：

- 直接复用安卓的 `lib/auto-connect.ts`（`resolveAutoConnectDevice`：仅当记住的主机仍 `trusted` 且服务器报告 `online`）与 `services/connection-recovery.ts`（`ForegroundConnectionRecovery`：连接成功后才 arm，离线时按 1s/3s/8s 重试，预算用尽回调 `onExhausted`）。鸿蒙侧用 `phase`/`retryable`/`armed` 映射到该类要求的 store 快照，`transportPreference` 固定 `relay`。
- 触发点：`initialize()` 恢复凭据后、`register()` 登录后、`EntryAbility.onForeground()`。断线重连后回到原工作区与原会话（`reconnect` → `openHostConnection(id, 'restore')`）。
- 边界：`connectHost` 拆出 `openHostConnection(id, kind)`，`manual` 与 `auto` 都会重新校验本地信任记录与公钥，`restore` 保留导航与目录；公钥不匹配的报错文本被 `identityMismatch()` 识别后置 `retryable=false`，不进入重试。手动「断开」置 `autoConnectMuted`，直到下一次显式连接成功；退后台调用 `onBackground()`，走 `disconnect(..., muteAutoConnect=false)`，因此回前台仍可恢复。
- 记住的主机存在 `@ohos.data.preferences` 的 `lastHost.<服务器>|<账号>`，不进 Asset；退出登录与解除该主机绑定时清除。
- 未做：后台长时任务与完成通知（缺口文档 B 类），因此仍不宣称持续后台保活。
- 新增 6 个契约测试（冷启动自动连接且不落 Asset、离线/撤销信任/换钥三种不自动连接、手动断开抑制回前台重连、退后台后回前台可重连、断线重试并回到原会话且不重放发送）；32 项测试、SDK 类型检查与 HAP 构建通过；versionCode 6809，内部版本 0.5.23-harmony.9。
