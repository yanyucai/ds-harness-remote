# DSH Remote 鸿蒙原生移植预览版

当前版本 **0.6.3-harmony.30 / 6831**，比较基准为上游 Android main `24160bd52e070f55e4e5a949d111644ca4a9a763`。这是 HarmonyOS NEXT Stage / ArkUI 客户端，复用共享协议、加密、连接和平台独立逻辑。

本版修复部分 HarmonyOS 设备缺少 `performance.now()` 导致无法连接主机的问题，使用系统单调时钟补足共享连接代码所需接口。更新后已在目标设备确认 Noise IK 局域网连接、工作区/会话读取、刷新与短时后台返回；97 项核心测试、SDK 检查和原生构建通过。完整范围及剩余边界见 [对齐记录](../../docs/harmonyos-alignment-0.6.3.md)。后台持续任务、通知和安装更新使用鸿蒙方案，不能宣称与 Android 全部等效或永久保活。

为与已安装的 Android 版并存，鸿蒙版独立包名为 `io.github.dshremote.harmony`，桌面名称为「DSH Remote 鸿蒙」。Android 版仍使用上游包名 `io.github.liguobao.dshremote`。

## 早期实现记录（当前状态见上方对齐记录）

| 功能 | 本版实现 |
| --- | --- |
| 界面结构 | 与安卓版对齐：会话列表为右侧滑出的抽屉（主机名、新建对话、后端标签、搜索、视图选项、分组与展开剩余），工作区页顶部为 DSH / CodeX / ACP 后端标签，「更多操作」为下钻式面板，快捷提示词独立成列表→编辑→新建三级，工作区支持长按进入管理表单 |
| 自动连接 | 复用安卓的 `resolveAutoConnectDevice` 与 `ForegroundConnectionRecovery`：冷启动、登录与回前台时自动连接上次主机（仍受信任且服务器报告在线）；连接中断按 1s/3s/8s 有限重试并回到原工作区与会话；手动「断开」后不再自动连接，直到下一次显式连接 |
| 会话总览 | 跨工作区会话总览页，按后端标签切换、按工作区分组或平铺、手动/最近排序、收藏与最近访问、归档筛选、每组默认 3 条并可展开剩余、标题搜索 |
| 轨迹视图 | 聊天页在「消息 / 轨迹」间切换，按分类筛选、整行搜索，显示轮次、时间、预览与附件数 |
| 消息操作 | 消息操作行提供分支、点赞/点踩反馈与 token 计数 |
| 更多操作 | 输入区「更多操作」面板：拍照/相册/文件附件、模式与操作权限预设、快捷提示词库增删改、把未开始的对话移动到其他工作区 |
| 排队消息 | 主机 inbox 投影的排队消息 dock，可查看并移出队列 |
| 工作区管理 | 会话列表 ⋮ 菜单重命名、上移/下移、删除工作区；CodeX 与 ACP 工作区只读拦截 |
| 主机绑定 | 信任页解除本机与远端主机的账号设备绑定 |
| 输入草稿 | 按会话保留未发送文本草稿，重进会话恢复；重启后仍在 |
| 会话名称 | 官方 Harness 会话标题取自主机投影（`projections.values`），与 Android 同一解析入口；本机新建会话在回合结束后回读主机改名 |
| 主机状态 | 设备列表与信任页显示主机在线/离线；服务器错误码复用 Android 中文文案表 |
| 账号与设备 | 自定义服务器、邮箱密码登录、本机注册、设备凭据恢复及刷新、同账号主机列表、主机改名 |
| 扫码授权 | 由服务器发现 GitHub / 知乎授权入口，本地 ArkUI QRCode，短期会话轮询与取消；二维码需要另一台设备扫描 |
| 安全连接 | 系统安全随机数、上游 Noise IK、X25519 / ChaChaPoly / SHA256、首次主机指纹确认、公钥变化拦截、加密 Relay、重放拒绝 |
| 本机存储 | 鸿蒙 Asset 安全资产；凭据按服务器、信任按服务器和账号隔离；锁定/读取失败不重置身份；不持久化聊天内容 |
| Harness | 工作区列表与创建、会话新建与切换、历史与更早分页、流式文字/思考/工具详情、发送、停止、一次审批/拒绝、用户提问表单、模型/思考强度目录 |
| CodeX | 共享项目/会话目录、历史、流式时间线、文字/图片、停止、一次审批；模型选择在下一条发送时提交 |
| ACP | 按 Host 能力显示 Cursor / Antigravity / Pi / OpenCode / Claude 目录，接入共享历史/流式/文字、取消、一次审批和模型目录；图片仅对 AGY 开放 |
| 原生交互 | 系统浅/深色资源、列表搜索、可复制正文和详情、系统相册选图；图片不落盘缓存 |
| 后台 | 转入后台主动断开并取消本机待审批状态；回前台自动尝试恢复上次主机，但不申请长时任务，不宣称持续后台保活 |

收藏、最近访问、分组与排序选项、提示词库与草稿保存在 `@ohos.data.preferences`，按服务器、账号和主机隔离；身份与凭据仍只留在 Asset 安全资产，偏好内容不含机密。

自动连接的边界：仍要求首次指纹确认与公钥变更拦截，身份变化时不重试；重连只重建连接与读取历史，绝不重放发送、审批或提问。

以上是源码实现范围。已验证真机安装、已有授权恢复、主机加密连接和工作区列表；扫码、相册、真实模型回复、各 ACP/CodeX 后端，以及本版新增的抽屉、下钻面板与自动连接行为仍需设备验收。

本版未移植：P2P/WebRTC/TURN、后台保活/自动重连、浏览器 OAuth 回跳/账号注册、文件树/预览/交互终端、工具访问预设入口、Bot/Intelligent UI、插件管理、自动化任务管理、加密草稿与阅读位置、多语言与主题设置、完整平板双栏。新建远端工作区当前仅开放 Harness。CodeX 历史当前整页读取，尚未接入分块分页界面。Cursor 历史受 Host 上游可提供能力限制。

## 源码结构

- `entry/src/main/ets/`：原生 ArkUI 页面、UIAbility、可审查的静态数据类型。
- `core/runtime.ts`：账号、信任和导航生命周期；通过 JSON DTO 与 ArkTS 通信。
- `core/platform.ts`：CryptoFramework 随机数、Asset、RCP HTTP（禁止重定向）、原生 WebSocket、UTF-8 与取消适配。
- `scripts/bundle.mjs`：直接打包本仓库共享协议/加密/client-core、Android 的平台无关连接及消息投影。构建会拒绝混入 React Native 或 Expo 原生依赖。
- `tests/`：只覆盖迁移带来的安全与核心状态边界；原生系统接口在 Node 测试中以契约替身提供。

## 构建

需要 Node.js 22+、pnpm 9.15.4 和带 **HarmonyOS SDK 26.0.0 / Hvigor 6.26.8** 的命令行工具或匹配的 DevEco Studio。工程声明最低 API 12；仅已在 SDK 26 完成编译，不代表 API 12 真机运行已验证。工程路径只使用英文、数字等 SDK 支持字符，避免中文和 emoji 路径。

仓库根目录：

```bash
pnpm install --frozen-lockfile
pnpm --filter @dsh-remote/harmony check
pnpm --filter @dsh-remote/harmony test
HARMONYOS_CLT_ROOT=/path/to/command-line-tools pnpm --filter @dsh-remote/harmony build
```

工具链默认查找 `$HOME/Tools/command-line-tools`，也可设置 `HARMONYOS_CLT_ROOT`。检查脚本会使用该 SDK 的真实声明文件；普通 `tsc` 不能替代 ArkTS 编译。根 npm 包不添加脚本，保留上游 DSH 安装边界。

HAP 输出：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

## 真机安装

1. 用匹配 SDK 的 DevEco Studio 打开本目录。
2. 按[华为自动签名指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing-auto)，使用你的开发者账号和目标设备生成调试签名，bundleName 为 `io.github.dshremote.harmony`。
3. 构建带签名的 HAP，连接已启用开发者调试的设备，执行 `hdc list targets` 确认设备。
4. 安装签名产物，而不是 unsigned 文件：

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

不要提交签名私钥、证书密码或个人 Profile。此源码包没有包含开发者签名材料，也没有替你发布到应用市场。

本次验证详情及验收清单见 [docs/harmonyos.md](../../docs/harmonyos.md)。

2026-11-06 真机验收补充：harmony.29 已验证启动/自动 LAN 连接、工作区层级与长路径、持续任务状态、更新查询、系统应用详情跳转及文件下载选择器取消；修复旧 settings action 无匹配错误。文件落盘、真实通知、长期锁屏和逐后端尚未完成验收，详见 docs/harmonyos-alignment-0.6.3.md。

公开源码使用通用包名 `io.github.dshremote.harmony`。既有设备上的私人开发签名包使用独立包名；从公开源码构建时应自行配置包名与签名，不能据此覆盖私人签名安装。
