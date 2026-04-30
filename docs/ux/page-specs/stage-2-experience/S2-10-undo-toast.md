# S2-10 undo-toast - Undo toast

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-10
> 页面类型：Undo
> 页面文件：`S2-10-undo-toast.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS Undo 反馈。
- **建议目录**：`apps/macos/AreaMatrix/Features/Undo/UndoToastView.swift`。
- **建议组件**：`UndoToastView`、`UndoToastPresenter`、`UndoActionSummary`。
- **实现说明**：toast 只展示最近一次可撤销操作，不替代完整 Undo 历史面板。

## 页面背景

用户完成移动、重命名、批量加标签、批量删除等操作后，需要立即知道操作已完成，并有短时间内撤销的入口。toast 不能挡住主要操作，也不能让高风险动作变得含糊。

入口：可撤销操作成功提交后。
退出：用户点击 Undo、toast 自动消失、用户关闭、后续操作替换当前 toast。

## 页面功能

- 简短总结刚完成的操作。
- 提供 `Undo` 主动作。
- 提供 `View history` 进入 Undo 历史面板。
- 在刚完成 Undo 且 redo stack 可用时，提供进入 `S2-22 redo` 的反馈入口。
- 显示操作影响数量。
- 显示撤销不可用原因，例如已过期或被后续操作覆盖。
- 对删除类操作明确说明文件进入 Trash。

## 布局与内容

位置：主窗口底部居中或右下角，避开 Import progress、搜索框和系统 sheet。macOS 原生风格，圆角适中，不做大面积彩色背景。

内容示例：
- `Moved 5 files to Documents.`
- `Renamed 12 files.`
- `Moved 3 files to Trash.`
- `Added tag “finance” to 24 files.`

操作：
- 主按钮：`Undo`
- 次按钮：`View history`
- 关闭按钮：`×`

Undo 后内容示例：
- `Undone: renamed 12 files.`
- 主按钮：`Redo`
- 次按钮：`View history`

进度/时间：
- 可显示轻量倒计时进度条，表示 toast 自动隐藏时间，不代表 Undo 过期时间，除非产品明确绑定。

## 状态与规则

- 默认态：最近一次可撤销操作成功后显示操作摘要和 `Undo`。
- 禁用态：Undo action 已过期、被后续写操作阻塞或权限/Trash 不可用时禁用 `Undo` 并显示原因，`View history` 和关闭按钮仍可用；执行中禁用 `Undo` 防止重复提交。
- 空态：没有可提示操作时不显示 toast，不占用 overlay 区域。
- 加载态：执行 Undo 时按钮显示 `Undoing...` 并禁用。
- 错误态：Undo 失败时显示错误 toast，提供 `View details` 打开 `S2-11 undo-history`。
- 恢复态：toast 自动隐藏不等于 Undo 过期；过期和阻塞状态由 Undo stack 与 `S2-11 undo-history` 决定。
- 只有可撤销操作显示 `Undo`。
- 操作不可撤销时显示普通 completion toast，不显示 Undo 按钮。
- 删除类 toast 文案必须是 `Moved ... to Trash`，不要写 `Deleted`。
- 新可撤销操作出现时替换旧 toast，但旧操作仍可在历史面板中看到，前提是 Undo 栈支持。
- Undo 成功后如果 redo stack 可用，toast 可切换为 `Redo`；任何新的写操作会清空 redo stack，并隐藏 `Redo`。
- Undo 执行中禁用按钮并显示 `Undoing...`。
- Undo 失败时显示错误 toast，提供 `View details`。

## 交互

1. 操作成功后 presenter 接收 `UndoableActionSummary`。
2. toast 出现并自动聚焦不抢走键盘焦点。
3. 用户点击 `Undo` 后调用 undo stack，对应行显示 `Undoing...`。
4. Undo 成功后 toast 变为 `Undone` 并短暂停留。
5. 点击 `View history` 打开 `S2-11 undo-history`。
6. 按 Cmd+Z 时，如果 toast 可见，执行同一个 undo action，并同步 toast 状态。
7. Undo 成功后点击 `Redo` 进入 `S2-22 redo` 的同一 redo action；若 redo 已失效，显示原因并打开历史面板。

## 可访问性

- 键盘：toast 不抢走当前焦点，但 `Undo`、`Redo`、`View history` 和关闭按钮可通过系统焦点顺序访问。
- 焦点：用户主动进入 toast 后，关闭或操作完成应回到进入 toast 前的控件。
- VoiceOver：toast 出现时公告操作完成、影响数量、Undo/Redo 可用性和禁用原因。
- 错误关联：Undo 失败必须读出失败原因，并提供进入 Undo History 的可读入口。
- 状态表达：倒计时、成功、失败和过期状态不能只用颜色或进度条表达。

## 数据与依赖

- Undo stack。
- Operation summary，包括 action type、affected count、file names sample。
- Toast presenter/global overlay。
- Error mapping for undo failure。
- Keyboard shortcut handler。
- Redo stack availability。

## 验收清单

- 移动、重命名、加标签、移到 Trash 操作都有不同文案。
- 删除类文案明确进入 Trash。
- Undo 按钮执行中有禁用和进度状态。
- Cmd+Z 与 toast Undo 指向同一个操作。
- toast 不遮挡 sheet 底部主按钮。
- VoiceOver 能公告操作完成和 Undo 可用。
- toast 自动隐藏后，Undo 历史仍能展示该操作是否可撤销。
- Undo 成功后可用 Redo 时有明确文案；新写操作后 Redo 不再显示。

## 来源

- `docs/ux/deep-features.md#1-撤销系统undo`（直接来源）。
- `docs/ux/ui-states.md`（组合来源）。
- 本页 toast 位置和文案依据现有文档推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-11 undo-history](S2-11-undo-history.md)
- [S2-22 redo](S2-22-redo.md)
- [S2-13 batch-delete-confirm](S2-13-batch-delete-confirm.md)
- [S2-14 batch-rename](S2-14-batch-rename.md)
