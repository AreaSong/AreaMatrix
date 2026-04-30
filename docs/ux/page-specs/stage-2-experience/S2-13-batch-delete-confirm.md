# S2-13 batch-delete-confirm - 批量删除确认

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-13
> 页面类型：批量
> 页面文件：`S2-13-batch-delete-confirm.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 批量操作。
- **建议目录**：`apps/macos/AreaMatrix/Features/BatchActions/BatchDeleteConfirmSheet.swift`。
- **建议组件**：`BatchDeleteConfirmSheet`、`DeleteImpactSummary`、`IndexOnlyDeleteOption`。
- **实现说明**：默认删除语义是移到 Trash，不提供永久删除。Index-only 条目可以仅从索引移除，不删除源文件。

## 页面背景

用户在主窗口多选文件后点击 Delete。删除属于高风险操作，尤其是混合了 repo 内文件、Index-only 文件、缺失文件和只读文件时。本页必须让用户明确知道哪些文件会进 Trash、哪些只是移除索引、哪些无法处理。

入口：多选后点击 Delete、右键菜单 `Move to Trash`、批量操作栏删除按钮。
退出：执行后回到主窗口并显示 Undo toast；取消则不做任何变更；遇到阻塞项时留在 sheet 并显示原因。

## 页面功能

- 显示总选择数量和预计处理结果。
- 区分 repo-managed 文件、Index-only 文件、缺失文件、不可删除文件。
- 默认主操作为 `Move to Trash`。
- 条件显示 `Remove from index`，仅针对 Index-only 或缺失记录。
- 显示 Undo 可用性。
- 显示示例文件列表，避免用户误删。
- 在 Trash 不可用时禁用破坏性主操作。

## 布局与内容

Sheet 标题按数量变化：
- `Move 5 files to Trash?`
- 混合选择时：`Review deletion for 5 selected items`

顶部说明：
`Files managed by AreaMatrix will be moved to Trash. Index-only items can be removed from the index without deleting the source files.`

影响摘要卡：
- `3 files will move to Trash`
- `1 index-only item can be removed from the index`
- `1 item is blocked and will be excluded`
- `Undo: available after completion`
- `No files will be permanently deleted`

文件预览：
- 最多显示 8 个文件名。
- 每行显示状态：`Trash`、`Index only`、`Missing`、`Read-only`。
- 超过 8 个显示 `+12 more`。
- blocked 行默认不处理，并在行尾显示原因：Trash unavailable、Read-only、Permission denied 或 External change。

Index-only 说明：
`Removing from index only deletes AreaMatrix's record. The original file stays where it is.`

Trash 不可用说明：
`Trash is not available for this location. AreaMatrix will not permanently delete these files in Stage 2.`

Undo 不可用确认区，仅在本次可处理项无法进入 Undo stack 时显示：
- warning 文案：`Undo will not be available for these items. Review the list before continuing.`
- checkbox：`I understand undo will not be available for these items.`
- 未勾选时禁用 `Move to Trash` / `Move available files to Trash` / `Remove from index`。
- VoiceOver label：`Required confirmation. Undo will not be available for this deletion or index removal.`

底部按钮：
- `Cancel`
- `Remove from index`，仅存在 index-only 或 missing record 时显示。
- destructive `Move to Trash`

## 状态与规则

- 默认态：打开 sheet 后显示影响摘要、文件预览和安全说明。
- 禁用态：Trash 不可用时禁用 `Move to Trash`；没有 Index-only/缺失记录时隐藏 `Remove from index`。
- 加载态：计算 Trash 可用性、权限和所有权时显示 `Checking delete impact...`。
- 空态：多选为空时显示 `No items selected`，只提供 `Close`。
- 错误态：影响计算失败时显示 `Could not prepare deletion` 和 `Retry`，不允许提交。
- 恢复态：部分失败后停留结果摘要，允许 `Retry failed` 或关闭返回主窗口。
- 没有可删除 repo-managed 文件时隐藏或禁用 `Move to Trash`。
- Trash 不可用时禁用 `Move to Trash`，不提供永久删除替代。
- Index-only 条目不会进入 Trash，只能 `Remove from index`。
- 缺失文件记录可以从索引移除，但要说明磁盘文件已不存在。
- 只读、权限不足、外部已变化或 Trash 不可用的文件列为 blocked，默认不处理；主按钮可处理其余可处理项，但执行前摘要必须显示 processed/excluded/blocked 数量。
- 当存在 blocked 项时，主按钮文案改为 `Move available files to Trash`，并在按钮上方显示 `Blocked items will be left unchanged.`。
- 操作成功后显示 Undo toast；Undo 能力不可用时必须在 sheet 中提前说明。
- Undo 不可用时，必须显示确认 checkbox；未勾选前禁用所有会写入的按钮。
- Trash restore 失败时 Undo 历史显示阻塞原因，不再次删除文件。
- 部分失败后停留结果摘要，保留成功/失败列表和 `Retry failed` 入口。

## 交互

1. 打开 sheet 时计算影响摘要，不立即执行删除。
2. 用户可展开文件预览查看完整列表。
3. 点击 `Move to Trash` 或 `Move available files to Trash` 只处理可移动到 Trash 的 repo-managed 文件；blocked 项保持原状。
4. 点击 `Remove from index` 只处理 Index-only/缺失记录，不触碰源文件。
5. 执行中按钮显示 `Moving...` 或 `Removing...`，禁止重复提交。
6. 部分失败时显示结果摘要：成功数量、失败数量、失败原因，并提供 `View details`。
7. Undo 不可用时，用户必须先勾选确认 checkbox，按钮才可提交。
8. Cancel 不移动文件、不移除索引、不写 change_log。

## 可访问性

- 键盘：文件预览、确认 checkbox、Cancel、Remove from index 和 destructive 按钮均可 Tab 到达。
- 焦点：打开 sheet 时焦点落在标题或影响摘要；Undo 不可用时焦点顺序必须经过确认 checkbox 后才能到提交按钮。
- VoiceOver：读出删除影响、Trash / Index-only / blocked 分类、Undo 可用性和 destructive 按钮含义。
- 错误关联：Trash 不可用、权限失败、外部变化和部分失败必须关联到影响摘要或文件行。
- 状态表达：危险、blocked、Index-only、Missing 不能只靠颜色或图标；必须有文字状态和可读说明。

## 数据与依赖

- Batch selection model。
- File ownership/index-only 状态。
- Trash API 和可用性检测。
- Batch delete API。
- Undo stack。
- Permission/read-only detection。
- Change log 写入。

## 验收清单

- 删除前必须看到数量、影响类型和示例文件。
- 默认删除进入 Trash，不提供永久删除。
- Index-only 的“移除索引”不会删除源文件。
- Trash 不可用时 destructive 操作不可用。
- blocked 项默认 excluded，且执行前能看到 processed/excluded/blocked 数量。
- 部分失败时能看到哪些失败以及为什么。
- 操作成功后有 Undo toast，且 change log 有记录。
- VoiceOver 能读出 destructive 按钮和影响摘要。
- Undo 不可用时必须有确认 checkbox；未勾选时 destructive / index removal 按钮禁用。
- VoiceOver 能读出 Undo 不可用确认要求和 checkbox 状态。
- Undo 不可用、Trash 不可用、Trash restore 失败都有明确文案和恢复路径。

## 来源

- `docs/ux/deep-features.md#34-批量删除确认`（直接来源）。
- `docs/ux/dedup-conflict.md` 的可逆性与安全承诺（组合来源）。
- Stage 1 删除/错误恢复原则，依据现有文档推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
- [S2-15 command-palette](S2-15-command-palette.md)
