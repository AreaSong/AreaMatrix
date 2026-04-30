# S4-LNX-02 main-window - Linux 主窗口

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-LNX-02
> 页面类型：Linux main window  
> 页面文件：`S4-LNX-02-main-window.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Linux 桌面端。
- **建议目录**：`apps/linux/AreaMatrix/Features/Library/MainWindow.*`。
- **建议组件**：`LinuxMainWindow`、`LibraryNavigationPane`、`FileListView`、`FileDetailPanel`、`LinuxStatusBar`。
- **实现边界**：这是 Linux 最小主窗口，不引入系统托盘、插件或复杂桌面环境集成。

## 页面背景

Linux 端需要在不同桌面环境下稳定完成核心资料管理：浏览、导入、查看详情、显示监听状态。视觉应遵循所选工具包的原生风格，不强行复刻 macOS 或 Windows。

入口：Linux 资料库选择成功。  
退出：关闭窗口、打开导入、进入详情、进入 watcher 状态。

## 页面功能

- 浏览分类和文件列表。
- 查看文件详情：Meta、Log、Note。
- 导入文件或文件夹。
- 提供 `Refresh`，只刷新当前 UI 和 Core 只读 snapshot，不触发全库 rescan。
- 打开文件，使用系统默认应用。
- 在文件管理器中显示文件。
- 显示本地目录提示、inotify watcher 状态和 DB 状态。
- 显示缺失文件、冲突、权限问题。

## 布局与内容

推荐使用传统桌面布局，但减少平台假设。

窗口结构：
- Header bar 或 toolbar。
- 左侧导航：All Files、Recent、Needs Review、分类。
- 中间文件列表。
- 右侧详情或底部详情，根据窗口宽度适配。
- 底部状态栏。

工具栏：
- `Import`
- `Search`
- `Refresh`，只读刷新当前分类、详情、状态栏和导入队列。
- `Settings`

文件列表：
- 列：Name、Category、Modified、Size、Status。
- Linux 大小写敏感文件名按实际显示，不做额外规范化。

详情：
- 单选显示 Meta、Log、Note tabs。
- 未选中显示 repo 摘要和导入入口。
- 多选显示数量和总大小。

状态栏：
- `Local folder`
- `Watcher: running` 或 `Watcher: needs attention`
- `Last scan: ...`

## 状态与规则

- 空库：显示导入空态。
- 加载：显示 skeleton 或进度条。
- watcher 错误：状态栏黄色提示，点击进入 watcher 状态页。
- 权限不足：文件行或详情显示恢复动作，不自动 chmod。
- 文件管理器 reveal 不可用：隐藏或降级为复制路径。
- DB locked：保留缓存列表并显示重试。
- 网络挂载：显示本地目录提示页入口。
- 未选中文件：文件动作禁用，只保留导入、刷新和设置入口。
- Refresh 默认状态：repo 可访问时可用，点击后只重新读取 repo summary、当前列表、选中详情和状态栏 snapshot。
- Refresh 加载态：显示 `Refreshing...`，按钮临时禁用，避免并发读取。
- Refresh 错误态：DB locked、权限不足或路径丢失时保留缓存列表并显示可读错误，不写 DB。
- watcher 错误或网络挂载场景：Refresh 不执行 inotify 回流，不启动全库 rescan；全库重扫只能从 [S4-LNX-04 watcher-status](S4-LNX-04-watcher-status.md) 进入 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md)。

## 交互

1. 启动后加载 repo summary、分类和列表。
2. 点击分类刷新列表。
3. 双击文件调用 `xdg-open` 或工具包等价 API。
4. 右键菜单：`Open`、`Show in File Manager`、`Copy Path`。
5. 拖拽文件到窗口进入 Linux 导入流程。
6. 点击 watcher 状态进入 `S4-LNX-04 watcher-status`。
7. 点击 `Local folder` 状态说明进入 `S4-LNX-03 local-folder-notice`。
8. 点击缺失文件恢复入口进入 `S4-X-06 missing-file-recovery`；点击冲突入口进入 `S4-X-03 sync-conflict-entry`。
9. 点击 `Refresh` 只刷新当前可见数据和状态，不触发 re-scan；如需要全库重扫，必须先进入 watcher 状态页再确认。

## 数据与依赖

- Rust core list/detail/log/note API。
- Linux file manager reveal，可能使用 xdg-open 或 DBus portal。
- inotify watcher 状态。
- POSIX 权限和路径检测。
- 工具包 accessibility 支持。
- 只读 refresh provider：repo summary、list、detail、status snapshot。

## 验收清单

- Linux 主窗口能完成浏览、打开、详情、导入入口。
- watcher、权限、DB locked、缺失文件状态可见。
- 文件管理器 reveal 不支持时有降级路径。
- 不要求 iCloud 或 OneDrive。
- 在 GNOME/KDE 至少一种目标环境中布局不重叠。
- 屏幕阅读器可读出文件列表和状态栏。
- `Refresh` 不写 DB、不触发 inotify 回流、不绕过 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md)。

## 来源

- 来源类型：组合来源。
- 直接来源：Stage 1 主窗口与 Detail 页面规格。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-30-s4-lnx-02-main-window.md`。
- 组合来源：`docs/adr/0001-tech-stack.md` 的 Linux UI 技术候选。
- 推导说明：Linux 主窗口复用桌面信息架构，但按 GTK/Qt 原生控件、inotify 和 POSIX 权限边界实现。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [本地目录提示](S4-LNX-03-local-folder-notice.md)
- [Linux 文件监听状态](S4-LNX-04-watcher-status.md)
- [Linux 导入流程](S4-LNX-05-import-flow.md)
- [冲突入口](S4-X-03-sync-conflict-entry.md)
- [缺失文件恢复](S4-X-06-missing-file-recovery.md)
- [逐页 UI 开发规格索引](../README.md)
