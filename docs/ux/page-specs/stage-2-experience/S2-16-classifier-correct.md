# S2-16 classifier-correct - 分类器纠错

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-16
> 页面类型：自定义分类
> 页面文件：`S2-16-classifier-correct.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 分类纠错体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Classifier/ClassifierCorrectionSheet.swift`。
- **建议组件**：`ClassifierCorrectionSheet`、`CategoryPicker`、`RuleSuggestionPanel`。
- **实现说明**：本页纠正 Stage 1 规则分类结果，不引入 AI 判断。是否沉淀为规则由后续规则页处理。

## 页面背景

AreaMatrix 自动分类可能把文件放错位置。用户在文件详情或列表中选择“纠正分类”，应能快速选择正确分类，并决定是否移动文件、是否把这次纠错记成规则。

入口：文件详情 `Correct category`、文件列表右键 `Correct classification`、导入结果中的错误分类反馈。
退出：`Apply correction` 只应用当前文件纠错，成功后回到文件详情或列表；`Edit rule...` 进入 `S2-17 classifier-save-rule`；`Preview impact` 进入 `S2-18 classifier-impact-preview`；取消不改变分类、规则或文件路径。

## 页面功能

- 显示当前文件和当前分类。
- 显示自动分类原因或命中的规则。
- 选择新的目标分类。
- 选择是否移动文件到目标目录。
- 选择是否创建纠错规则。
- 显示影响预览入口。
- 应用后写入 change log。

## 布局与内容

Sheet 标题：`Correct classification`

文件摘要：
- 文件名：`报告.pdf`
- 当前分类：`Documents / Reports`
- 当前路径：`docs/reports/报告.pdf`
- 分类来源：`Matched rule: *.pdf -> Documents / Reports` 或 `Default rule`

目标分类：
- `New category` picker。
- 支持搜索分类。
- `Create new category...` 打开 `S2-19 classifier-rule-editor` 的新建分类草稿；S2-16 不做内联创建。

选项：
- checkbox `Move file to the new category folder`。
  - AreaMatrix 导入并管理的 repo-managed 文件：默认开启。
  - adopted / repo 内既有文件：默认关闭；目标路径 dry-run 通过后用户可手动开启。
  - Index-only、missing、read-only、目标目录不可写：默认关闭且禁用。
  - 该默认值不跟随 Settings 中的 Import 默认存储模式；这里控制的是纠错后的文件整理动作。
- checkbox `Remember this correction as a rule`。

规则建议区，勾选 Remember 后显示：
- 候选关键词：`合同`（来自文件名）。
- 候选关键词：`客户A`（来自来源目录名或相对路径片段）。
- 候选扩展名：`pdf`。
- 来源目录和相对路径只作为关键词候选的解释来源；不得生成 `path`、`source_folder` 或独立 rule object。
- 按钮：`Edit rule...`
- 状态文案：`Apply correction changes only this file. Save a rule from Edit rule or Preview impact.`

底部按钮：
- `Cancel`
- `Edit rule...`，勾选 Remember 时显示，打开 `S2-17 classifier-save-rule`。
- `Preview impact`，勾选 Remember 时显示。
- 主按钮 `Apply correction`

## 状态与规则

- 默认态：显示当前文件、当前分类、分类原因、目标分类 picker 和移动/记住规则选项。
- 禁用态：未选择新分类、目标分类等于当前分类或目标状态不可写时禁用 `Apply correction`。
- 加载态：分类原因或 category tree 加载中时显示 `Loading classification...`。
- 空态：没有可选分类时显示 `No categories available`，提供 `Open classifier settings`。
- 错误态：加载分类原因、目标路径预览或执行纠错失败时显示错误，不写规则。
- 恢复态：失败后保留目标分类、移动选项和 Remember 选择，允许重试或 Cancel。
- 未选择新分类：禁用 Apply。
- 新分类与当前分类相同：禁用 Apply，并提示 `Choose a different category.`。
- 目标目录不可写：移动选项禁用并显示错误；只允许 metadata category update。
- 勾选 Remember 后不能直接创建过宽规则，必须进入规则确认或影响预览。
- 规则建议只能生成当前 `classifier.yaml` 支持的 keyword / extension / priority 草稿；来源目录、相对路径和当前文件名模式不得写成独立匹配字段。
- 移动文件是可撤销操作，应接入 Undo。
- Index-only 文件默认不移动源文件，只更新分类记录。
- 记住规则但未完成规则确认时，`Apply correction` 只应用当前文件纠错，不保存规则。
- `Apply correction` 在任何 Remember 状态下都不得写 classifier 规则；规则写入只能由 `S2-17` 的 `Save rule`、`S2-18` 的 `Save rule only` 或 `Save and apply to existing files` 完成。
- `Edit rule...` 禁用条件：未选择目标分类、分类树不可用、无法生成任何安全规则候选且无法进入手动规则编辑时禁用；禁用时显示原因。
- `Preview impact` 禁用条件：未选择目标分类、没有可预览的规则草稿、规则草稿校验失败或 dry-run 入口不可用。
- 从 `S2-17` 保存失败返回时不自动写入 S2-16 的纠错；S2-17 保留规则草稿并显示失败原因，S2-16 仍保持打开前的目标分类和移动选项。
- 从 `S2-17` Cancel 返回时只丢弃规则草稿，不改变 S2-16 当前纠错草稿。
- 从 `S2-18` Cancel 关闭时不写规则、不重分类现有文件，并回到打开前上下文；从 Back 返回 S2-16 时保留目标分类、移动选项、Remember 选择和规则草稿。
- 执行失败时保持 sheet 打开并显示失败原因；已成功移动或更新的项必须可 Undo 或写入 change_log。

## 交互

1. 打开 sheet 时加载文件当前分类和分类原因。
2. 用户选择新分类后显示目标路径预览。
3. 勾选移动文件后显示 `Will move to ...`。
4. 勾选 Remember 后展开规则建议，并显示“当前文件纠错”和“保存未来规则”是两个动作。
5. 点击 `Edit rule...` 打开 `S2-17 classifier-save-rule`，传入当前文件、当前分类、目标分类、规则候选和 move preference；进入 S2-17 前不写任何规则。
6. 点击 `Preview impact` 打开 `S2-18 classifier-impact-preview`，source page id 为 S2-16；S2-18 的只保存或保存并应用动作负责写规则。
7. 点击 `Apply correction` 只执行当前文件的分类更新和可选移动，不保存规则；成功后显示 Undo toast。
8. 点击 Cancel 不改变分类、规则、文件路径或 change_log，并丢弃本页未保存的规则草稿。
9. 从 S2-17 Cancel 返回时恢复 S2-16 草稿；从 S2-17 Save 成功返回时保留 S2-16 当前文件纠错草稿，用户仍需点击 `Apply correction` 才会改当前文件。
10. 从 S2-18 Back 返回时，保留目标分类、移动选项、Remember 选择和规则草稿。

## 可访问性

- 键盘：category picker、移动 checkbox、Remember checkbox、Edit rule、Preview impact、Cancel 和 Apply correction 均可键盘操作。
- 焦点：打开 sheet 后焦点落在目标分类；从 S2-17/S2-18 Back 返回时恢复到离开前控件。
- VoiceOver：读出当前分类、目标分类、分类原因、移动默认值、Remember 状态和 Apply 禁用原因。
- 错误关联：分类树加载失败、目标路径预览失败、不可写状态和执行失败必须关联到字段或 sheet 错误区。
- 状态表达：repo-managed、adopted、Index-only、missing、read-only 和不可写状态不能只靠图标或颜色。

## 数据与依赖

- File metadata and classification reason。
- Category tree。
- Classification update API。
- File move API。
- Rule suggestion generator。
- Rule draft handoff state for S2-17 / S2-18。
- New category draft route to S2-19。
- Undo stack and change log。

## 验收清单

- 能看到当前分类、目标分类和分类原因。
- 选择相同分类不能提交。
- 移动文件和只改分类的区别清楚。
- Index-only 文件不会被误移动。
- 记住规则会进入规则确认或影响预览，不直接创建宽泛规则。
- `Apply correction` 不会保存 classifier 规则；规则保存只能通过 S2-17 或 S2-18 完成。
- `Edit rule...` 会进入 S2-17，并且失败/取消不会静默改当前文件。
- `Create new category...` 会进入 S2-19 的新建分类草稿，不在 S2-16 内联创建分类。
- 操作成功后有 Undo toast 和 change log。
- repo-managed、adopted、Index-only、missing、read-only、目标不可写的移动默认值明确。
- 移动默认值不跟随 Import 默认存储模式。
- 从 S2-18 返回 S2-16 时草稿和 move preference 不丢失。

## 来源

- `docs/ux/classifier-calibration.md#核心交互-1快速纠错不沉淀规则`（直接来源）。
- `docs/ux/settings-panel.md#tab分类规则classifier`（组合来源）。
- Stage 2 自定义分类规则目标，依据现有文档推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-17 classifier-save-rule](S2-17-classifier-save-rule.md)
- [S2-18 classifier-impact-preview](S2-18-classifier-impact-preview.md)
- [S2-19 classifier-rule-editor](S2-19-classifier-rule-editor.md)
