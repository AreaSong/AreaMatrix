# S2-07 tags-add - 添加标签 Popover

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-07
> 页面类型：标签
> 页面文件：`S2-07-tags-add.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 标签系统
- **建议目录**：`apps/macos/AreaMatrix/Features/Tags/`
- **建议组件**：`TagEditorPopover`、`TagChipView`、`TagSuggestionList`
- **实现说明**：这是 Detail Meta 中的 popover，不是独立设置页。

## 页面背景

用户正在查看某个文件的 Meta，需要给文件添加已有标签或创建新标签。标签是横向组织维度，不改变文件所在分类。

入口：Detail Meta 的 `+ Add...`，或标签 chip 的删除按钮。
退出：添加/移除成功后刷新 Detail Meta；Esc、点击外部或关闭按钮退出 popover；失败时停留 popover 并保留输入。

## 页面功能

- 展示当前文件已有标签。
- 搜索已有标签。
- 创建新标签。
- 防止重复添加。
- 说明标签和分类的区别。
- 移除当前文件上的标签关系。
- 添加或移除失败时给出恢复动作。

## 布局与内容

Detail Meta 中显示：

```text
Tags: [ urgent ] [ clientA ] [+ Add...]
```

点击 `+ Add...` 打开 popover。

Popover 内容：

- 输入框 placeholder：`Search or create tag...`
- 最近使用标签列表。
- 匹配标签列表。
- 创建新标签行：`Create "clientB"`
- 可选入口：`Suggestions...`，当 `S2-23 tag-suggestions` 有候选时显示。

提示文案：

```text
分类决定“放哪儿”，标签决定“怎么横向组织”。
```

按钮与动作语义：
- 回车或点击高亮候选是主动作：为当前文件添加已有标签或创建并添加新标签。
- chip 上的 `×` 是关系移除动作，只移除当前文件与标签的关联，不删除标签定义。
- `Esc`、点击外部和关闭按钮是退出动作；已完成的标签关系变更保留，未提交输入丢弃。
- `Suggestions...` 打开 `S2-23 tag-suggestions`，不自动采纳任何标签。
- 本页没有危险按钮；不会改变分类、路径或删除标签定义。

## 状态与规则

- 默认态：显示当前文件已有标签、最近使用标签和输入框。
- 禁用态：Tag store 不可用时禁用候选选择、Create 行、chip 删除和 `Suggestions...`；当前文件已拥有的标签候选禁用并显示 `已添加`；输入为空或含非法字符时禁用 Create。
- 加载态：Tag store 加载中时输入框可聚焦，但候选列表显示 `Loading tags...`。
- 空态：没有最近标签和已有标签时显示 `No tags yet`，用户可输入创建。
- 错误态：Tag store 加载失败时显示 `Could not load tags` 和 `Retry`；创建或添加失败时保留输入。
- 恢复态：移除标签失败时 chip 保持原状；添加失败时不写入关系，并允许重试。
- 空输入：显示最近使用标签。
- 输入匹配已有标签：显示候选。
- 输入不存在标签：显示 Create 行。
- 标签已存在于当前文件：候选禁用并显示 `已添加`。
- 非法字符：输入框下方显示错误。
- 删除 chip 只移除当前文件和标签的关联，不删除标签定义。
- 添加/移除成功后显示 Undo toast；Undo 只撤销本次关系变更。

## 交互

- 回车选择高亮候选或创建新标签。
- 点击 chip 的删除按钮可移除标签。
- Esc 关闭 popover。
- 添加成功后 Meta 立即刷新。
- 点击外部关闭 popover；已完成的添加/移除保留，未提交输入丢弃。
- 点击 `Retry` 重新加载候选，不改变当前文件标签。
- 点击 `Suggestions...` 打开标签建议页，返回后刷新当前文件标签。

## 数据与依赖

- Tag store。
- File tags relation。
- Recent tags。
- Tag slug/displayName normalization。
- Undo stack and change_log。

## 验收清单

- 单文件可添加已有标签和新标签。
- 重复标签不会重复写入。
- 标签操作不改变文件分类和路径。
- Tag store 加载失败、创建失败、添加失败、移除失败都有恢复路径。
- 删除 chip 不删除标签定义，只移除当前文件关系。
- Undo 只撤销本次标签关系变更。
- 候选点击、回车、chip 删除、关闭和 Suggestions 入口的动作语义可测试。

## 来源

- `docs/ux/deep-features.md#2-标签系统tags`（直接来源）。
- 标签失败恢复与 Undo 规则依据 Stage 2 标签体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-08 tags-filter](S2-08-tags-filter.md)
- [S2-09 batch-add-tags](S2-09-batch-add-tags.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-23 tag-suggestions](S2-23-tag-suggestions.md)
