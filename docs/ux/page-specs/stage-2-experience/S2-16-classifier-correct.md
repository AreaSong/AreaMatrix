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
退出：应用纠错后回到文件详情或列表；选择“记住规则”进入 `S2-17 classifier-save-rule` 或内联展开规则确认；取消不改变分类。

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
- 可创建新分类入口如果 Stage 2 自定义分类已启用。

选项：
- checkbox `Move file to the new category folder`：repo-managed 文件默认跟随用户现有存储设置；Index-only 文件默认关闭且禁用。
- checkbox `Remember this correction as a rule`。

规则建议区，勾选 Remember 后显示：
- `When file name matches: *.pdf`
- `When source folder is: Downloads`
- `When extension is: pdf`
- 按钮：`Edit rule...`

底部按钮：
- `Cancel`
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
- 移动文件是可撤销操作，应接入 Undo。
- Index-only 文件默认不移动源文件，只更新分类记录。
- 记住规则但未完成规则确认时，`Apply correction` 只应用当前文件纠错，不保存规则。
- 执行失败时保持 sheet 打开并显示失败原因；已成功移动或更新的项必须可 Undo 或写入 change_log。

## 交互

1. 打开 sheet 时加载文件当前分类和分类原因。
2. 用户选择新分类后显示目标路径预览。
3. 勾选移动文件后显示 `Will move to ...`。
4. 勾选 Remember 后展开规则建议，并允许进入规则沉淀页面。
5. 点击 `Preview impact` 打开 `S2-18 classifier-impact-preview`。
6. 点击 `Apply correction` 执行分类更新和可选移动，成功后显示 Undo toast。
7. 点击 Cancel 不改变分类、规则、文件路径或 change_log。
8. 从 S2-18 Back 返回时，保留目标分类、移动选项、Remember 选择和规则草稿。

## 数据与依赖

- File metadata and classification reason。
- Category tree。
- Classification update API。
- File move API。
- Rule suggestion generator。
- Undo stack and change log。

## 验收清单

- 能看到当前分类、目标分类和分类原因。
- 选择相同分类不能提交。
- 移动文件和只改分类的区别清楚。
- Index-only 文件不会被误移动。
- 记住规则会进入规则确认或影响预览，不直接创建宽泛规则。
- 操作成功后有 Undo toast 和 change log。
- repo-managed、Index-only、目标不可写三类文件的移动默认值明确。
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
