# S2-23 tag-suggestions - 标签建议

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-23
> 页面类型：标签
> 页面文件：`S2-23-tag-suggestions.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 标签体验。
- **建议目录**：`apps/macos/AreaMatrix/Features/Tags/TagSuggestionsPanel.swift`。
- **建议组件**：`TagSuggestionsPanel`、`SuggestedTagRow`、`SuggestionReasonView`。
- **实现说明**：Stage 2 标签建议只基于文件名、相对路径和来源目录关键词；不是 AI，不读取文件内容，不做语义理解。

## 页面背景

用户不一定记得要给文件加哪些标签。AreaMatrix 可以根据文件名、路径、来源目录和已有标签词库给出可解释建议，用户决定是否采纳。建议失败不能阻塞手动加标签。

入口：Detail Meta 的 `Suggestions...`；导入结果中的 `Review tag suggestions`；命令面板 `Review tag suggestions`。
退出：采纳后刷新当前文件标签并显示 Undo toast；`Ignore` / `Cancel edit` 不写标签关系；生成失败或用户关闭时回 Detail Meta 或导入结果上下文。

## 页面功能

- 显示候选标签和建议理由。
- 支持一键采纳、逐条采纳、编辑后采纳、忽略。
- 防止重复添加当前文件已有标签。
- 创建新标签前执行 slug/displayName 规范化。
- 采纳后写 change_log，并接入 Undo。
- 明确说明建议来源非 AI、非内容读取。

## 布局与内容

Popover 或右侧 panel 标题：`Tag suggestions`

说明：
`Suggestions come from file name and path keywords. File contents are not read.`

候选列表行：
- checkbox
- tag chip：`finance`
- reason：`Matched file name: invoice_2026.pdf`
- source：`File name` / `Path` / `Source folder` / `Existing tag pattern`
- match：`Strong match` / `Weak match`
- 状态：`New tag`、`Already added`、`Invalid`、`Blocked`

顶部操作：
- `Select all`
- `Clear selection`

底部按钮：
- `Ignore`
- `Edit selected...`
- 主按钮 `Apply selected`

轻量 edit mode，同一 panel 内切换，不新增独立页面：
- 标题：`Edit selected tags`
- 说明：`Editing changes pending tag names only. Nothing is written until Apply edited.`
- 每个选中候选一行：
  - 原建议：`finance`
  - `displayName` 文本框，默认建议显示名。
  - `slug` 文本框，默认由 displayName 规范化生成，用户可编辑。
  - reason 只读保留，帮助用户判断是否继续采纳。
  - 状态：`Ready`、`Duplicate`、`Invalid`、`Already added`、`Blocked`
- 顶部错误摘要：`2 tags need attention before applying.`
- 底部按钮：`Cancel edit`、主按钮 `Apply edited`

按钮语义：
- `Apply selected` 是主动作，只给当前文件或当前导入结果中的目标文件添加选中标签。
- `Edit selected...` 是次动作，进入同一 panel 的 edit mode，允许修改 displayName/slug 后再应用。
- `Cancel edit` 返回建议列表，恢复进入 edit mode 前的候选选择和建议值，不写 Tag store 或标签关系。
- `Apply edited` 先创建或复用规范化后的标签，再写入标签关系；任一编辑行 `Invalid`、`Duplicate`、`Already added` 或 `Blocked` 时禁用。
- `Ignore` 关闭建议，不写标签关系，不删除候选。
- 本页没有危险按钮；不会改变分类、路径、文件内容或标签筛选条件。

## 状态与规则

- 默认态：展示候选标签、理由、match 类型和选中状态；`Strong match` 默认选中，`Weak match` 默认不选中。
- 禁用态：没有选中候选、候选全部已添加、tag store 不可写或 slug invalid 时禁用 `Apply selected`。
- 加载态：生成建议时显示 `Finding tag suggestions...`。
- 空态：无建议时显示 `No tag suggestions`，并提供 `Add tag manually` 入口回到 S2-07。
- 错误态：建议生成失败时显示 `Could not generate suggestions`，不阻塞手动标签。
- 恢复态：采纳部分失败后保留失败候选和原因，成功项保留，可 Undo。
- 建议来源只能是文件名、相对路径、来源目录和已有标签词库；不得调用 AI、远程模型或读取文件内容。
- `Strong match` 定义：文件名、相对路径或来源目录 token 与既有 tag 的 slug/displayName 归一化后完整相同，且该 tag 尚未应用到当前文件。
- `Weak match` 定义：部分匹配、相近词、由来源目录推断的新标签、或基于已有标签模式推断但没有完整 token 命中的候选。
- `Strong match` / `Weak match` 是确定性规则，不使用 AI 置信度、语义理解或内容读取结果。
- `Invalid`、`Already added` 和 `Blocked` 候选默认不选中，且不可直接 Apply。
- `Select all` 只选择可写的 `Strong match` 和用户已显式勾选的有效 `Weak match`；不得选择 `Invalid`、`Already added` 或 `Blocked`。
- 已有标签显示 `Already added` 并默认禁用，避免重复写入。
- tag store 不可写时所有候选保留可读，`Apply selected` 禁用并显示原因。
- Ignore 只忽略当前展示，不删除标签定义，不写 change_log。
- edit mode 只编辑待采纳候选的 displayName/slug，不修改已有标签定义，不修改未选候选。
- edit mode 中 slug 为空、非法字符、超过长度、命中保留名、规范化后为空或与已有标签/本批编辑行重复时，该行显示字段级错误并禁用 `Apply edited`。
- edit mode 中 displayName 为空时允许由 slug 回填显示名；slug 不可从空 displayName 生成时显示错误。
- edit mode 中 `Already added` 行不可编辑也不可提交，用户必须返回建议列表取消该候选。
- tag store 只读或不可写时允许进入 edit mode 查看候选，但禁用所有文本框和 `Apply edited`，显示 `Tag store is read-only.`
- `Apply edited` 失败时停留 edit mode，成功项显示 `Applied`，失败项保留字段和值，允许修正后 `Retry failed`；不回滚已成功写入的标签关系。

## 交互

1. 打开 panel 时生成候选，并显示每条理由。
2. 用户勾选或取消候选；`Weak match` 需要用户显式勾选后才进入待采纳集合。
3. 点击 `Edit selected...` 切换到同一 panel 的 edit mode；只带入当前已选且可编辑的候选。
4. edit mode 中修改 displayName 时默认重新生成 slug；用户手动编辑 slug 后，不再被 displayName 自动覆盖，除非点击 `Regenerate slug`。
5. 点击 `Cancel edit` 返回建议列表，恢复 edit mode 入口前的选择和值。
6. 点击 `Apply edited` 校验所有编辑行，创建或复用标签并写入标签关系。
7. 点击 `Apply selected` 直接写入未编辑的选中标签关系。
8. 执行中按钮显示 `Applying...`，禁止重复提交。
9. 成功后刷新 Detail Meta 或导入结果项，并显示 S2-10 Undo toast。
10. 失败时显示成功、失败和 skipped 数量，允许重试失败项或回到手动标签。

## 可访问性

- 键盘：建议列表、checkbox、Edit selected、Apply selected、Ignore 和 Cancel edit 均可键盘操作。
- 焦点：进入 edit mode 后焦点落在第一个可编辑 chip；Apply 或 Cancel edit 后恢复到建议列表。
- VoiceOver：读出建议标签、理由、Strong/Weak match、选中状态、编辑错误和禁用原因。
- 错误关联：生成失败、非法标签、重复标签和应用失败必须关联到建议行或 edit mode 输入。
- 状态表达：Strong/Weak、selected、edited、ignored 和 error 不能只靠颜色或图标。

## 数据与依赖

- Current file metadata。
- Import result item metadata。
- File name / relative path / source folder tokenizer。
- Existing tag registry。
- Tag normalization and duplicate validator。
- Editable suggestion draft state。
- Tag displayName / slug field validators。
- Tag relation write API。
- Undo stack and change_log。
- Deterministic strong/weak match classifier based on file name, relative path, source folder and existing tag registry。

## 验收清单

- 建议理由可见且可解释。
- 明确标注非 AI、非内容读取。
- `Strong match` 和 `Weak match` 的判定规则明确且可测试。
- `Strong match` 默认选中；`Weak match` 默认不选中，需用户显式勾选。
- Invalid、Already added、Blocked 候选不可被 `Select all` 或 `Apply selected` 直接提交。
- 已有标签不会重复写入。
- 用户可逐条采纳、全选采纳、编辑后采纳或忽略。
- `Edit selected...` 在同一 panel 内进入 edit mode，不新增独立页面。
- edit mode 有 displayName 和 slug 字段，Cancel edit 不写入，Apply edited 才写 Tag store 和标签关系。
- displayName/slug 的非法、重复、只读、Already added 状态会阻止 Apply edited。
- 生成失败不阻塞 S2-07 手动添加标签。
- 部分失败有结果摘要和恢复动作。
- 成功后有 Undo toast，Undo 只撤销本次新增标签关系。
- VoiceOver 能读出建议标签、理由、选中状态和禁用原因。

## 来源

- `docs/roadmap/milestones.md#stage-2体验完善约-4-个月`（依据现有文档推导）。
- `docs/ux/deep-features.md#2-标签系统tags`（组合来源）。
- 本页建议来源、非 AI 边界和失败恢复依据 Stage 2 标签体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-07 tags-add](S2-07-tags-add.md)
- [S2-09 batch-add-tags](S2-09-batch-add-tags.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-15 command-palette](S2-15-command-palette.md)
