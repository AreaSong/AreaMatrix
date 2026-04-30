# S2-18 classifier-impact-preview - 规则影响预览

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-18
> 页面类型：自定义分类
> 页面文件：`S2-18-classifier-impact-preview.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 分类规则 UI。
- **建议目录**：`apps/macos/AreaMatrix/Features/Classifier/ClassifierImpactPreviewSheet.swift`。
- **建议组件**：`ClassifierImpactPreviewSheet`、`RuleImpactTable`、`ApplyRuleOptions`。
- **实现说明**：保存规则或重分类现有文件前必须展示影响范围；应用到现有文件属于批量操作，应接入 Undo。

## 页面背景

一条规则可能影响许多现有文件。用户需要在保存或应用前看到影响范围、当前分类、新分类、冲突和不可处理项，避免一个过宽规则把资料库大面积改乱。

入口：`S2-16 classifier-correct` 勾选 Remember 后点击 `Preview impact`；`S2-17 classifier-save-rule` 点击 `Preview impact`；`S2-19 classifier-rule-editor` 点击 `Preview impact`、删除 extension/keyword/category 前查看影响。
退出：Back 返回来源页面并保留草稿；`Save rule only` 只保存规则或编辑草稿；`Save and apply to existing files` 保存并应用到现有文件；Cancel 关闭并不写入。

## 页面功能

- 显示规则摘要。
- 显示受影响文件数量。
- 展示文件当前分类和新分类。
- 标记冲突、缺失、Index-only、不可移动项。
- 允许只保存规则或同时重分类现有文件。
- 显示应用后 Undo 可用性。

## 布局与内容

标题：`Preview rule impact`

规则摘要卡：
- `Rule: file name contains “合同” -> finance/contracts`
- 多依据草稿示例：`Add keyword “合同” and extension “pdf” to finance/contracts`；两者按 classifier matcher 独立生效，不是 AND 条件。
- `Applies to: future imports and existing files if applied now`
- 删除匹配值场景：`Remove keyword “合同” from finance/contracts`
- 删除分类场景：`Remove category “finance/contracts” from classifier.yaml`

影响摘要：
- `24 existing files match this rule`
- `18 will change category`
- `4 already match target category`
- `2 need review`

表格列：
- `File`
- `Current category`
- `New category`
- `Action`
- `Status`

状态示例：
- `Will update`
- `Already correct`
- `Name conflict if moved`
- `Missing file`
- `Index-only`

底部选项：
- checkbox `Move files to new category folders`，默认关闭；仅当来源流程已显式开启移动选项时继承开启。
- `Back`
- 从 S2-16 / S2-17 进入时：`Save rule only`
- 从 S2-19 进入时：`Save classifier changes only`
- 主按钮 `Save and apply to existing files`

来源页提交语义：

| 来源 | 只保存按钮 | 行为 |
|---|---|---|
| S2-16 classifier-correct | `Save rule only` | 保存规则配置，不重分类现有文件，返回来源上下文。 |
| S2-17 classifier-save-rule | `Save rule only` | 保存规则配置，不重分类现有文件，返回来源上下文。 |
| S2-19 classifier-rule-editor | `Save classifier changes only` | 先 Validate 当前编辑器草稿；通过后保存 classifier changes，不重分类现有文件，返回 S2-19。 |

`Save and apply to existing files` 语义：
- 先执行与来源页对应的保存动作。
- 保存成功后只应用 dry-run 表格中 `Will update` 的行。
- 存在 Needs review、路径冲突、dry-run 失败或删除 category 缺少 replacement category 时禁用。
- 保存失败时不进入 apply；apply 部分失败时保存结果保留，成功文件变更进入 Undo stack。

## 状态与规则

- 默认态：dry-run 成功后显示规则摘要、影响摘要、表格和底部操作。
- 禁用态：存在 Needs review、dry-run 失败或 Move 冲突时禁用 `Save and apply to existing files`。
- 加载态：执行 dry-run 时显示 `Previewing impact...`。
- 空态：影响为 0 时显示 `This rule will only affect future imports.`。
- 错误态：dry-run、写规则或批量应用失败时显示错误摘要，不静默改分类。
- 恢复态：失败后保留规则草稿、表格状态和 Move 选择，允许 Retry preview、Back 或 Save rule only。
- 影响为 0：显示 `This rule will only affect future imports.`，允许 Save rule only。
- 影响过大：显示 warning，建议缩小规则。
- 有冲突或不可处理项时，默认不跳过；`Save and apply to existing files` 禁用，用户可 `Save rule only`、点击 Back 缩小规则，或关闭 Move 后重新 dry-run。
- Move 开启时必须执行路径冲突 dry-run。
- classifier dry-run 必须复用当前 `classifier.yaml` matcher 语义；keyword 和 extension 是独立匹配值，不得把多个依据实现成未定义的 AND / OR 复合 rule object。
- 同一草稿同时追加 keyword 与 extension 时，影响数量应覆盖真实 matcher 下会改变分类的所有文件，并清楚标记命中来源为 keyword、extension 或两者均命中。
- Index-only 文件只允许更新分类记录；无论 Move 是否开启，都不得移动、删除或重命名源文件。
- 从 S2-16 进入时保留目标分类、Remember 选择、规则草稿和 move preference；Back 返回 S2-16 后这些草稿不能丢失。
- 从 S2-17 进入时 Move 默认关闭；Back 返回 S2-17 后保留规则依据、priority 和 warning 状态。
- 从 S2-19 进入时使用当前 classifier 编辑草稿；Back 返回 S2-19 后保留 dirty state、last validation result、YAML reload choice 和当前选中分类。
- Apply 成功后必须显示结果摘要和 Undo toast。
- 只保存规则不会修改现有文件或分类。
- `Save rule only` 在冲突存在时仍可用，因为它只影响未来导入。
- 从 S2-19 进入时，底部只保存按钮文案必须为 `Save classifier changes only`，避免误解为只保存单条规则。
- 从 S2-19 进入时，保存前必须执行 classifier editor 的 Validate；Validate 失败时不保存、不 apply，并返回可定位错误。
- `Save and apply to existing files` 必须先完成来源页对应保存动作；保存失败时不得执行现有文件重分类。
- `Save and apply to existing files` 只应用 `Will update` 行，不静默处理 Needs review、冲突或缺少 replacement 的行。
- apply 部分失败时，已保存的 classifier 配置保持生效；成功变更写 change_log 并进入 Undo stack，失败项保留原因和恢复动作。
- dry-run 失败时不允许 Apply，保留规则草稿并显示 `Retry preview`。
- 删除 extension/keyword/category 的影响预览默认只修改 classifier.yaml 草稿；不得移动、删除或重命名历史文件。
- 删除 category 时如用户选择 `Save and apply to existing files`，必须先选择 replacement category；没有 replacement category 时禁用 Apply，只允许 Back 或 Save rule only。

## 交互

1. 页面打开时执行 classifier dry-run。
2. dry-run 期间显示 `Previewing impact...`。
3. 用户可筛选表格：All、Will update、Needs review、Skipped。
4. 点击 Back 返回来源页：S2-16、S2-17 或 S2-19，并保留对应草稿。
5. 从 S2-16 / S2-17 点击 `Save rule only` 写入规则配置并返回；不更新现有文件分类。
6. 从 S2-19 点击 `Save classifier changes only` 先 Validate 再保存当前编辑器草稿并返回；不更新现有文件分类。
7. 点击 `Save and apply to existing files` 先执行对应保存动作，再执行批量分类更新或删除分类 replacement 更新，显示进度和结果。
8. 执行中显示 `Applying rule...`，禁止重复提交。
9. 部分失败时显示成功、失败、阻塞数量；成功项进入 Undo stack。

## 可访问性

- 键盘：表格筛选、Move checkbox、Back、只保存按钮和主按钮均可键盘操作。
- 焦点：Back 返回来源页时恢复来源控件；dry-run 或 apply 失败时焦点移到错误摘要。
- VoiceOver：读出规则摘要、影响数量、表格行状态、Move 含义、按钮文案差异和禁用原因。
- 错误关联：dry-run 失败、Needs review、路径冲突、replacement 缺失和部分失败必须关联到表格或底部错误区。
- 状态表达：Will update、Already correct、Needs review、Index-only、Missing 和 warning 不能只靠颜色。

## 数据与依赖

- Classifier dry-run API。
- Current classifier matcher semantics。
- Rule draft。
- File list and current classification。
- Batch category update API。
- Move dry-run/conflict detection。
- Source flow move preference。
- Undo stack and change log。
- Source page id：S2-16、S2-17、S2-19。
- Source save action：save rule、save classifier editor draft。
- Optional replacement category for category deletion apply。

## 验收清单

- 保存前能看到影响数量和示例文件。
- dry-run 使用真实 classifier matcher，keyword / extension 不被误实现成复合 AND 条件。
- 影响为 0 时文案清楚。
- 过宽规则有 warning。
- 冲突、缺失、Index-only 文件可见。
- Save rule only 不修改现有文件。
- Apply 后有结果摘要、Undo toast 和 change log。
- VoiceOver 能读出表格行状态和底部主按钮含义。
- Needs review 存在时不能静默 Apply。
- dry-run 失败、路径冲突、Index-only、缺失文件都有明确处理。
- Move 默认值和 S2-16/S2-17/S2-19 来源可测试；Index-only 不会触碰源文件。
- Back 来源为 S2-16/S2-17/S2-19 时，目标分类、规则草稿、dirty state 和 move preference 的保留规则可测试。
- S2-16/S2-17 的 `Save rule only` 与 S2-19 的 `Save classifier changes only` 文案和保存语义可区分。
- `Save and apply to existing files` 必须先保存来源草稿；保存失败时不会 apply。
- Apply 只处理 `Will update` 行；Needs review、冲突和 replacement 缺失会禁用 Apply。
- 删除 extension/keyword/category 的预览不会移动、删除或重命名历史文件。
- 删除 category 并 Apply 到现有文件时必须选择 replacement category。

## 来源

- `docs/ux/classifier-calibration.md#preview-impact预览影响范围`（直接来源）。
- `docs/ux/deep-features.md#3-批量操作batch-actions`（组合来源）。
- 冲突阻塞策略依据 Stage 2 安全边界推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-16 classifier-correct](S2-16-classifier-correct.md)
- [S2-17 classifier-save-rule](S2-17-classifier-save-rule.md)
- [S2-19 classifier-rule-editor](S2-19-classifier-rule-editor.md)
