# S2-15 command-palette - 命令面板 Cmd+K

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-15
> 页面类型：命令面板
> 页面文件：`S2-15-command-palette.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 全局快捷操作。
- **建议目录**：`apps/macos/AreaMatrix/Features/CommandPalette/CommandPaletteView.swift`。
- **建议组件**：`CommandPaletteView`、`CommandSearchField`、`CommandResultRow`、`CommandRegistry`。
- **实现说明**：命令面板是导航和动作入口，不绕过原页面的安全确认。删除、Replace、批量移动等高风险命令仍跳对应确认页。

## 页面背景

熟练用户希望通过 Cmd+K 快速搜索命令、跳转页面、打开 Smart List 或执行常用动作。命令面板必须快、可键盘操作，同时不能让危险动作变成“输入即执行”。

入口：快捷键 `Cmd+K`、菜单 `View > Command Palette`。
退出：执行命令、按 Escape、点击面板外区域。

## 页面功能

- 搜索命令。
- 搜索导航目标：Settings、Smart Lists、Needs Review。
- 根据当前选择显示上下文命令：Rename、Add tags、Change category。
- 显示 Redo、标签建议、导入冲突继续处理等上下文命令入口。
- 显示快捷键提示。
- 支持最近使用命令。
- 对危险命令显示确认流程入口，不直接执行。
- 支持无结果状态和搜索分组。

## 布局与内容

面板居中浮层，宽约 640，高度随结果最多 8-10 行。背景使用 macOS material，避免覆盖整屏。

顶部输入框：
- 占位：`Type a command or search...`
- 左侧搜索图标。
- 右侧显示 `Esc` 关闭提示。

结果分组：
- `Commands`
- `Navigation`
- `Current Selection`
- `Recent`

结果行：
- 图标。
- 主标题：`Import files...`
- 副标题：`Open the import sheet`
- 右侧快捷键：`⌘I`。
- 危险命令标记：`Requires confirmation`。
- Redo 命令标记：`Redo available` 或 disabled reason。

空态：
- `No commands found for “...”`
- 建议：`Try “import”, “tag”, or “settings”.`

按钮语义：
- 命令行本身是可选中项，Enter 是主执行动作。
- `Esc` 是关闭动作，恢复打开前焦点。
- 危险命令只显示 `Requires confirmation` 标记，并打开确认页；命令面板内不显示 destructive 按钮。
- 无 repo 或无选择时，相关命令禁用或隐藏，并在副标题说明原因。

## 状态与规则

- 默认态：repo 已打开时显示导航、组织、当前选择和最近命令。
- 禁用态：不可执行命令行保留但禁用，副标题必须说明原因；无选择时 selection commands 隐藏或禁用；Command registry 未就绪时禁用执行但输入框仍可输入；危险命令只允许打开确认页，不能在面板内直接执行。
- 加载态：Command registry 初始化时显示 `Loading commands...`，输入框可聚焦。
- 空态：搜索无匹配时显示建议关键词。
- 错误态：命令注册失败时显示 `Some commands are unavailable`，仍显示可用命令。
- 恢复态：执行命令失败时关闭面板或保留面板按命令类型决定，但必须显示错误并恢复焦点。
- 没有 repo 打开时，只显示可用命令：Open repository、Settings、Help。
- 没有选中文件时隐藏或禁用 selection commands。
- 批量操作命令显示影响数量，例如 `Add tags to 12 files...`。
- 删除、Replace、批量移动等命令只能打开对应确认 sheet。
- 超出 Stage 2 范围的智能化或多端命令不在 Stage 2 面板注册。
- 命令搜索不搜索文件内容；文件搜索仍使用搜索页。
- 命令面板只能导航、聚焦、打开 sheet 或触发低风险即时动作；不得绕过 S2-12、S2-13、S2-14、S2-18 的确认/预览。
- Stage 2 不注册智能化、OCR 或多端命令。
- `Redo latest action` 只在 redo stack 可用时出现或启用，执行语义由 `S2-22 redo` 决定。
- `Review import conflicts` 打开 `S2-21 import-conflict-batch`，不会直接 Replace。
- `Review tag suggestions` 打开 `S2-23 tag-suggestions`，不会自动采纳。

## 交互

1. 按 Cmd+K 打开面板并聚焦输入框。
2. 输入时即时过滤命令，支持模糊匹配。
3. 上下箭头移动选中行，Enter 执行。
4. Cmd+K 再次按下关闭面板。
5. 执行导航命令关闭面板并跳转。
6. 执行需要确认的命令关闭面板并打开对应 sheet。
7. 面板关闭后焦点回到打开前的控件。
8. 执行失败时显示错误 toast 或 inline error，并可重新打开命令面板。

## 数据与依赖

- Command registry。
- App navigation router。
- Current selection context。
- Feature flags/stage capability flags。
- Keyboard shortcut manager。
- Recent commands storage。

## 验收清单

- Cmd+K 可打开/关闭面板。
- 键盘可以完成搜索、选择和执行。
- 无 repo、无选择、多选三种上下文结果不同。
- 危险命令不直接执行，必须进入确认页。
- 执行后焦点恢复合理。
- VoiceOver 能读出结果分组、选中状态和快捷键。
- 超出 Stage 2 范围的命令不会出现在 Stage 2 面板中。
- Delete、batch move、rename、apply rule 只能打开对应确认或预览页。
- Redo、导入冲突、标签建议命令只作为对应页面入口，不绕过 S2-21/S2-22/S2-23 的确认或采纳流程。

## 来源

- `docs/ux/deep-features.md#5-命令面板command-palette-cmdk`（直接来源）。
- Stage 2 批量、标签、Smart List 页面规格（组合来源）。
- macOS 命令面板交互依据现有文档推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-06 smart-lists](S2-06-smart-lists.md)
- [S2-09 batch-add-tags](S2-09-batch-add-tags.md)
- [S2-12 batch-change-category](S2-12-batch-change-category.md)
- [S2-13 batch-delete-confirm](S2-13-batch-delete-confirm.md)
- [S2-14 batch-rename](S2-14-batch-rename.md)
- [S2-21 import-conflict-batch](S2-21-import-conflict-batch.md)
- [S2-22 redo](S2-22-redo.md)
- [S2-23 tag-suggestions](S2-23-tag-suggestions.md)
