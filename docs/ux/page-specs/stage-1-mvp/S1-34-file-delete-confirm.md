# S1-34 file-delete-confirm - 删除 / 移除索引确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-34
> 页面类型：文件操作
> 页面文件：`S1-34-file-delete-confirm.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口危险操作确认 sheet。
- **建议目录**：`apps/macos/AreaMatrix/Features/FileActions/DeleteFileConfirmSheet.swift`。
- **建议组件**：`DeleteFileConfirmSheet`、`RemoveFromIndexConfirmSheet`。
- **实现说明**：单文件 Delete 和 Remove from index 共用确认框；Stage 1 不提供多选删除或永久删除。Delete 必须走系统 Trash，并在 DB 中保留软删除记录与 change_log。

## 页面背景

用户从文件列表、详情页或缺失文件提示中发起删除或移除索引。该操作高风险，必须在确认页说明会影响文件本身还是只影响索引。

入口：`S1-09 main-list` 行右键 `Delete...`；`S1-12 detail-meta` 缺失文件 banner 的 `Remove from index`。
退出：Cancel 返回入口页；成功后返回 `S1-09 main-list` 并清空或移动选中；失败留在本 sheet。

## 页面功能

- 区分 `Move to Trash` 与 `Remove from index` 两种模式。
- 显示文件名、相对路径、存储模式和操作后果。
- 要求用户二次确认。
- 成功后写入 change_log 和软删除元数据，并保证失败不留下半成品。

## 布局与内容

Delete 模式标题：`Move File to Trash?`

Delete 模式说明：
```text
AreaMatrix will move this file to the system Trash and keep a change-log record.
```

Delete 补充说明：

- `The file is recoverable from system Trash while Trash retains it.`
- `AreaMatrix keeps a deleted metadata record for at least 30 days for traceability.`
- `Permanent delete is not available in Stage 1.`

Remove from index 模式标题：`Remove from Index?`

Remove from index 模式说明：
```text
This removes the AreaMatrix index entry. It does not delete the original file.
```

文件摘要：
- `Name`: `合同.pdf`
- `Location`: `docs/contracts/合同.pdf`
- `Storage mode`: `Copy` / `Move` / `Index-only`
- `Status`: `OK` / `Missing`

确认复选框：
- Delete：`我理解该文件会被移到系统废纸篓`
- Remove from index：`我理解该条目会从 AreaMatrix 索引中移除`

底部按钮：`Cancel`、destructive `Move to Trash` 或 `Remove from Index`。

## 状态与规则

- 未勾选确认复选框时，危险按钮禁用。
- Delete 只允许单文件；多选时不显示入口。
- Trash 不可用时禁用 `Move to Trash`，提示用户先在 Finder 中处理或导出诊断。
- Missing / Index-only 条目默认走 `Remove from index`，不得尝试删除不存在或外部引用文件。
- 删除成功后把文件移到系统 Trash，DB 标记为 soft-deleted，并保留至少 30 天可追溯元数据和 change_log。
- Stage 1 不提供永久删除按钮，不提供清空 Trash，不承诺自动从 Trash 还原；恢复能力以系统 Trash 和后续 Core 恢复能力为准。
- Remove from index 只移除 AreaMatrix 索引条目或标记索引移除，不删除磁盘上的用户文件，不清空用户笔记内容。
- 任何失败都不得删除索引以外的其他文件，不得清空用户笔记内容。
- 空态不适用：本 sheet 只在已有单文件或 missing/index-only 条目时打开；上下文缺失按错误态关闭并返回来源页。
- 加载态：Trash 可用性或 file status 检查中禁用危险按钮，显示 `Checking file status...`。

## 交互

1. 打开 sheet 后先显示操作后果，危险按钮默认禁用。
2. `Cancel` 关闭 sheet，不写文件、不写 DB。
3. 用户勾选确认后，危险按钮可用。
4. 点击危险按钮后显示执行中状态并防重复点击。
5. 成功后关闭 sheet，List 移除该行，Detail 显示空态或下一选中项。
6. 失败时保留 sheet，显示错误、`Retry` 和 `Collect Diagnostics...`；诊断不包含用户文件内容，不自动上传。
7. Delete 成功后 toast 文案为 `Moved to Trash. Metadata retained for traceability.`；Remove from index 成功后 toast 文案为 `Removed from AreaMatrix index. Original file was not deleted.`

## 可访问性

- 操作后果、确认复选框和 destructive 按钮必须逐项可读。
- Trash 不可用、Missing、Index-only 的差异不能只靠图标表达。
- Cancel、确认复选框、Move to Trash / Remove from Index、Retry 均可通过键盘访问。

## 数据与依赖

- 当前 `fileId`、相对路径、存储模式、missing 状态。
- Trash API。
- remove-index API。
- change_log 写入。
- DB soft-delete retention policy，Stage 1 至少 30 天。
- Diagnostics exporter。

## 验收清单

- Delete 每次必须二次确认并走 Trash。
- Delete 后 DB 有 soft-deleted 记录和 change_log，至少 30 天可追溯。
- Stage 1 不出现永久删除入口。
- Missing / Index-only 的 Remove from index 不删除用户原文件。
- Trash 不可用时不能继续 Delete。
- Cancel 不发生任何写入。
- 成功和失败都有明确返回路径。
- 诊断导出不包含用户文件内容。

## 来源

- `docs/ux/ui-states.md#文件缺失index-only-外部删除`（直接）。
- `docs/roadmap/stage-1-mvp.md#功能完整性`（组合）。
- `AGENTS.md` 中删除和用户文件安全边界（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
