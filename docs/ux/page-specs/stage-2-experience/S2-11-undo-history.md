# S2-11 undo-history - Undo 历史面板

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-11
> 页面类型：Undo
> 页面文件：`S2-11-undo-history.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS Undo 体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Undo/UndoHistoryPanel.swift`。
- **建议组件**：`UndoHistoryPanel`、`UndoHistoryRow`、`UndoPreviewPane`。
- **实现说明**：固定实现为 `UndoHistoryPanel`。toast、Redo toast、菜单和快捷键都只打开同一个 panel，不另做 popover 或 sidebar 变体；长期审计仍看文件 change log。

## 页面背景

toast 只能处理最近一次操作。用户可能希望查看最近多次可撤销操作，确认影响范围后再撤销。本页固定为主窗口级 `UndoHistoryPanel`，由 toast、Redo toast、View 菜单或快捷入口打开；这些入口共享同一份 Undo/Redo stack snapshot 和同一套信息结构。

入口：Undo toast 点击 `View history`、Redo toast 点击 `View history`、菜单 `View > Undo History`、快捷入口。
退出：撤销或重做成功后返回打开前上下文；关闭 `UndoHistoryPanel`；查看某个操作影响文件。

## 页面功能

- 列出最近可撤销操作。
- 显示每个操作的类型、影响数量、时间、是否仍可撤销。
- 选中操作后显示影响摘要。
- 作为唯一 Undo History 容器承接 toast、Redo、菜单和快捷入口。
- 支持撤销最近一项。
- 支持进入最近可 Redo 操作。
- 如果 Undo 栈只允许顺序撤销，应明确说明不能跳过中间操作。
- 显示不可撤销原因：过期、文件已外部变更、应用重启后不可用等。

## 布局与内容

承载形态：固定为 `UndoHistoryPanel`，作为主窗口级 panel 打开；不要实现为 tag popover、sidebar 分组或多个入口各自独立的历史视图。

标题：`Undo History`

顶部状态：
- `5 actions can be undone`
- 如果没有操作：`No undoable actions`

列表行：
- 图标：移动、重命名、标签、删除等。
- 主文本：`Moved 5 files to Documents`
- 副文本：`2 minutes ago · 5 files`
- 状态：`Available`、`Blocked`、`Expired`

右侧或下方预览：
- `Action: Move files`
- `Affected files: 5`
- 示例文件列表最多 5 个。
- `Undo result: files will move back to their previous folders.`

底部按钮：
- `Undo latest`
- `Redo latest`，仅 redo stack 有可用项时显示或启用。
- `Close`
- 选中不可撤销项时按钮禁用并显示原因。

## 状态与规则

- 默认态：有可撤销操作时显示最新操作在顶部，并默认选中最新操作。
- 禁用态：最新操作为 `Blocked`、`Expired`、正在加载或 Undo stack 不可写时禁用 `Undo latest`；redo stack 为空、被新写操作清空或 redo action blocked 时禁用 `Redo latest`；`Close` 始终可用。
- 空历史：显示空态，不显示空白列表。
- 顺序 Undo 模型：只能撤销最上方最新操作；点击旧操作显示说明 `Undo newer actions first.`。
- Redo 模型：只允许重做最近成功 Undo 且未被新写操作清空的操作；点击 `Redo latest` 打开或执行 `S2-22 redo`。
- 操作被外部变更阻塞：显示 `Blocked` 和 `Review details`。
- 删除到 Trash 的撤销：必须确认文件仍可从 Trash 恢复。
- 面板不提供永久清空历史，除非设置页另有定义。
- 加载态：读取 Undo stack snapshot 时显示 `Loading undo history...`。
- 错误态：读取失败显示 `Could not load undo history` 和 `Retry`。
- 恢复态：Undo 失败后该行标记 `Blocked`，保留操作摘要，并提供 `Review details`。
- Stage 2 不承诺跨应用重启后的 Undo；重启后不可用的操作显示 `Expired`。
- 关闭面板必须回到打开前上下文，例如搜索结果、冲突页、批量 sheet 或普通列表，不强制回普通列表。
- 所有入口必须打开同一个 `UndoHistoryPanel`，不能因为入口不同而使用不同的 UI 容器或不同的历史快照。

## 交互

1. 任一入口打开 `UndoHistoryPanel` 时读取 Undo stack snapshot。
2. 点击列表行更新预览，不执行撤销。
3. 点击 `Undo latest` 执行最新可撤销操作。
4. 点击 `Redo latest` 打开或执行 `S2-22 redo` 的最新可重做操作。
5. Cmd+Z 执行同一最新 Undo；Shift+Cmd+Z 执行同一最新 Redo，并刷新面板。
6. 撤销或重做失败时该行标记 `Blocked`，预览显示恢复建议。
7. 面板关闭后不改变 Undo/Redo stack，并恢复打开前焦点。

## 数据与依赖

- Undo stack snapshot。
- Operation summary and affected file samples。
- Trash/restore capability for delete undo。
- Change log mapping，用于链接到文件详情但不替代审计日志。
- Keyboard shortcut handler。
- Redo stack snapshot。

## 验收清单

- 空历史、可撤销、阻塞、过期四类状态都有 UI。
- Undo toast、Redo toast、`View > Undo History` 和快捷入口都打开同一个 `UndoHistoryPanel`。
- 不存在 popover、sidebar 或入口专属历史视图分叉实现。
- 面板清楚说明是否支持跳过旧操作撤销。
- 选中操作不会立即执行。
- 删除撤销会检查 Trash 恢复能力。
- Cmd+Z 和面板状态同步。
- Shift+Cmd+Z、Redo latest 和 S2-22 指向同一 redo action。
- VoiceOver 能读出每条历史的类型、时间、可用性。
- Trash restore 失败时不删除历史行，用户能看到阻塞原因。
- Close 回到打开前上下文，不强制切换到普通列表。

## 来源

- `docs/ux/deep-features.md#1-撤销系统undo`（直接来源）。
- `docs/ux/dedup-conflict.md` 的可逆性原则（组合来源）。
- 本面板作为 Stage 2 可选体验增强，依据现有文档补齐为开发规格，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-22 redo](S2-22-redo.md)
- [S2-12 batch-change-category](S2-12-batch-change-category.md)
- [S2-13 batch-delete-confirm](S2-13-batch-delete-confirm.md)
