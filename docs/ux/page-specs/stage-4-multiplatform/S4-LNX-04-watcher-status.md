# S4-LNX-04 watcher-status - Linux 文件监听状态

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-LNX-04
> 页面类型：Linux status page / dialog  
> 页面文件：`S4-LNX-04-watcher-status.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Linux 桌面端。
- **建议目录**：`apps/linux/AreaMatrix/Features/System/WatcherStatusView.*`。
- **建议组件**：`LinuxWatcherStatusView`、`InotifyDiagnostics`、`ManualRescanPanel`。
- **实现边界**：这是 Linux inotify 状态和恢复页，不实现内核参数修改器，只提示用户可采取的安全恢复动作。

## 页面背景

Linux 文件变化监听使用 inotify。它可能受 watch 数量限制、权限、网络挂载和桌面环境差异影响。本页需要让用户知道监听是否正常，以及何时需要手动 rescan。

入口：主窗口状态栏 watcher 提示、检测到 inotify 错误、设置高级页。  
退出：重启监听成功、手动 rescan 完成、关闭页面。

## 页面功能

- 显示 inotify watcher 当前状态。
- 显示监听路径、watch 数量、最近事件、最近扫描时间。
- 显示 inotify limit 相关错误。
- 提供 `Restart watcher`。
- 提供 `Run rescan now` 入口，但点击后必须先进入 `S4-X-07 rescan-confirm`。
- 提供诊断导出。
- 对网络挂载说明监听可能不可靠。

## 布局与内容

标题：`File watcher status`

状态卡：
- `Status: Running`、`Paused`、`Error`
- `Backend: inotify`
- `Watching: /home/you/AreaMatrix`
- `Watches: 128`
- `Last event: Apr 29, 2026 11:30`
- `Last rescan: Apr 29, 2026 11:28`

错误说明：
- limit exceeded：`Linux has reached the inotify watch limit.`
- permission denied：`AreaMatrix cannot watch this folder because of permissions.`
- network mount：`This location may not report all file changes.`

操作区：
- 主按钮：`Restart watcher`
- 次按钮：`Run rescan now`，打开 `S4-X-07 rescan-confirm`
- 辅助按钮：`Export diagnostics`
- 链接：`Open repository folder`

提示：
- 对 limit exceeded 可给说明链接，但不要自动运行 sudo 或修改系统配置。

## 状态与规则

- 默认状态：watcher snapshot 读取成功且状态为 Running 时，`Restart watcher`、`Run rescan now`、`Export diagnostics` 和 `Open repository folder` 可用；页面只展示状态，不主动重启或重扫。
- 加载态：读取 watcher snapshot 时显示 `Checking watcher status...`，恢复类按钮暂时禁用，`Close` 保持可用。
- 空态：repo 未连接或 watcher 后端不可用时显示 `File watcher is not available for this repository.`，隐藏事件预览。
- Running：显示正常说明。
- 错误态：Error、权限不足、路径丢失或 snapshot 读取失败时必须显示可读原因和恢复动作。
- Error：必须显示可读原因和恢复动作。
- Limit exceeded：建议减少监听范围或查看帮助，不执行系统级修改。
- Network mount：允许继续，但提示使用手动 rescan。
- Rescan running：禁用再次 rescan。
- Path missing：提供重新选择 repo。
- 禁用条件：repo path missing、DB locked、已有 rescan 运行、watcher snapshot 缺失或平台能力未知时，`Run rescan now` 禁用并显示原因；`Restart watcher` 在 Starting 或 watcher 后端不可用时禁用。

## 交互

1. 页面打开时读取 watcher snapshot。
2. 点击 `Restart watcher` 重建 inotify 监听。
3. 点击 `Run rescan now` 打开 `S4-X-07 rescan-confirm`；用户确认影响后才触发 Core re-scan。
4. 点击 `Export diagnostics` 生成不包含用户文件内容的诊断数据。
5. limit exceeded 场景下点击帮助打开文档或应用内帮助。
6. 状态恢复后自动刷新主窗口状态栏。

## 数据与依赖

- inotify watcher 状态。
- Core re-scan API。
- Linux mount/path type detection。
- Diagnostic export。
- 文件管理器打开能力。

## 验收清单

- Running、Error、limit exceeded、network mount、rescan running 都有独立状态。
- 页面不会请求 sudo，也不会自动修改系统配置。
- rescan 过程中不会启动第二次 rescan。
- 诊断导出明确不包含用户文件内容。
- 屏幕阅读器能读出 backend、状态和错误原因。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-12-platform-watcher-status.md`。
- 组合来源：`docs/adr/0005-fsevents-listener.md`、`docs/architecture/source-of-truth.md`。
- 推导说明：Linux watcher 状态展示 inotify 服务快照；手动 rescan 作为高风险回流动作拆到 `S4-X-07`。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Linux 主窗口](S4-LNX-02-main-window.md)
- [手动重扫确认](S4-X-07-rescan-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
