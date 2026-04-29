# S4-WIN-05 import-flow - Windows 导入流程

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-WIN-05
> 页面类型：Windows import dialog  
> 页面文件：`S4-WIN-05-import-flow.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Windows 桌面端。
- **建议目录**：`apps/windows/AreaMatrix/Features/Import/WindowsImportDialog.*`。
- **建议组件**：`WindowsImportDialog`、`ImportPreviewList`、`ConflictInlinePanel`、`ImportProgressView`。
- **实现边界**：这是 Windows 文件/文件夹导入 UI，沿用 Stage 1 事务式导入和冲突策略，不实现额外自动化规则编辑器。

## 页面背景

Windows 用户可通过按钮、拖拽或文件夹选择把资料导入 AreaMatrix。导入必须明确来源、目标、冲突处理和进度，默认不覆盖用户文件。Windows 端要兼容 Explorer 拖拽体验。

入口：主窗口 `Import` 菜单、拖拽文件到主窗口、Explorer `Open with AreaMatrix` 可选入口。  
退出：导入成功返回主窗口并选中新文件；取消返回主窗口；冲突未解决时停留在导入对话框。

## 页面功能

- 选择一个或多个文件。
- 选择一个文件夹并递归预览导入内容。
- 显示文件数量、总大小、来源路径。
- 选择导入模式：`Copy into repository` 默认；`Move into repository` 作为危险选项；`Index in place` 不属于 Stage 4 Windows MVP，默认不显示。
- 对 `Move into repository` 展示源文件影响、权限 preflight、失败恢复和二次确认。
- 显示目标分类或目标路径。
- 展示冲突：重复内容、同名不同内容、不可读文件。
- 导入进度分阶段展示。
- 导入结果显示成功、跳过、失败和可打开位置。

## 布局与内容

推荐使用 modal dialog，宽度约 760。拖拽时主窗口显示 drop overlay，松开后进入同一 dialog。

标题：`Import to AreaMatrix`

来源区：
- `Source: 5 items from C:\Users\you\Downloads`
- 按钮：`Add files...`、`Add folder...`、`Clear`

预览列表：
- 列：Name、Type、Size、Suggested category、Status。
- 状态：`Ready`、`Duplicate`、`Name conflict`、`Unreadable`。
- 多文件时允许展开文件夹层级。

导入设置：
- `Import mode`
  - `Copy into repository`，默认。
  - `Move into repository`，危险，需要额外确认。
  - `Index in place` 不进入 Stage 4 MVP 验收；除非后续有独立规格，否则不显示。
- `Target category`
- `Preserve folder structure` checkbox，导入文件夹时显示。

Move 确认区，仅在选择 `Move into repository` 时显示：
- 标题：`Move originals after import?`
- 影响摘要：
  - `Source folder: C:\Users\you\Downloads`
  - `Target folder: <repository relative path>`
  - `Items to move: 5`
  - `Source removal: after files and database records are safely written`
- 安全文案：`AreaMatrix will keep the original files in place until the repository copy and database update succeed.`
- 风险文案：`After a successful move, the originals will no longer remain in the source folder.`
- 恢复文案：`If removing an original fails, the import result will say the source was retained and will not mark that item as fully moved.`
- 确认项：`I understand the originals will be removed from the source folder after a successful import.`
- 替代操作：`Use Copy instead`

冲突区：
- 同名不同内容显示黄色 panel。
- 默认选项：`Keep both`。
- `Replace existing file` 需要二次确认；只有检测到 Recycle Bin 可用且 move-to-bin 能成功时才允许执行，并说明旧文件会先移入 Recycle Bin 且写入日志。

底部按钮：
- `Cancel`
- `Import`
- 导入中变为 `Close when done` 或 `Cancel remaining`，按 Core 是否支持取消决定。

## 状态与规则

- 默认状态：至少有一个可导入项、目标分类可写、冲突策略有效时，`Import` 可用。
- 空态：没有文件时显示 `Add files or folders to import.`，`Import` 禁用。
- 加载态：构建预览、展开文件夹、计算 hash、检测 Recycle Bin 或分类建议时显示 `Preparing import...`，`Import` 临时禁用。
- 错误态：DB locked、路径不可访问、Recycle Bin 检测失败、目标不可写或全部项目不可读时显示具体原因和恢复动作。
- 没有文件：`Import` 禁用。
- 存在不可读文件：允许跳过并导入其他文件，但必须显示数量。
- 重复 hash：默认 `Skip duplicate`，可打开已有文件。
- 同名不同内容：默认 `Keep both` 自动编号。
- Move 模式：必须显示 Move 确认区；确认项未勾选时 `Import` 禁用。
- Move preflight：必须确认源文件可读、源位置允许删除/移动、目标 repo 可写、staging 可用；任一阻断失败时禁用 Move 并提示改用 `Copy into repository`。
- Move 不可降级：用户选择 Move 但 preflight 失败时，不得静默改为 Copy；必须让用户明确切换。
- Move 执行顺序：先 staging/copy 到 repo、写 DB、写入导入日志，再移除源文件；移除源文件失败时不得回滚已安全导入的 repo 文件，但结果必须标记 `Imported, original retained`，并记录 source removal failure。
- Move 取消：确认前取消不复制、不删除；导入中若 Core 不支持取消，按钮显示 `Close when done`，不得让用户误以为源文件已停止处理。
- Replace：必须进入 `S4-X-09 replace-confirm` 二次确认；Recycle Bin 不可用、检测失败、网络盘不支持、组织策略禁止或 move-to-bin 失败时禁用 Replace，并提示改用 `Keep both`。
- Replace 执行顺序：先确认 Recycle Bin 移动成功，再执行替换；任一步失败都不得覆盖 existing 文件。
- 导入中 DB locked：暂停并显示重试，不留下最终目录半成品。

## 交互

1. 用户选择或拖入文件后，先构建预览，不立即复制。
2. 预览中每个文件显示建议分类和冲突状态。
3. 用户选择 `Move into repository` 时显示 Move 确认区；未勾选确认项前 `Import` 保持禁用。
4. 用户解决必要冲突并完成 Move 确认后 `Import` 启用。
5. 点击 `Import` 后进入进度视图：`Staging`、`Hashing`、`Writing files`、`Updating database`、`Removing originals`、`Done`。
6. 如果源文件移除失败，结果页显示 `Imported, original retained`，并提供 `Show original` 与 `Show imported file`。
7. 失败项保留在结果页，提供 `Retry failed` 和 `Show details`。
8. 成功后结果页提供 `Show in Explorer`、`View imported files`。

## 数据与依赖

- Windows file/folder picker。
- Windows drag and drop。
- Core transactional import API。
- Duplicate and name conflict detection。
- Move preflight：源文件可读、源位置可删除/移动、目标可写、staging 可用。
- Move result：imported、source removed、source retained、source removal failure reason。
- Windows Recycle Bin integration for Replace。
- Recycle Bin availability and move-to-bin preflight。
- Explorer reveal。

## 验收清单

- 按钮选择、文件夹选择、拖拽三种入口进入同一导入流程。
- 同名不同内容默认保留两份。
- Replace 和 Move 都有额外确认；Recycle Bin 不可用或 move-to-bin 失败时 Replace 禁用，不会一键破坏原文件。
- Move 未确认时 `Import` 禁用，并清楚说明源文件会在成功后从原位置移除。
- Move preflight 失败时不能静默降级为 Copy；用户必须手动选择 `Copy into repository`。
- Move 源文件移除失败时结果页必须显示 `Imported, original retained`，并且不把该项标记为完整 Move。
- 导入进度显示事务阶段，失败后能说明哪些项失败。
- 成功导入后文件系统和 DB 都可见。
- Narrator 能读出预览列表的冲突状态。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/drag-import-flow.md`。
- 直接来源：`docs/ux/dedup-conflict.md`。
- 组合来源：`docs/architecture/transactional-import.md`、`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-13-desktop-import-flow.md`。
- 推导说明：Windows 导入沿用 Stage 1 事务式导入和冲突策略，Explorer 入口、Recycle Bin 和拖拽按 Windows 平台能力补齐；Stage 4 prompt 来源为 `tasks/prompts/phase-4/4-3-stage4-multiplatform/task-13-desktop-import-flow.md`。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Windows 主窗口](S4-WIN-02-main-window.md)
- [Replace 二次确认](S4-X-09-replace-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
