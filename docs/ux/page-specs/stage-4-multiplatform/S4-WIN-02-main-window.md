# S4-WIN-02 main-window - Windows 主窗口

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-WIN-02
> 页面类型：Windows main window  
> 页面文件：`S4-WIN-02-main-window.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Windows 桌面端。
- **建议目录**：`apps/windows/AreaMatrix/Features/Library/MainWindow.*`。
- **建议组件**：`WindowsMainWindow`、`RepositorySidebar`、`FileListPane`、`DetailPane`、`StatusBar`。
- **实现边界**：这是 Windows 最小主窗口，复用 macOS 的信息架构，但控件和快捷键按 Windows 习惯实现。

## 页面背景

Windows 用户需要完成资料库浏览、导入、详情查看和监听状态查看。桌面空间允许三栏概念，但不要照搬 SwiftUI 视觉；应使用 WinUI 3 或 Avalonia 的原生导航、列表、命令栏和状态栏。

入口：`choose-repo` 成功打开已有 repo。  
退出：关闭窗口、切换 repo、打开文件详情、进入导入流程或 watcher 状态页。

## 页面功能

- 显示资料库分类树或导航栏。
- 显示当前分类的文件列表。
- 显示右侧详情：Meta、Log、Note 摘要。
- 提供导入入口：`Import Files...`、`Import Folder...`。
- 提供搜索入口；Stage 4 MVP 只要求基础搜索入口，高级搜索仅在 Stage 2 能力已落地时显示。
- 提供 `Refresh`，只刷新当前 UI 和 Core 只读 snapshot，不触发全库 rescan。
- 显示 OneDrive、watcher、DB locked、缺失文件等状态。
- 支持打开文件、在 Explorer 中显示、复制路径。
- 支持基础多选，但批量高级动作按 Stage 2 能力是否已落地决定。

## 布局与内容

窗口结构：
- 顶部命令栏。
- 左侧导航栏：repo 名称、分类、Needs Review、Recent。
- 中间文件列表。
- 右侧详情 pane。
- 底部状态栏。

顶部命令栏：
- `Import`，下拉包含 `Files...`、`Folder...`。
- `Search` 输入或按钮。
- `Refresh`，只读刷新当前分类、详情、状态栏和导入队列。
- `Settings`。

左侧导航：
- Repo 名称和路径简写。
- `All Files`
- `Recent`
- `Needs Review`
- 一级分类列表和数量。

文件列表：
- 列：Name、Category、Modified、Size、Status。
- 状态徽标：`Missing`、`Conflict`、`OneDrive`、`Locked`。
- 空态文案：`Drop files here or use Import to add documents.`

详情 pane：
- 未选中文件：显示导入提示和 repo 摘要。
- 单选文件：显示 Meta、Log、Note tabs。
- 多选：显示数量、总大小、可用批量动作。

状态栏：
- `Watcher: running`
- `OneDrive: syncing` 或 `Local folder`
- 最近扫描时间。

## 状态与规则

- 空资料库：左侧仍显示基础导航，中间显示导入空态。
- 加载中：列表显示 skeleton，状态栏显示 `Loading repository...`，导入和打开文件类操作临时禁用。
- DB locked：顶部显示黄色 banner，允许重试，不清空列表缓存。
- watcher stopped：状态栏显示 `File watcher paused`，点击进入 watcher 状态页。
- OneDrive 同步中：状态栏显示同步提示，不阻止已下载文件操作。
- 缺失文件：列表行保留并标记，详情提供恢复入口。
- 导入进行中：底部显示进度 mini bar。
- 未选中文件：右键菜单文件动作禁用，只保留导入和刷新。
- Refresh 默认状态：repo 可访问时可用，点击后只重新读取 repo summary、当前列表、选中详情和状态栏 snapshot。
- Refresh 加载态：显示 `Refreshing...`，按钮临时禁用，避免并发读取。
- Refresh 错误态：DB locked、权限不足或路径丢失时保留缓存列表并显示可读错误，不写 DB。
- watcher stopped 或 OneDrive 事件噪声场景：Refresh 不执行 watcher 回流，不启动全库 rescan；全库重扫只能从 [S4-WIN-04 watcher-status](S4-WIN-04-watcher-status.md) 进入 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md)。

## 交互

1. 打开窗口后加载 repo summary、分类树和默认列表。
2. 点击分类更新中间列表，右侧详情清空或保留当前选择视实现策略。
3. 双击文件打开系统默认应用；右键菜单提供 `Open`、`Show in Explorer`、`Copy Path`。
4. 拖拽文件到列表区域进入 Windows 导入流程。
5. 点击 watcher 状态进入 `S4-WIN-04 watcher-status`。
6. 点击 OneDrive 状态进入 `S4-WIN-03 onedrive-notice` 的已连接说明版本。
7. 点击缺失文件的恢复入口进入 `S4-X-06 missing-file-recovery`；点击冲突入口进入 `S4-X-03 sync-conflict-entry`。
8. 点击 `Refresh` 只刷新当前可见数据和状态，不触发 re-scan；如需要全库重扫，必须先进入 watcher 状态页再确认。

## 数据与依赖

- Rust core list/detail/change log/note API。
- Windows shell open、Explorer reveal。
- Windows drag and drop。
- ReadDirectoryChangesW watcher 状态。
- OneDrive path and sync status，若不可精确检测，显示 `Unknown` 而不是猜测。
- 只读 refresh provider：repo summary、list、detail、status snapshot。

## 验收清单

- Windows 主窗口能完成浏览、打开、导入入口、详情查看。
- 空态、加载、DB locked、watcher stopped、缺失文件都有明确 UI。
- 列表列宽在 1280px 宽度下不重叠。
- 右键菜单和键盘快捷键符合 Windows 习惯。
- 不依赖 macOS API 或 SwiftUI 组件。
- Narrator 能读出列表列名、文件状态和状态栏。
- `Refresh` 不写 DB、不触发 watcher 回流、不绕过 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md)。

## 来源

- 来源类型：组合来源。
- 直接来源：Stage 1 主窗口与 Detail 页面规格。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-11-desktop-main-query.md`。
- 直接来源：`docs/roadmap/milestones.md` Stage 4 Windows 端。
- 推导说明：窗口布局复用桌面信息架构，但控件、菜单、状态栏和快捷键按 Windows 习惯实现。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Windows 文件监听状态](S4-WIN-04-watcher-status.md)
- [Windows 导入流程](S4-WIN-05-import-flow.md)
- [冲突入口](S4-X-03-sync-conflict-entry.md)
- [缺失文件恢复](S4-X-06-missing-file-recovery.md)
- [逐页 UI 开发规格索引](../README.md)
