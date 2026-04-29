# S2-21 import-conflict-batch - 同名导入冲突批量决策

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
退出：应用批量策略后返回导入进度或导入结果；Cancel 不提交策略；Ask per item 回到逐项冲突处理。

## 页面功能

- 按冲突类型分组展示：hash duplicate、same-name different-content。
- 为 hash duplicate 提供 `Skip`、`Keep both`、`Replace`。
- 为 same-name different-content 提供 `Keep both (auto-number)`、`Ask per item`、`Replace`。
- 默认策略安全：hash duplicate 默认 `Skip`，same-name different-content 默认 `Keep both (auto-number)`。
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

冲突列表：
- File name
- Conflict type
- Existing location
- Incoming source
- Selected action
- Status: `Ready`、`Needs confirmation`、`Blocked`、`Failed`

Replace 二次确认：
- 标题：`Replace existing files?`
- 文案：`Existing files will be moved to Trash before imported files take their place. AreaMatrix does not permanently delete files in Stage 2.`
- 按钮：`Cancel`、destructive `Move existing files to Trash and Replace`

底部按钮：
- `Cancel`
- `Ask per item`
- 主按钮 `Apply strategy`

## 状态与规则

- 默认态：展示冲突摘要、默认安全策略和列表预览。
- 禁用态：存在 `Replace` 但尚未完成二次确认时禁用 `Apply strategy`。
- 加载态：计算 hash、目标路径和 Trash 可用性时显示 `Checking conflicts...`。
- 空态：冲突已被外部解决时显示 `No conflicts remain`，只提供 `Close`。
- 错误态：冲突检测失败或 staging 不可写时显示 `Could not prepare conflict strategy` 和 `Retry`。
- 恢复态：策略应用部分失败后停留结果摘要，成功项保留，失败项可 `Retry failed` 或 `Ask per item`。
- hash duplicate 默认 `Skip`，不导入重复内容，不删除已有文件。
- same-name different-content 默认 `Keep both (auto-number)`，为 incoming 文件生成安全新名称。
- `Ask per item` 不执行批量策略，只回到逐项处理列表。
- `Replace` 必须确认 Trash 可用；Trash 不可用时禁用 Replace，不提供永久删除。
- Index-only 目标不得被 Replace 覆盖；只能 Keep both 或 Ask per item。
- 操作成功后写 import/change_log；可逆项进入 Undo stack。

## 交互

1. 打开 sheet 时按冲突类型分组并应用默认策略。
2. 用户切换策略后立即刷新 preview，不写文件。
3. 选择 Replace 时打开二次确认；取消确认后策略回到上一个安全值。
4. 点击 `Apply strategy` 执行 staging 决策和导入继续流程。
5. 执行中按钮显示 `Applying...`，禁止重复提交。
6. 部分失败显示成功、失败、skipped、replaced、kept-both 数量。
7. Cancel 不替换、不移动、不删除已有文件，不清空 staging。

## 数据与依赖

- Import staging conflict list。
- Hash duplicate detector。
- Same-name conflict resolver。
- Trash API and availability。
- Auto-number name generator。
- Import apply strategy API。
- Undo stack and change_log。

## 验收清单

- hash duplicate 和同名不同内容有不同默认策略。
- 默认不会 Replace、不会删除、不会覆盖已有文件。
- Replace 必须二次确认，且 Trash 不可用时禁用。
- Ask per item 不执行批量策略。
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

