# S2-22 redo - Redo feedback region / Redo 状态区域

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-22
> 页面类型：Undo / Redo 页面区域
> 页面文件：`S2-22-redo.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS Undo / Redo 反馈区域。
- **建议目录**：`apps/macos/AreaMatrix/Features/Undo/`。
- **建议组件**：`UndoToastView` 的 Redo slot、`UndoHistoryPanel` 的 Redo row、`RedoActionSummary`。
- **实现说明**：本规格不是独立页面、独立 panel 或独立审计日志；它定义 S2-10 Undo toast 与 S2-11 Undo History 中共享的 Redo feedback region。Redo 只重做刚被 AreaMatrix 成功 Undo 的操作。

## 页面背景

用户执行 Undo 后可能发现撤销错了，需要重做。Redo feedback region 嵌入在 S2-10 toast 和 S2-11 Undo History 中，复用同一份 redo stack 状态，不新增独立 Redo 容器。Redo 必须和 Undo 栈语义一致，不能在外部文件变化、新写操作或应用重启后假装可用。

入口：`S2-10 undo-toast` 中 Undo 成功后的 `Redo` slot；`S2-11 undo-history` 的 `Redo latest` row；快捷键 `Shift+Cmd+Z`；命令面板 `Redo latest action`。
退出：Redo 成功后回打开前上下文并显示完成 toast；Redo 不可用时留在宿主 S2-10 或 S2-11 中显示原因，不跳转到独立页面。

## 页面功能

- 在 S2-10 / S2-11 的宿主容器中显示最近可 Redo 操作的摘要、影响数量和来源 Undo。
- 支持 `Shift+Cmd+Z` 与按钮 Redo 同步。
- 展示不可 Redo 原因：新写操作清空、外部变更、过期、应用重启、Trash restore 状态变化。
- Redo 成功后重新写入 change_log 并恢复 Undo 可用状态。
- Redo 失败时保留历史行和阻塞原因。

## 布局与内容

S2-10 toast 中的 Redo slot：
- `Undone: moved 5 files back.`
- 主按钮：`Redo`
- 次按钮：`View history`

S2-11 Undo History 中的 Redo row：
- 顶部状态：`1 action can be redone`
- 行主文本：`Redo: Move 5 files to Documents`
- 副文本：`Available until the next file operation`
- 状态：`Available`、`Cleared`、`Blocked`、`Expired`

按钮语义：
- `Redo` / `Redo latest` 是主动作；执行中显示 `Redoing...` 并禁用。
- `View history` 是次动作，打开 `S2-11 undo-history`。
- `Close` 属于宿主 S2-10 toast 或 S2-11 panel；关闭宿主时回打开前上下文，不改变 undo/redo stack。
- 本页没有危险按钮；Redo 只重做已被用户撤销的 AreaMatrix 操作，仍必须遵守 Trash、Index-only 和 conflict 安全边界。

## 状态与规则

- 默认态：最近一次 Undo 成功且未发生新写操作时显示 Redo。
- 禁用态：redo stack 为空、被新操作清空、应用重启后不可恢复或外部变更阻塞时禁用 Redo。
- 加载态：校验 redo preflight 时显示 `Checking redo...`。
- 空态：没有可重做操作时 S2-10 不显示 Redo slot；S2-11 显示 `No redoable actions`。
- 错误态：Redo 执行失败时显示 `Could not redo action` 和具体原因。
- 恢复态：失败后在宿主 S2-11 中保留 redo row，用户可 `Review details`、重试或关闭。
- 新的写操作会清空 redo stack，包括导入、标签写入、重命名、移动、删除、规则应用。
- Redo 不覆盖外部 FSEvents 造成的变化；外部变化只记录 change_log。
- Stage 2 不承诺跨应用重启后的 Redo；重启后显示 `Expired` 或不显示。
- Trash restore 相关 Redo 必须重新检查 Trash 和目标路径可用性。

## 交互

1. 用户在 S2-10 或 S2-11 执行 Undo 成功后，redo stack 生成一条 redoable action。
2. 用户点击 `Redo` 或按 `Shift+Cmd+Z`。
3. 系统执行 redo preflight，检查外部变更、路径冲突、Trash 可用性和权限。
4. 通过后执行 Redo，按钮显示 `Redoing...`。
5. Redo 成功后显示完成 toast，并让原操作重新进入 Undo stack。
6. Redo 失败时历史行标记 `Blocked`，显示失败原因和恢复建议。
7. 全流程不创建独立 Redo 页面；所有反馈都停留在 S2-10 或 S2-11 的宿主区域。

## 数据与依赖

- Undo / redo stack。
- Operation summary。
- Redo preflight validator。
- Trash / path / permission check。
- Change log。
- Keyboard shortcut handler。
- Command palette command state。
- Host container state：S2-10 Redo slot 或 S2-11 Redo row。

## 验收清单

- Undo 成功后 Redo 可见，且 `Shift+Cmd+Z` 指向同一操作。
- 新写操作会清空 Redo，并显示或记录原因。
- Redo preflight 能阻止外部变更、路径冲突和 Trash 不可用。
- Redo 成功后原操作重新可 Undo。
- 应用重启后不承诺 Redo，可用性文案清楚。
- Redo 失败不会丢历史行，用户能查看阻塞原因。
- VoiceOver 能读出 Redo 可用性、影响数量和禁用原因。
- S2-22 不新增独立页面、独立 panel 或独立历史容器；所有入口复用 S2-10 / S2-11 的 Redo feedback region。

## 来源

- `docs/ux/deep-features.md#1-撤销系统undo`（直接来源）。
- `docs/ux/deep-features.md#4-快捷键体系shortcuts`（组合来源）。
- `docs/roadmap/milestones.md#stage-2体验完善约-4-个月`（依据现有文档推导）。
- 本页 redo stack、新写操作清空和跨重启限制依据现有 Undo 安全边界推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
- [S2-15 command-palette](S2-15-command-palette.md)
