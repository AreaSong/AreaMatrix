# S4-LNX-05 import-flow - Linux 导入流程

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-LNX-05
> 页面类型：Linux import dialog  
> 页面文件：`S4-LNX-05-import-flow.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Linux 桌面端。
- **建议目录**：`apps/linux/AreaMatrix/Features/Import/LinuxImportDialog.*`。
- **建议组件**：`LinuxImportDialog`、`ImportPreviewList`、`LinuxTrashCapabilityView`、`ImportProgressView`。
- **实现边界**：这是 Linux 文件/文件夹导入 UI，复用 Core 事务式导入，不实现发行版专属文件管理器扩展。

## 页面背景

Linux 用户可通过文件选择器或拖拽导入资料。Linux 上回收站能力、文件权限、大小写敏感和网络挂载行为差异明显，因此导入 UI 必须清楚显示安全选择和失败恢复。

入口：主窗口 `Import`、拖拽文件、命令行打开文件可选入口。  
退出：导入成功返回主窗口；失败显示结果；取消返回主窗口。

## 页面功能

- 选择文件或文件夹。
- 预览导入项数量、总大小、不可读项。
- 选择导入模式：默认 Copy into repository。
- 对 `Move into repository` 展示 POSIX 权限、跨挂载、源文件影响、失败恢复和二次确认。
- 显示目标分类和建议分类。
- 处理重复 hash 和同名冲突。
- 在 Replace 场景中检测 Trash 是否可用。
- 显示导入进度和结果。

## 布局与内容

使用 GTK/Qt 原生 dialog，宽度约 760，避免 macOS sheet 文案。

标题：`Import to AreaMatrix`

来源区：
- `Source: /home/you/Downloads`
- 按钮：`Add files...`、`Add folder...`

预览列表：
- Name、Size、Suggested category、Status。
- 状态：`Ready`、`Duplicate`、`Name conflict`、`Unreadable`、`Permission denied`。

导入设置：
- `Copy into repository`，默认。
- `Move into repository`，危险，需要确认。
- `Preserve folder structure`。

Move 确认区，仅在选择 `Move into repository` 时显示：
- 标题：`Move originals after import?`
- 影响摘要：
  - `Source path: /home/you/Downloads`
  - `Target path: <repository relative path>`
  - `Items to move: 5`
  - `File system: same mount / different mount / unknown`
  - `Source removal: after repository write and database update succeed`
- 安全文案：`AreaMatrix will not remove originals until the imported files and database records are safely written.`
- POSIX 权限提示：`The source folder must allow removing these files. AreaMatrix will not ask for sudo or change permissions.`
- 跨挂载提示：`If the source and repository are on different mounts, AreaMatrix will copy into staging first and remove originals only after the import succeeds.`
- 恢复文案：`If removing an original fails, the result will say the source was retained and will not mark that item as fully moved.`
- 确认项：`I understand the originals will be removed from the source folder after a successful import.`
- 替代操作：`Use Copy instead`

冲突区：
- 重复内容：默认 `Skip duplicate`。
- 同名不同内容：默认 `Keep both`，自动编号。
- Replace：如果 Trash 可用，进入 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md) 并说明旧文件移入 Trash；如果 Trash 不可用，默认禁用 Replace。Stage 4 不提供不可逆替换路径。

底部按钮：
- `Cancel`
- `Import`

## 状态与规则

- 默认状态：至少有一个可导入项、目标分类可写、预览和 Trash 检测完成、无阻断错误时，`Import` 可用；导入模式默认为 `Copy into repository`。
- 空态：没有选择或拖入文件时显示 `Add files or folders to import.`，预览列表为空，`Import` 禁用。
- 加载态：构建预览、读取目录、计算 hash 或检测 Trash 能力时显示 `Reading selected items...`、`Checking conflicts...` 或 `Checking Trash availability...`，`Import` 临时禁用。
- 错误态：DB locked、目标路径丢失、目标分类不可写、Trash 检测失败、全部项目不可读时显示具体原因和 `Retry` / `Choose another target` / `Export diagnostics`。
- 禁用条件：无文件、预览中、Trash 检测中、目标不可写、全部项目不可读、DB locked、危险 `Move into repository` 未确认、Replace 恢复能力不可用、导入已在运行。
- 不可读文件：显示原因，允许跳过其余文件。
- POSIX 权限不足：不建议用户运行 sudo；提示选择可读文件、选择有写权限的目标目录，或由用户自行在系统文件管理器中调整权限后重试，不给可直接复制的危险 `chmod` 命令。
- Move 模式：必须显示 Move 确认区；确认项未勾选时 `Import` 禁用。
- Move preflight：必须确认源文件可读、源目录允许 unlink/rename、目标 repo 可写、staging 可用；跨挂载时必须走 copy-to-staging 再 remove original，不依赖原子 rename。
- Move 不可降级：用户选择 Move 但 preflight 失败时，不得静默改为 Copy；必须让用户明确切换。
- Move 源文件移除失败：保留已安全导入的 repo 文件，结果标记 `Imported, original retained`，并记录失败原因；不得建议用户运行 sudo/chmod。
- 大小写冲突：在大小写敏感文件系统中按实际名称处理；如果目标 repo 策略要求统一，显示冲突。
- Trash 可用：Replace 仍必须进入 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md)，且先通过 move-to-trash preflight。
- Trash 不可用或检测失败：Replace 不能假装可逆，默认禁用；未来如需不可逆替换，必须另开独立规格。
- 网络挂载：显示黄色提示，建议导入完成后 rescan。
- DB locked：暂停预览或导入，保留当前选择和用户设置；显示 `Database is busy. Try again.`，不写最终目录。
- 导入中取消/关闭：若 Core 支持取消，显示 `Cancel remaining` 并保留已完成结果摘要；若不支持取消，`Cancel` 改为 `Close when done`，避免用户误以为已中断事务。
- 部分失败：结果页保留成功、跳过、失败数量；`Retry failed` 只重试失败项，不重复导入成功项。
- 导入失败：不留下最终目录半成品；staging recovery 状态必须可被下次启动恢复或清理。

## 交互

1. 用户选择或拖入文件后先构建预览。
2. 预览阶段进行只读校验和冲突检测。
3. 用户调整分类和冲突策略后点击 `Import`。
4. 如果用户选择 `Move into repository`，先显示 Move 确认区；未确认前 `Import` 保持禁用。
5. 进度阶段显示：`Staging`、`Hashing`、`Writing files`、`Updating database`、`Removing originals`、`Done`。
6. 如果源文件移除失败，结果页显示 `Imported, original retained`，并提供 `Open original folder` 与 `Open imported file`。
7. 如果用户选择 Replace，先打开 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md)；Trash 不可用、检测失败或 preflight 失败时不能继续 Replace。
8. 失败结果保留，可 `Retry failed` 或 `Export diagnostics`。
9. 成功后可 `Open folder` 或 `View imported files`。

## 数据与依赖

- Linux file/folder picker 或 xdg-desktop-portal。
- Drag and drop。
- Core transactional import API。
- Duplicate/conflict detection。
- Move preflight：源文件可读、源目录可 unlink/rename、目标可写、staging 可用、same-mount / cross-mount 判断。
- Move result：imported、source removed、source retained、source removal failure reason。
- freedesktop Trash 能力检测。
- Move-to-trash preflight。
- POSIX permission detection。
- DB lock / staging recovery 状态。

## 验收清单

- 文件、文件夹、拖拽三种入口可用。
- 未选择文件时显示空态，`Import` 禁用。
- 预览、hash、Trash 检测加载中时有明确文案，`Import` 禁用。
- 同名冲突默认保留两份。
- Replace 在 Trash 不可用时不会被描述为可逆。
- Trash 检测失败时 Replace 禁用，并提示改用 `Keep both`。
- Move 未确认时 `Import` 禁用，并清楚说明源文件会在成功后从原位置移除。
- Move preflight 失败时不能静默降级为 Copy；用户必须手动选择 `Copy into repository`。
- 跨挂载 Move 使用 copy-to-staging 后移除源文件的安全顺序，不依赖原子 rename。
- Move 源文件移除失败时结果页必须显示 `Imported, original retained`，且不建议 sudo/chmod。
- 权限错误不会建议危险命令。
- DB locked 时不会写最终目录，用户设置和预览结果保留。
- 网络挂载有导入后 rescan 提示。
- 部分失败可 `Retry failed`，不会重复导入已成功项。
- 每个禁用状态都能显示原因。
- 屏幕阅读器能读出预览列表状态和导入进度。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/drag-import-flow.md`。
- 直接来源：`docs/ux/dedup-conflict.md`。
- 组合来源：`docs/architecture/transactional-import.md`、`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-33-s4-lnx-05-import-flow.md`。
- 推导说明：Linux 导入沿用事务式导入和冲突策略，Trash、POSIX 权限、网络挂载风险按 Linux 平台能力补齐。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Linux 主窗口](S4-LNX-02-main-window.md)
- [Replace 二次确认](S4-X-09-replace-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
