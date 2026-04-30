# S2-21 import-conflict-batch - 导入冲突批量决策

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-21
> 页面类型：冲突增强
> 页面文件：`S2-21-import-conflict-batch.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 批量导入冲突处理。
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/ImportConflictBatchSheet.swift`。
- **建议组件**：`ImportConflictBatchSheet`、`ConflictStrategyPicker`、`ConflictItemRow`、`ReplaceSecondConfirmSheet`。
- **实现说明**：本页只处理导入 staging 中的冲突策略，不直接改写已有文件；危险策略必须二次确认。

## 页面背景

用户批量导入文件时可能遇到 hash duplicate 或同名不同内容。Stage 1 可逐个处理，Stage 2 需要批量策略减少打断，同时不能让 `Replace` 变成静默覆盖。

入口：Batch Import Sheet 检测到 1 个以上冲突；导入结果中的 `Review conflicts`；命令面板 `Review import conflicts`。
退出：应用批量策略后返回导入进度或导入结果；Cancel 不提交策略；`Ask per item` 按当前作用域进入逐项冲突处理队列，内容重复进入 `S1-22 conflict-duplicate`，同名不同内容进入 `S1-23 conflict-name`，逐项 Replace 二次确认进入 `S1-24 replace-confirm`。

## 页面功能

- 按冲突类型分组展示：hash duplicate、same-name different-content。
- 为 hash duplicate 提供 `Skip`、`Keep both`、`Replace`。
- 为 same-name different-content 提供 `Keep both (auto-number)`、`Ask per item`、`Replace`。
- 默认策略安全：hash duplicate 默认 `Skip`，same-name different-content 默认 `Keep both (auto-number)`。
- 支持按类型全量应用或只处理用户显式勾选的冲突行。
- Replace 必须二次确认，并显示会被移动到 Trash 或替换的已有文件数量。
- 显示结果摘要、部分失败原因、Undo 和 change_log 状态。

## 布局与内容

Sheet 标题：`Resolve 12 import conflicts`

摘要区：
- `8 duplicates by content`
- `4 files with the same name but different content`
- `Existing files will not be replaced unless you explicitly choose Replace.`

策略区：
- `Duplicates by content`: `Skip` / `Keep both` / `Replace`
- `Same name, different content`: `Keep both (auto-number)` / `Ask per item` / `Replace`
- `Apply this strategy to all similar conflicts` checkbox，默认开启。
- 开启时：每个策略 picker 作用于当前导入批次中同一 conflict type 的全部冲突。
- 关闭时：策略只作用于冲突列表中用户显式勾选的行；未勾选行保持 `Pending`，不会被本次 `Apply strategy` 或 `Ask per item` 处理。
- 作用域计数：`Will apply to 8 duplicate conflicts and 4 same-name conflicts.` 或 `Will apply to 3 selected conflicts.`

冲突列表：
- Selection checkbox，只有关闭 `Apply this strategy to all similar conflicts` 时可用。
- File name
- Conflict type
- Existing location
- Incoming source
- Selected action
- Status: `Ready`、`Pending`、`Needs confirmation`、`Blocked`、`Failed`
- 行尾说明：`Included by type rule`、`Selected manually`、`Not selected`、`Blocked: Trash unavailable`。

Replace 二次确认：
- 标题：`Replace 3 existing files?`，数量必须等于当前作用域内会 Replace 的已有文件数量。
- 文案：`Existing files in the selected scope will be moved to Trash before imported files take their place. AreaMatrix does not permanently delete files in Stage 2.`
- 作用域摘要：`Scope: all same-name conflicts in this import` 或 `Scope: 3 selected conflicts`。
- 按钮：`Cancel`、destructive `Move existing files to Trash and Replace`

底部按钮：
- `Cancel`
- `Ask per item`
- 主按钮 `Apply strategy`

按钮语义：
- `Apply strategy` 只处理当前作用域内的 included rows，不处理 `Pending`、`Blocked` 或未勾选行。
- `Ask per item` 不执行批量策略；按当前作用域打开逐项处理队列，未勾选行保持在批量冲突列表中。
- `Cancel` 不替换、不移动、不删除已有文件，不清空 staging，不改变行选择。

## 状态与规则

- 默认态：展示冲突摘要、默认安全策略和列表预览。
- 禁用态：存在 `Replace` 但尚未完成二次确认、当前作用域为空、作用域内全部行 blocked、或关闭全量作用域但未勾选任何行时禁用 `Apply strategy`。
- 加载态：计算 hash、目标路径和 Trash 可用性时显示 `Checking conflicts...`。
- 空态：冲突已被外部解决时显示 `No conflicts remain`，只提供 `Close`。
- 错误态：冲突检测失败或 staging 不可写时显示 `Could not prepare conflict strategy` 和 `Retry`。
- 恢复态：策略应用部分失败后停留结果摘要，成功项保留，失败项可 `Retry failed` 或 `Ask per item`。
- hash duplicate 默认 `Skip`，不导入重复内容，不删除已有文件。
- same-name different-content 默认 `Keep both (auto-number)`，为 incoming 文件生成安全新名称。
- `Apply this strategy to all similar conflicts` 开启时，不显示可交互行选择；每个分组的策略作用于该 conflict type 的全部当前冲突。
- `Apply this strategy to all similar conflicts` 关闭时，行选择启用；没有勾选行时 `Apply strategy` 和 `Ask per item` 禁用并显示 `Select at least one conflict.`
- 作用域变化后必须重新计算 affected count、Replace count、blocked count 和 `Selected action` preview。
- `Ask per item` 不执行批量策略；按当前作用域进入逐项处理队列。hash duplicate 行进入 `S1-22 conflict-duplicate`，same-name different-content 行进入 `S1-23 conflict-name`；逐项选择 Replace 时再进入 `S1-24 replace-confirm`。
- `Replace` 必须确认 Trash 可用；Trash 不可用时禁用 Replace，不提供永久删除。
- Index-only 目标不得被 Replace 覆盖；只能 Keep both 或 Ask per item。
- Index-only 行选择 Replace 时立即标记 `Blocked`，不允许通过二次确认绕过。
- 未勾选或不在当前作用域的冲突行保持 staging unresolved，不写 change_log，不进入 Undo stack。
- 操作成功后写 import/change_log；可逆项进入 Undo stack。

## 交互

1. 打开 sheet 时按冲突类型分组并应用默认策略。
2. 用户切换全量作用域 checkbox 时刷新行选择、作用域计数和策略 preview，不写文件。
3. 关闭全量作用域后，用户通过行 checkbox 选择本次要处理的冲突；未选行显示 `Pending`。
4. 用户切换策略后立即刷新 preview，不写文件。
5. 选择 Replace 时打开二次确认；取消确认后策略回到上一个安全值，并清除本次 Replace confirmation。
6. 点击 `Ask per item` 按当前作用域打开逐项处理队列；队列处理结束后回到批量导入进度或剩余冲突列表。
7. 点击 `Apply strategy` 只对当前作用域执行 staging 决策和导入继续流程。
8. 执行中按钮显示 `Applying...`，禁止重复提交。
9. 部分失败显示成功、失败、skipped、replaced、kept-both 和 pending 数量。
10. Cancel 不替换、不移动、不删除已有文件，不清空 staging。

## 可访问性

- 键盘：策略 picker、作用域 checkbox、行选择、Ask per item、Apply strategy、Replace 二次确认和 Cancel 均可键盘操作。
- 焦点：Replace 二次确认关闭后焦点回到对应策略 picker；部分失败后焦点移到结果摘要。
- VoiceOver：读出冲突类型、作用域、当前策略、Selected action、Replace 数量、blocked 原因和 pending 状态。
- 错误关联：Trash 不可用、staging 不可写、Index-only blocked 和策略应用失败必须关联到冲突行或摘要。
- 状态表达：Ready、Pending、Needs confirmation、Blocked、Failed 和危险策略不能只靠颜色或图标。

## 数据与依赖

- Import staging conflict list。
- Hash duplicate detector。
- Same-name conflict resolver。
- Trash API and availability。
- Auto-number name generator。
- Conflict row selection state。
- Per-item conflict routing to S1-22 / S1-23 / S1-24。
- Affected count and replace count calculator。
- Import apply strategy API。
- Undo stack and change_log。

## 验收清单

- hash duplicate 和同名不同内容有不同默认策略。
- 默认不会 Replace、不会删除、不会覆盖已有文件。
- Replace 必须二次确认，且 Trash 不可用时禁用。
- 全量作用域开启时按 conflict type 全部处理；关闭时只处理显式勾选行。
- 作用域计数、Replace 数量和 blocked 数量与二次确认文案一致。
- Ask per item 不执行批量策略，并能按类型进入 S1-22 / S1-23 / S1-24。
- 未勾选行保持 pending，不写 change_log、不进入 Undo stack。
- 部分失败有结果摘要和恢复动作。
- Index-only 目标不会被覆盖或删除。
- 成功策略写 change_log，并在可逆时显示 Undo toast。
- VoiceOver 能读出冲突类型、选中策略、危险确认和 blocked 原因。

## 来源

- `docs/ux/dedup-conflict.md#批量导入的冲突策略不打断`（直接来源）。
- `docs/ux/dedup-conflict.md#replace二次确认规范`（组合来源）。
- `docs/roadmap/milestones.md#stage-2体验完善约-4-个月`（依据现有文档推导）。
- 本页批量策略、Trash 和 Index-only 边界依据 Stage 2 安全约束推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
- [S2-15 command-palette](S2-15-command-palette.md)
- [S1-22 conflict-duplicate](../stage-1-mvp/S1-22-conflict-duplicate.md)
- [S1-23 conflict-name](../stage-1-mvp/S1-23-conflict-name.md)
- [S1-24 replace-confirm](../stage-1-mvp/S1-24-replace-confirm.md)
