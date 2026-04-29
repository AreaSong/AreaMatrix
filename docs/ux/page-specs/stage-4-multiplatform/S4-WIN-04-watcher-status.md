# S4-WIN-04 watcher-status - Windows 文件监听状态

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-WIN-04
> 页面类型：Windows status page / dialog  
> 页面文件：`S4-WIN-04-watcher-status.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Windows 桌面端。
- **建议目录**：`apps/windows/AreaMatrix/Features/System/WatcherStatusView.*`。
- **建议组件**：`WatcherStatusView`、`WindowsWatcherDiagnostics`、`RescanActions`。
- **实现边界**：这是文件监听状态与恢复页，不实现底层 ReadDirectoryChangesW 逻辑，只展示状态并触发已有平台服务动作。

## 页面背景

AreaMatrix 的真相源策略要求外部文件系统变化能回流到 DB。Windows 端使用 ReadDirectoryChangesW。用户不需要知道 API 名称，但需要知道监听是否正常、是否暂停、是否因为权限或网络盘限制失效。

入口：主窗口状态栏点击 watcher 状态、检测到 watcher 错误、设置高级页查看诊断。  
退出：重启监听成功返回主窗口；导出诊断；关闭页面。

## 页面功能

- 显示当前 watcher 状态：Running、Starting、Paused、Error、Unavailable。
- 显示监听路径和最近事件时间。
- 显示待处理事件数量和最近一次 scan 时间。
- 提供 `Restart watcher`。
- 提供 `Run rescan now` 入口，但点击后必须先进入 `S4-X-07 rescan-confirm`。
- 提供诊断导出入口。
- 对 OneDrive 或网络路径给出降级说明。

## 布局与内容

推荐作为主窗口内的详情页或 modal dialog。

标题：`File watcher status`

状态卡：
- `Status: Running`
- `Watching: C:\Users\you\Documents\AreaMatrix`
- `Last event: Apr 29, 2026 11:30`
- `Pending events: 0`
- `Last rescan: Apr 29, 2026 11:28`

状态说明：
- Running：`AreaMatrix is watching this folder for external changes.`
- Paused：`File changes may not appear until the watcher is restarted or a rescan runs.`
- Error：显示具体可读错误，例如权限、路径不可用、句柄失败。

操作区：
- 主按钮：`Restart watcher`
- 次按钮：`Run rescan now`，打开 `S4-X-07 rescan-confirm`
- 辅助按钮：`Export diagnostics`
- 链接：`Open repository folder`

事件预览：
- 可选显示最近 5 个事件：Created、Modified、Deleted、Renamed。
- 事件仅用于诊断，不作为用户编辑入口。

## 状态与规则

- 默认状态：watcher snapshot 读取成功且状态为 Running 时，`Restart watcher`、`Run rescan now`、`Export diagnostics` 和 `Open repository folder` 可用；页面只展示状态，不主动重启或重扫。
- 加载态：读取 watcher snapshot 时显示 `Checking watcher status...`，恢复类按钮暂时禁用，`Close` 保持可用。
- 空态：repo 未连接或 watcher 后端不可用时显示 `File watcher is not available for this repository.`，隐藏事件预览。
- Running：主按钮可显示为 `Restart watcher`，不是禁用。
- Starting：按钮禁用，显示进度。
- Paused：显示黄色提示，建议重启。
- 错误态：Error、Path missing、权限不足或 snapshot 读取失败时显示错误原因和恢复动作。
- Error：显示错误原因和恢复动作。
- Path missing：提供选择资料库或重新连接磁盘。
- Rescan running：显示进度，不允许并发启动第二次 rescan。
- OneDrive 路径：增加说明 `OneDrive may generate bursts of file events.`。
- 禁用条件：repo path missing、DB locked、已有 rescan 运行、watcher snapshot 缺失或平台能力未知时，`Run rescan now` 禁用并显示原因；`Restart watcher` 在 Starting 或 watcher 后端不可用时禁用。

## 交互

1. 打开页面时读取 watcher snapshot，不主动重启。
2. 点击 `Restart watcher` 调用平台服务重建监听。
3. 点击 `Run rescan now` 打开 `S4-X-07 rescan-confirm`；用户确认影响后才触发 Core re-scan。
4. watcher 恢复后状态卡即时更新。
5. 点击 `Export diagnostics` 生成诊断包，包含 watcher 状态、最近事件和错误，不包含用户文件内容。
6. 点击 `Open repository folder` 用 Explorer 打开 repo。

## 数据与依赖

- ReadDirectoryChangesW watcher 状态。
- Core re-scan API。
- 诊断导出 API。
- Windows Explorer reveal。
- 错误映射：`WatcherUnavailable`、`PermissionDenied`、`PathMissing`、`DatabaseLocked`。

## 验收清单

- Running、Paused、Error、Path missing、Rescan running 五种状态有不同 UI。
- 用户能从 watcher 错误中找到明确恢复动作。
- 诊断导出说明不包含用户文件内容。
- rescan 进行中不会启动第二个 rescan。
- OneDrive 路径显示事件噪声提示。
- Narrator 能读出状态值和最近事件列表。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-12-platform-watcher-status.md`。
- 组合来源：`docs/adr/0005-fsevents-listener.md` 的跨平台 watcher 说明。
- 组合来源：`docs/architecture/source-of-truth.md`。
- 推导说明：Windows watcher 状态展示 ReadDirectoryChangesW 服务快照；手动 rescan 作为高风险回流动作拆到 `S4-X-07`。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Windows 主窗口](S4-WIN-02-main-window.md)
- [手动重扫确认](S4-X-07-rescan-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
