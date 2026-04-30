# S1-23 conflict-name - 同名不同内容冲突

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-23
> 页面类型：冲突
> 页面文件：`S1-23-conflict-name.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入冲突处理
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/Conflicts/`
- **建议组件**：`NameConflictView / ConflictResolutionView / ReplaceConfirmSheet`
- **实现说明**：当前仓库以文档为主，工程骨架出现后按上述目录落位；若实际骨架命名不同，保持同等功能边界并更新本页。

## 页面背景

这是 AreaMatrix `ImportSheet` 中的一部分，不是完整独立窗口。用户正在导入一个文件，目标位置已经存在同名文件，但 hash 不同。

入口与退出：
- 入口：`ImportSheet` 的冲突区检测到目标目录已有同名文件，且内容 hash 不同。
- 退出：用户选择处理策略后回到导入确认；选择 Replace 时进入 `S1-24 replace-confirm`。
- 取消：沿用 ImportSheet 的 `Cancel`，取消后不发生任何文件系统变更。

本区域只处理“同名但内容不同”的导入分支；重复 hash、Replace 二次确认和 iCloud 冲突分别由相邻页面处理。开发时不要把后续阶段的内容对比详情或智能判断塞进本页。

## 页面功能

- 说明目标位置已有同名文件，但内容不同。
- 对比展示已有文件和当前导入文件。
- 提供保留两份、重命名导入文件两种默认策略。
- `allowReplaceDuringImport=true` 时额外提供替换已有文件策略。
- 默认选择安全策略：保留两份并自动编号。
- 提供定位已有文件和打开目标目录的辅助动作。

## 整体风格

- SwiftUI macOS 原生风格。
- 专业、清晰、安全优先，适合文件管理工具。
- 不使用网页后台式大卡片堆叠，不使用营销页表达。
- 冲突和危险操作使用 warning / destructive 语义，但不要大面积红色恐吓。

## 布局与内容

本区域嵌在 ImportSheet 内，使用 macOS 原生表单和 warning 语义。

冲突区域标题：

```text
冲突：目标位置已有同名文件
```

提示说明：

```text
目标目录中已经存在同名文件，但内容不同。
```

已有文件信息：

- 已存在：`docs/reports/报告.pdf`
- 大小：`860 KB`
- 修改时间：`Apr 20, 2026 09:14`

当前导入文件信息：

- 你的文件：`报告.pdf`
- 来源：`~/Downloads/报告.pdf`
- 大小：`912 KB`
- 修改时间：`Apr 29, 2026 11:30`

对比方式：

- 使用上下两行或左右两列都可以，但字段标签必须明确。
- 不做复杂 diff；Stage 1 只比较路径、大小、修改时间和 hash 结论。
- 不要让用户误以为“同名”就是“重复内容”。

处理选项使用 radio group：

1. `保留两份（自动编号，推荐）`
   说明：导入文件将保存为 `报告 (2).pdf`，不覆盖已有文件。
2. `重命名导入文件...`
   说明：手动指定导入后的文件名。
3. `替换已有文件（危险）`，仅 `allowReplaceDuringImport=true` 时显示
   说明：用当前文件替换目标位置的已有文件，旧文件将移到废纸篓并写入改动日志。

Replace 不可用说明：

- 默认 `allowReplaceDuringImport=false`：不显示 Replace，避免把危险能力作为普通导入路径暴露。
- 设置开启但 Trash 不可用：显示 disabled Replace 和 `Replace requires system Trash`。

默认选择：

- `保留两份（自动编号，推荐）`

辅助按钮：

- `Show existing file`
- `Reveal target folder`

底部按钮沿用 ImportSheet：

- `Cancel`
- `Import` 或 `Continue`

## 状态与规则

选择 `保留两份（自动编号，推荐）` 时：

- 显示最终导入文件名：`报告 (2).pdf`
- 自动编号文件名只读；用户要手动改名时必须选择 `重命名导入文件...`。
- `Import` 可用。

选择 `重命名导入文件...` 时：

- 显示输入框：

```text
新文件名：报告_2026-04-29.pdf
```

- 如果名称仍然冲突，输入框下方显示轻量错误，并禁用 `Import`。
- 如果包含 macOS 非法字符，显示自动修正提示或校验错误。
- 重命名只影响导入的新文件，不影响已有文件。

选择 `替换已有文件（危险）` 时：

- 仅当 `replaceOptionVisibility=enabled` 时出现。
- 显示 warning：

```text
替换操作需要二次确认。旧文件不会直接删除，会移到废纸篓。
```

- `Import` 可改为 `Continue`，点击后进入 `S1-24 replace-confirm`。
- 不允许在本区域直接执行替换。

- 加载态：冲突检测仍在计算 hash 时，区域显示 `Checking conflict...`，radio group 暂不出现，ImportSheet 底部 `Import` 禁用。
- 自动编号失败时：显示 `无法生成可用文件名`，提供 `重命名导入文件...`，不允许继续导入。
- 已有文件无法定位时：`Show existing file` 禁用并显示 `已有文件不再位于目标位置，请重新扫描。`
- 目标目录不可写时：所有已显示的处理选项都保留可读，但底部 `Import` 禁用，错误文本指向权限恢复流程。
- `replaceOptionVisibility=hidden` 时，不显示 Replace，也不改变默认 Keep both 策略。
- `replaceOptionVisibility=disabled` 时，Replace 可显示为 disabled，用于解释 Trash 不可用原因；用户不能选中。
- 空态不适用：本区域只在已确认同名不同内容时渲染；冲突状态消失时返回普通 ImportSheet 冲突区。

## 交互

- 默认保留两份，避免覆盖。
- 自动编号必须预览最终文件名。
- Keep both 的自动编号预览只读。
- 重命名只影响导入的新文件。
- Replace 必须进入二次确认，不得在当前区域直接替换。
- `Show existing file` 可以在主窗口中定位已有文件。
- `Reveal target folder` 打开目标目录。
- 用户在三个 radio 之间切换时，底部按钮状态要立即更新。
- 用户输入新文件名时，校验结果在输入框下方即时显示；不要等点击 Import 后才报错。
- Replace 选项被选中后，底部主按钮文案改为 `Continue`，点击只打开 `S1-24 replace-confirm`。

## 可访问性

对比区域使用字段标签，不只靠左右位置。

补充要求：
- 关键状态不能只依赖颜色或图标表达。
- 主要操作、取消操作、危险操作都要能通过键盘访问。
- 表单错误要和对应输入控件关联。

## 数据与依赖

- 目标路径解析：用于判断 `docs/reports/报告.pdf` 已存在。
- hash 比对：用于确认同名但内容不同。
- 命名校验：复用 ImportSheet 的文件名合法性、自动编号和冲突预告逻辑。
- `allowReplaceDuringImport` settings value。
- Trash availability for Replace。
- Replace 流程：先依赖 `S1-24 replace-confirm` 标记 `Replace confirmed`，最终 Import 执行时旧文件必须移到 Trash 并写入 change_log。
- Finder 定位：`Show existing file` / `Reveal target folder` 依赖平台层能力。

- ImportSheet 需要传入 `existingFile`、`incomingFile`、`targetDirectory`、`suggestedResolvedName` 和当前 `ConflictResolution`。
- UI preview 至少准备三组数据：普通英文名、中文文件名、长文件名。
- UI preview contract 必须覆盖 hash 不同、自动编号成功、自动编号失败三个分支；若 Core 缺少独立 preview API，需由 Swift adapter 用 capability spec 定义的错误和导入 dry-run 等价结果生成，不得依赖产品口头确认。

## 验收清单

- 同名不同内容默认保留两份，不覆盖。
- 页面明确显示已有文件和当前导入文件的路径、大小和修改时间。
- 选择重命名时，文件名冲突或非法字符会阻止继续导入。
- Replace 默认隐藏；开启设置且 Trash 可用时只能进入二次确认，不能直接替换。
- `Show existing file` 能定位已有条目或给出可恢复错误。
- hash 计算中、自动编号失败、目标目录不可写三个异常状态都有可见 UI。
- Replace 选项会改变主按钮文案并进入 `S1-24 replace-confirm`。

## 整体感觉

用户应该明确知道：两个文件只是名字相同，不代表内容相同。AreaMatrix 默认会保留两份并自动编号，避免任何数据丢失。

## 来源

- `docs/ux/dedup-conflict.md#单文件重名不同内容`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-24 replace-confirm](S1-24-replace-confirm.md)
