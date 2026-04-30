# S2-14 batch-rename - 批量重命名

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-14
> 页面类型：批量
> 页面文件：`S2-14-batch-rename.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 批量操作
- **建议目录**：`apps/macos/AreaMatrix/Features/BatchActions/`
- **建议组件**：`BatchRenameSheet`、`RenameRuleEditor`、`BatchRenamePreviewTable`
- **实现说明**：批量重命名必须先预览每个文件的新名称和冲突状态。

## 页面背景

用户希望对多个文件统一添加前缀、日期、序号或替换文本。

入口：Detail multi 的 `Rename...`、列表右键菜单、命令面板上下文命令。
退出：Apply 成功后返回主窗口并显示 Undo toast；Cancel 不改变文件名；冲突或失败时停留预览/结果摘要。

## 页面功能

- 选择重命名策略。
- 输入模板或替换规则。
- 展示逐文件预览。
- 校验非法名称和重名冲突。
- 执行后可 Undo。

## 布局与内容

标题：`批量重命名`

策略 segmented control：

- `Prefix`
- `Date prefix`
- `Keep base + sequence`
- `Replace text`

通用规则：

- 所有策略默认保留原扩展名；扩展名定义为最后一个 `.` 之后的部分，包含点一起保留，例如 `合同.final.pdf` 的 stem 是 `合同.final`，extension 是 `.pdf`。
- 新名称只改 stem，不允许策略修改 extension。
- Preview 默认按当前 List 排序生成；用户改变排序、选择集或规则后，旧 preview 失效。
- 输出名称必须经过 name sanitizer；非法字符、空文件名、`.`、`..`、尾随 `/` 都标记 `ERROR`。
- 目标重名检查同时覆盖同一批次内部重复和目标目录已有文件。
- Index-only 条目不重命名源文件，只更新 AreaMatrix display name；预览行状态显示 `DISPLAY_ONLY`。

策略字段与公式：

| 策略 | 字段 | 输出公式 | 禁用 / 特殊规则 |
|---|---|---|---|
| `Prefix` | `Prefix` 文本框，默认空 | `{prefix}{stem}{ext}` | Prefix 为空且所有输出不变时，Apply 禁用并显示 `No filename changes.` |
| `Date prefix` | `Date source`: Imported / Modified / Today，默认 Imported；`Date format` 默认 `yyyy-MM-dd`；`Separator` 默认 `_` | `{formattedDate}{separator}{stem}{ext}` | 所选日期缺失时该行标记 `ERROR`；日期格式非法时 preview 整体失败 |
| `Keep base + sequence` | `Separator` 默认 `_`；`Start number` 默认 `1`；`Padding` 默认 `2` | `{stem}{separator}{sequence}{ext}` | sequence 按 preview 排序稳定生成；padding 不足时自动扩展到最大序号位数 |
| `Replace text` | `Find`、`Replace with`、`Case sensitive` toggle，默认 false | `stem.replace(find, replacement) + ext` | `Find` 为空时 Apply 禁用；无匹配行标记 `UNCHANGED`；全部无匹配时 Apply 禁用 |

字段示例：

- Prefix：`ProjectA_` -> `合同.pdf` 变为 `ProjectA_合同.pdf`
- Date prefix：Imported date `2026-04-29` + `_` -> `2026-04-29_合同.pdf`
- Keep base + sequence：start `1`、padding `2` -> `合同_01.pdf`
- Replace text：find `草稿` replace `final` -> `合同_final.pdf`

预览表列：

- Original
- New
- Status

示例：

- `合同.pdf -> ProjectA_合同.pdf | OK`
- `报告.pdf -> ProjectA_报告.pdf | NAME`
- `缺失.pdf -> ProjectA_缺失.pdf | MISSING`
- `只读.pdf -> ProjectA_只读.pdf | READONLY`
- `外部索引.pdf -> ProjectA_外部索引.pdf | DISPLAY_ONLY`
- `旧名.pdf -> 旧名.pdf | UNCHANGED`

按钮：`Refresh preview`、`Cancel`、`Apply`。

按钮语义：
- `Refresh preview` 是次按钮，只重新计算预览，不写文件。
- `Apply` 是确认动作；只有预览中所有可处理行均为 `OK` 或 `DISPLAY_ONLY`、没有阻塞状态、且至少一行会变化时启用。
- `Cancel` 不重命名文件、不写 change_log。
- 本页没有永久删除或 Replace 动作；重命名冲突必须先解决，不能静默跳过。

## 状态与规则

- 默认态：规则变化后自动刷新预览；用户也可点击 `Refresh preview`。
- 禁用态：存在 `ERROR`、`NAME`、`MISSING`、`READONLY`、`EXTERNAL_CHANGE` 时禁用 Apply；只有 `UNCHANGED` 行不阻塞，但所有行均 `UNCHANGED` 时禁用 Apply。
- 加载态：预览计算中显示 `Refreshing preview...`，Apply 禁用。
- 空态：当前多选为空时显示 `No files selected`，只提供 `Close`。
- 错误态：rename preview API 失败显示 `Could not preview rename` 和 `Retry`。
- 恢复态：部分执行失败后显示结果摘要；成功项保留，失败项列出原因和可重试性。
- 非法文件名标记 `ERROR`。
- 目标重名标记 `NAME`。
- 缺失文件标记 `MISSING`。
- 权限不足或只读文件标记 `READONLY`。
- 预览生成后文件被外部移动或改名标记 `EXTERNAL_CHANGE`。
- Index-only 记录标记 `DISPLAY_ONLY`，Apply 只更新 AreaMatrix display name，不触碰源文件路径。
- Replace text 对某行没有匹配时标记 `UNCHANGED`，不会为该行写 rename change_log。
- 冲突优先级：`MISSING` / `EXTERNAL_CHANGE` 高于 `READONLY`，高于 `ERROR`，高于 `NAME`，高于 `DISPLAY_ONLY`，高于 `UNCHANGED`，最后是 `OK`。
- 存在任何阻塞状态时禁用 Apply。
- Apply 必须绑定最近一次 preview；用户修改规则、排序或选择集后旧 preview 失效，并禁用 Apply 直到刷新完成。
- Apply 后每个实际改名文件写 rename change_log；每个 Index-only display name 更新写 metadata/display-name change_log。
- 成功后显示 Undo toast；Undo 反向 rename，失败时进入 Undo 历史阻塞态。
- Index-only 的 Undo 只恢复 AreaMatrix display name，不尝试恢复或改动源文件。

## 交互

- 修改规则后自动或手动刷新预览。
- Apply 执行批量 rename；Index-only 行只执行 display name 更新。
- Undo 对 repo-managed 文件执行反向 rename；对 Index-only 行恢复旧 display name。
- 执行中按钮显示 `Renaming...`，禁止重复提交。
- Cancel 不重命名文件、不写 change_log。
- 点击错误行显示具体原因：非法字符、目标已存在、缺失、外部变更、只读或 display-only。

## 可访问性

- 键盘：策略 segmented control、规则字段、预览表、Cancel、Preview 和 Apply 均可键盘操作。
- 焦点：规则变化导致 preview 失效时焦点保持在当前字段；Apply 失败时焦点移到结果摘要。
- VoiceOver：读出策略名、字段值、Original / New 名称、状态和 Apply 禁用原因。
- 错误关联：非法名称、目标重名、日期格式错误和只读/缺失状态必须关联到字段或预览行。
- 状态表达：OK、ERROR、NAME、MISSING、READONLY、DISPLAY_ONLY、UNCHANGED 不能只靠颜色；每行必须显示文字状态。

## 数据与依赖

- Rename preview API。
- name sanitizer。
- conflict detection。
- Undo stack。
- Permission/read-only detection。
- Index-only display name update API。
- Change log。

## 验收清单

- 执行前能看到每个文件新名称。
- 四种策略的字段、公式、扩展名保留规则和排序稳定性可测试。
- Prefix 为空且全部不变时不能 Apply。
- Date prefix 的日期来源、格式错误和缺失日期有明确状态。
- Keep base + sequence 的 start number、padding 和排序稳定性可验证。
- Replace text 的 find 为空、部分无匹配、全部无匹配都有明确禁用或 `UNCHANGED` 状态。
- 冲突和非法字符会阻止执行。
- 执行后可撤销。
- NAME、ERROR、MISSING、READONLY、EXTERNAL_CHANGE 会阻止 Apply。
- Index-only 行只改 display name，不重命名源文件，并且 Undo 只恢复 display name。
- Apply 是确认动作，且必须基于最新 preview。
- 部分失败后有结果摘要、失败原因和 Undo 状态。

## 来源

- `docs/roadmap/milestones.md#stage-2体验完善约-4-个月`（依据现有文档推导）。
- `docs/ux/deep-features.md#3-批量操作batch-actions`（组合来源）。
- 本页批量重命名状态与恢复规则依据 Stage 2 高级文件操作目标推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
- [S2-15 command-palette](S2-15-command-palette.md)
