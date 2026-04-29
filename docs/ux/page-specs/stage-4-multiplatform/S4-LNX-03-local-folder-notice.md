# S4-LNX-03 local-folder-notice - 本地目录提示

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-LNX-03
> 页面类型：Linux dialog / onboarding step  
> 页面文件：`S4-LNX-03-local-folder-notice.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Linux 桌面端。
- **建议目录**：`apps/linux/AreaMatrix/Features/Onboarding/LocalFolderNoticeView.*`。
- **建议组件**：`LocalFolderNoticeView`、`MountTypeSummary`、`LinuxPathRiskView`。
- **实现边界**：这是 Linux 路径说明页，不实现云盘同步配置，也不修改挂载选项。

## 页面背景

Linux 用户可能选择本地磁盘、外接盘、网络挂载、Dropbox/Nextcloud 同步目录等位置。Stage 4 Linux 默认以本地目录为安全基线，本页用于解释当前路径的能力差异和风险。

入口：选择 repo 时检测到网络挂载、外接盘或同步目录；主窗口点击 `Local folder` 状态说明。  
退出：用户确认继续、选择其他目录、关闭说明。

## 页面功能

- 显示当前 repo 路径和路径类型。
- 解释本地目录是推荐路径。
- 对网络挂载、外接盘、第三方同步目录给出风险提示。
- 提供继续使用或选择其他目录。
- 提醒 Linux 端不会自动配置云同步。

## 布局与内容

标题：`Repository folder on Linux`

路径卡片：
- `Folder: /home/you/AreaMatrix`
- `Type: Local folder`、`External drive`、`Network mount`、`Sync folder`、`Unknown`
- `Writable: Yes/No`

说明文案：
- 本地目录：`This is the recommended setup for Linux.`
- 网络挂载：`Network drives may delay or reorder file events. Run a rescan if changes look out of date.`
- 同步目录：`AreaMatrix does not manage your sync provider. Conflict files will be shown for review when detected.`

操作：
- 主按钮：`Continue`
- 次按钮：`Choose Another Folder`
- 辅助：`Open Folder`

## 状态与规则

- 本地路径：可只显示简短确认，不阻塞用户。
- 加载态：检测挂载类型和权限时显示 `Checking folder...`，`Continue` 临时禁用。
- 空态：未收到路径或路径已被清空时显示 `Choose a repository folder first.`，隐藏路径风险说明，`Continue` 禁用。
- 外接盘：提示断开后 repo 不可访问。
- 网络挂载：需要确认后继续。
- 同步目录：需要确认冲突和监听风险。
- 类型未知：显示 `Unknown`，不猜测。
- 错误态：检测失败、路径丢失或权限不足时显示具体原因；检测失败显示 `Type: Unknown`，不把能力显示为可用。
- 不可写：不允许继续初始化或导入。

## 交互

1. 页面打开时读取路径类型和权限状态。
2. 对高风险路径显示确认 checkbox：`I understand this location may not report changes reliably.`
3. 勾选后 `Continue` 启用。
4. 点击 `Choose Another Folder` 返回选择页。
5. 点击 `Open Folder` 使用文件管理器打开目录。

## 数据与依赖

- Linux mount/path type detection，允许 best effort。
- POSIX permission check。
- 文件管理器打开能力。
- watcher 风险提示来自 inotify 能力边界。

## 验收清单

- 本地、外接盘、网络挂载、同步目录、未知类型有不同文案。
- 高风险路径继续前需要确认。
- 不可写路径不能继续。
- 页面不承诺 AreaMatrix 会管理 Dropbox/Nextcloud 同步。
- 屏幕阅读器能读出路径类型和确认项。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-10-linux-repo-connect.md`。
- 组合来源：`docs/adr/0005-fsevents-listener.md` 的跨平台 watcher 风险。
- 推导说明：Linux 路径类型、挂载差异和第三方同步目录风险依据平台能力推导；不承诺管理 Dropbox/Nextcloud 同步。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Linux 资料库选择](S4-LNX-01-choose-repo.md)
- [Linux 主窗口](S4-LNX-02-main-window.md)
- [逐页 UI 开发规格索引](../README.md)
